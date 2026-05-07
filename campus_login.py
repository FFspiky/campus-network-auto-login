#!/usr/bin/env python3
"""Auto-login helper for campus ePortal networks on Windows startup."""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from pathlib import Path
from string import Formatter
from typing import Any
from urllib.parse import urlencode, urljoin, urlparse

import requests


DEFAULT_CONFIG = {
    "portal_base": "https://wlan.upc.edu.cn/eportal/",
    "check_url": "http://www.msftconnecttest.com/connecttest.txt",
    "check_expected_text": "Microsoft Connect Test",
    "max_wait_seconds": 300,
    "retry_interval_seconds": 10,
    "timeout_seconds": 8,
    "verify_tls": True,
    "login_method": "POST",
    "service": "",
    "password_encrypt": "false",
    "headers": {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/124.0 Safari/537.36"
        )
    },
    "success_indicators": ["success", "认证成功", "登录成功"],
}


DEFAULT_LOGIN_PAYLOAD = {
    "userId": "{username}",
    "password": "{password}",
    "service": "{service}",
    "queryString": "{query_string}",
    "operatorPwd": "",
    "operatorUserId": "",
    "validcode": "",
    "passwordEncrypt": "{password_encrypt}",
}


class LoginError(RuntimeError):
    pass


def load_config(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise LoginError(f"Config file not found: {path}")

    with path.open("r", encoding="utf-8") as file:
        user_config = json.load(file)

    config = DEFAULT_CONFIG | user_config
    config["headers"] = DEFAULT_CONFIG["headers"] | user_config.get("headers", {})
    config["config_dir"] = str(path.parent)

    missing = [key for key in ("username", "password") if not config.get(key)]
    if missing:
        raise LoginError(f"Missing required config field(s): {', '.join(missing)}")

    return config


def setup_logging(config: dict[str, Any]) -> None:
    log_file = config.get("log_file", "campus_login.log")
    log_path = Path(log_file)
    if not log_path.is_absolute():
        log_path = Path(config["config_dir"]) / log_path

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=[
            logging.FileHandler(log_path, encoding="utf-8"),
            logging.StreamHandler(sys.stdout),
        ],
    )


def render_template(value: Any, context: dict[str, Any]) -> Any:
    if isinstance(value, str):
        return SafeFormatter().format(value, **context)
    if isinstance(value, dict):
        return {key: render_template(item, context) for key, item in value.items()}
    if isinstance(value, list):
        return [render_template(item, context) for item in value]
    return value


class SafeFormatter(Formatter):
    def get_value(self, key: Any, args: Any, kwargs: Any) -> Any:
        if isinstance(key, str):
            return kwargs.get(key, "{" + key + "}")
        return Formatter.get_value(self, key, args, kwargs)


def portal_host(config: dict[str, Any]) -> str:
    return urlparse(config["portal_base"]).hostname or ""


def looks_like_portal(url: str, config: dict[str, Any]) -> bool:
    host = urlparse(url).hostname or ""
    return bool(host and host == portal_host(config))


def check_online(session: requests.Session, config: dict[str, Any]) -> tuple[bool, str | None]:
    try:
        response = session.get(
            config["check_url"],
            timeout=config["timeout_seconds"],
            allow_redirects=True,
            verify=config["verify_tls"],
        )
    except requests.RequestException as exc:
        logging.info("Network check failed: %s", exc)
        return False, None

    final_url = response.url
    if looks_like_portal(final_url, config):
        logging.info("Network check redirected to portal: %s", final_url)
        return False, final_url

    expected_text = str(config.get("check_expected_text", ""))
    if response.ok and expected_text and expected_text in response.text:
        logging.info("Internet is already reachable.")
        return True, final_url

    if response.ok and not expected_text and not looks_like_portal(final_url, config):
        logging.info("Internet check returned HTTP %s from %s.", response.status_code, final_url)
        return True, final_url

    logging.info("Internet check not ready: HTTP %s from %s.", response.status_code, final_url)
    return False, final_url


def build_login_request(config: dict[str, Any], portal_url: str | None) -> tuple[str, str, dict[str, Any], dict[str, Any]]:
    login_url = config.get("login_url") or urljoin(config["portal_base"], "InterFace.do?method=login")
    method = str(config.get("login_method", "POST")).upper()
    query_string = ""

    if portal_url:
        parsed = urlparse(portal_url)
        query_string = parsed.query

    context = {
        **config,
        "portal_url": portal_url or "",
        "query_string": query_string,
        "query_string_encoded": urlencode({"q": query_string})[2:] if query_string else "",
    }

    payload_template = config.get("login_payload", DEFAULT_LOGIN_PAYLOAD)
    query_template = config.get("login_query", {})
    payload = render_template(payload_template, context)
    query = render_template(query_template, context)
    return method, login_url, query, payload


def response_says_success(response: requests.Response, config: dict[str, Any]) -> bool:
    text = response.text or ""
    try:
        data = response.json()
    except ValueError:
        data = None

    if isinstance(data, dict):
        result = str(data.get("result", "")).lower()
        message = str(data.get("message", ""))
        if result in {"success", "ok", "true"}:
            return True
        if any(indicator in message for indicator in config["success_indicators"]):
            return True
        if "result" in data:
            return False

    lowered = text.lower()
    return any(str(indicator).lower() in lowered for indicator in config["success_indicators"])


def login_once(session: requests.Session, config: dict[str, Any], portal_url: str | None) -> bool:
    method, login_url, query, payload = build_login_request(config, portal_url)
    logging.info("Submitting campus login request to %s.", login_url)

    try:
        response = session.request(
            method,
            login_url,
            params=query,
            data=payload if method != "GET" else None,
            timeout=config["timeout_seconds"],
            headers=config["headers"],
            verify=config["verify_tls"],
        )
    except requests.RequestException as exc:
        logging.info("Login request failed: %s", exc)
        return False

    logging.info("Login response: HTTP %s.", response.status_code)
    if response_says_success(response, config):
        logging.info("Login response indicates success.")
        return True

    snippet = " ".join(response.text[:300].split())
    logging.info("Login response did not indicate success: %s", snippet)
    return False


def run(config: dict[str, Any]) -> int:
    setup_logging(config)
    deadline = time.monotonic() + int(config["max_wait_seconds"])
    session = requests.Session()
    last_portal_url: str | None = None

    logging.info("Campus login started.")
    while time.monotonic() <= deadline:
        online, portal_url = check_online(session, config)
        if online:
            return 0

        last_portal_url = portal_url if portal_url and looks_like_portal(portal_url, config) else last_portal_url
        if last_portal_url:
            if login_once(session, config, last_portal_url):
                online, _ = check_online(session, config)
                if online:
                    logging.info("Campus login completed.")
                    return 0

        time.sleep(int(config["retry_interval_seconds"]))

    logging.error("Campus login timed out after %s seconds.", config["max_wait_seconds"])
    return 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Auto-login to a campus ePortal network.")
    parser.add_argument(
        "-c",
        "--config",
        default=str(Path(__file__).with_name("config.json")),
        help="Path to config.json.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        config = load_config(Path(args.config).expanduser().resolve())
        return run(config)
    except LoginError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
