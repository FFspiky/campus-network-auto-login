#!/usr/bin/env python3
"""Run campus login only when the current Wi-Fi SSID matches the config."""

from __future__ import annotations

import argparse
import json
import platform
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


DEFAULT_TARGET_SSIDS = ["upc"]
DEFAULT_CONNECT_TIMEOUT_SECONDS = 45


def load_config(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as file:
        return json.load(file)


def target_ssids(config: dict[str, Any]) -> list[str]:
    value = config.get("target_ssids", DEFAULT_TARGET_SSIDS)
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [str(item) for item in value if str(item).strip()]
    return DEFAULT_TARGET_SSIDS


def run_text(command: list[str]) -> str:
    try:
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except FileNotFoundError:
        return ""
    return completed.stdout


def run_result(command: list[str]) -> tuple[int, str]:
    try:
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except FileNotFoundError as exc:
        return 127, str(exc)
    return completed.returncode, completed.stdout


def current_ssid_windows() -> str | None:
    output = run_text(["netsh", "wlan", "show", "interfaces"])
    for line in output.splitlines():
        stripped = line.strip()
        if stripped.lower().startswith("ssid") and not stripped.lower().startswith("bssid"):
            _, _, value = stripped.partition(":")
            ssid = value.strip()
            return ssid or None
    return None


def visible_ssids_windows() -> list[str]:
    output = run_text(["netsh", "wlan", "show", "networks", "mode=bssid"])
    ssids: list[str] = []
    for line in output.splitlines():
        stripped = line.strip()
        if stripped.lower().startswith("ssid") and not stripped.lower().startswith("bssid"):
            _, _, value = stripped.partition(":")
            ssid = value.strip()
            if ssid:
                ssids.append(ssid)
    return ssids


def connect_windows(ssid: str) -> bool:
    return_code, output = run_result(["netsh", "wlan", "connect", f"name={ssid}", f"ssid={ssid}"])
    print(output.strip())
    return return_code == 0


def macos_wifi_device() -> str | None:
    output = run_text(["networksetup", "-listallhardwareports"])
    current_port = ""
    for line in output.splitlines():
        stripped = line.strip()
        if stripped.startswith("Hardware Port:"):
            current_port = stripped.partition(":")[2].strip()
        elif stripped.startswith("Device:") and current_port in {"Wi-Fi", "AirPort"}:
            return stripped.partition(":")[2].strip()
    return "en0"


def current_ssid_macos() -> str | None:
    device = macos_wifi_device()
    if not device:
        return None

    output = run_text(["networksetup", "-getairportnetwork", device])
    marker = "Current Wi-Fi Network:"
    for line in output.splitlines():
        if marker in line:
            ssid = line.split(marker, 1)[1].strip()
            return ssid or None
    return None


def visible_ssids_macos() -> list[str]:
    device = macos_wifi_device()
    if not device:
        return []

    output = run_text(["/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport", "-s"])
    ssids: list[str] = []
    for line in output.splitlines()[1:]:
        stripped = line.rstrip()
        if not stripped:
            continue
        ssid = stripped[:32].strip()
        if ssid:
            ssids.append(ssid)
    return ssids


def connect_macos(ssid: str, password: str | None = None) -> bool:
    device = macos_wifi_device()
    if not device:
        print("Could not determine macOS Wi-Fi device.")
        return False

    command = ["networksetup", "-setairportnetwork", device, ssid]
    if password:
        command.append(password)

    return_code, output = run_result(command)
    if output.strip():
        print(output.strip())
    return return_code == 0


def current_ssid() -> str | None:
    system = platform.system()
    if system == "Windows":
        return current_ssid_windows()
    if system == "Darwin":
        return current_ssid_macos()
    return None


def visible_ssids() -> list[str]:
    system = platform.system()
    if system == "Windows":
        return visible_ssids_windows()
    if system == "Darwin":
        return visible_ssids_macos()
    return []


def connect_to_ssid(ssid: str, config: dict[str, Any]) -> bool:
    system = platform.system()
    if system == "Windows":
        return connect_windows(ssid)
    if system == "Darwin":
        password = config.get("wifi_password")
        return connect_macos(ssid, str(password) if password else None)
    return False


def ssid_matches(current: str | None, targets: list[str]) -> bool:
    if not current:
        return False
    lowered_current = current.casefold()
    return any(lowered_current == target.casefold() for target in targets)


def find_target_ssid(targets: list[str], visible: list[str]) -> str | None:
    visible_by_case = {ssid.casefold(): ssid for ssid in visible}
    for target in targets:
        matched = visible_by_case.get(target.casefold())
        if matched:
            return matched
    return None


def wait_for_target_ssid(targets: list[str], timeout_seconds: int) -> str | None:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() <= deadline:
        ssid = current_ssid()
        if ssid_matches(ssid, targets):
            return ssid
        time.sleep(2)
    return None


def auto_connect_if_needed(config: dict[str, Any], targets: list[str]) -> str | None:
    ssid = current_ssid()
    if ssid_matches(ssid, targets):
        return ssid

    if not bool(config.get("auto_connect_wifi", True)):
        return ssid

    print("Current SSID does not match. Scanning for target Wi-Fi...")
    visible = visible_ssids()
    if visible:
        print(f"Visible Wi-Fi SSID(s): {', '.join(visible)}")
    else:
        print("No visible Wi-Fi SSIDs found.")

    target = find_target_ssid(targets, visible)
    if not target:
        print("Target Wi-Fi was not found; skipping campus login.")
        return ssid

    print(f"Connecting to Wi-Fi SSID: {target}")
    if not connect_to_ssid(target, config):
        print("Wi-Fi connection command failed; skipping campus login.")
        return current_ssid()

    timeout = int(config.get("wifi_connect_timeout_seconds", DEFAULT_CONNECT_TIMEOUT_SECONDS))
    connected = wait_for_target_ssid(targets, timeout)
    if connected:
        print(f"Connected to target Wi-Fi SSID: {connected}")
        return connected

    print("Timed out waiting for target Wi-Fi connection.")
    return current_ssid()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run campus login only on configured Wi-Fi SSIDs.")
    parser.add_argument(
        "-c",
        "--config",
        default=str(Path(__file__).with_name("config.json")),
        help="Path to config.json.",
    )
    parser.add_argument(
        "--run-anyway",
        action="store_true",
        help="Skip SSID matching and run campus_login.py.",
    )
    parser.add_argument(
        "--no-connect",
        action="store_true",
        help="Do not try to connect to target Wi-Fi before checking SSID.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config_path = Path(args.config).expanduser().resolve()
    config = load_config(config_path)
    targets = target_ssids(config)

    if not args.run_anyway:
        if args.no_connect:
            config["auto_connect_wifi"] = False
        ssid = auto_connect_if_needed(config, targets)
        print(f"Current Wi-Fi SSID: {ssid or '(not connected)'}")
        print(f"Target Wi-Fi SSID(s): {', '.join(targets)}")
        if not ssid_matches(ssid, targets):
            print("SSID does not match; skipping campus login.")
            return 0

    login_script = Path(__file__).with_name("campus_login.py")
    return subprocess.call([sys.executable, str(login_script), "--config", str(config_path)])


if __name__ == "__main__":
    raise SystemExit(main())
