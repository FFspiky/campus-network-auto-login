#!/usr/bin/env python3
"""Graphical setup helper for the campus network auto-login script."""

from __future__ import annotations

import json
import platform
import queue
import subprocess
import sys
import threading
from pathlib import Path
from tkinter import BooleanVar, StringVar, Tk, messagebox
from tkinter import ttk
from tkinter.scrolledtext import ScrolledText


PROJECT_DIR = Path(__file__).resolve().parent
CONFIG_TEMPLATE_PATH = PROJECT_DIR / "config.example.json"
CONFIG_PATH = PROJECT_DIR / "config.json"
REQUIREMENTS_PATH = PROJECT_DIR / "requirements.txt"
LOGIN_SCRIPT_PATH = PROJECT_DIR / "campus_login.py"

SERVICES = {
    "中国移动": "cmcc",
    "校园网": "default",
    "校园内网": "local",
    "中国联通": "unicom",
    "中国电信": "ctcc",
    "自定义": "",
}


def load_config() -> dict:
    source = CONFIG_PATH if CONFIG_PATH.exists() else CONFIG_TEMPLATE_PATH
    with source.open("r", encoding="utf-8-sig") as file:
        return json.load(file)


def save_config(config: dict) -> None:
    CONFIG_PATH.write_text(
        json.dumps(config, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


class SetupApp:
    def __init__(self, root: Tk) -> None:
        self.root = root
        self.root.title("校园网自动登录配置")
        self.root.geometry("820x640")
        self.root.minsize(760, 560)

        self.output_queue: queue.Queue[str] = queue.Queue()
        self.running = False

        config = load_config()
        service = str(config.get("service", "cmcc"))
        service_label = next(
            (label for label, value in SERVICES.items() if value == service),
            "自定义",
        )

        self.username_var = StringVar(value=str(config.get("username", "")))
        self.password_var = StringVar(value=str(config.get("password", "")))
        self.service_label_var = StringVar(value=service_label)
        self.custom_service_var = StringVar(value=service if service_label == "自定义" else "")
        self.portal_base_var = StringVar(value=str(config.get("portal_base", "")))
        self.login_url_var = StringVar(value=str(config.get("login_url", "")))
        self.target_ssids_var = StringVar(value=", ".join(self.read_target_ssids(config)))
        self.auto_connect_wifi_var = BooleanVar(value=bool(config.get("auto_connect_wifi", True)))
        self.install_deps_var = BooleanVar(value=True)
        self.run_test_var = BooleanVar(value=True)
        self.install_startup_var = BooleanVar(value=True)

        self.build_ui()
        self.root.after(100, self.drain_output_queue)

    def build_ui(self) -> None:
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)

        container = ttk.Frame(self.root, padding=18)
        container.grid(row=0, column=0, sticky="nsew")
        container.columnconfigure(0, weight=1)
        container.rowconfigure(3, weight=1)

        title = ttk.Label(container, text="校园网自动登录配置", font=("", 18, "bold"))
        title.grid(row=0, column=0, sticky="w")

        form = ttk.LabelFrame(container, text="账号和门户配置", padding=14)
        form.grid(row=1, column=0, sticky="ew", pady=(14, 10))
        form.columnconfigure(1, weight=1)

        self.add_entry(form, 0, "校园网账号", self.username_var)
        self.add_entry(form, 1, "校园网密码", self.password_var, show="*")

        ttk.Label(form, text="服务类型").grid(row=2, column=0, sticky="w", pady=6)
        service_box = ttk.Combobox(
            form,
            textvariable=self.service_label_var,
            values=list(SERVICES.keys()),
            state="readonly",
        )
        service_box.grid(row=2, column=1, sticky="ew", pady=6)
        service_box.bind("<<ComboboxSelected>>", lambda _event: self.update_custom_service_state())

        ttk.Label(form, text="自定义 service").grid(row=3, column=0, sticky="w", pady=6)
        self.custom_service_entry = ttk.Entry(form, textvariable=self.custom_service_var)
        self.custom_service_entry.grid(row=3, column=1, sticky="ew", pady=6)

        self.add_entry(form, 4, "门户地址", self.portal_base_var)
        self.add_entry(form, 5, "登录接口", self.login_url_var)
        self.add_entry(form, 6, "目标 Wi-Fi", self.target_ssids_var)
        self.update_custom_service_state()

        options = ttk.LabelFrame(container, text="执行步骤", padding=14)
        options.grid(row=2, column=0, sticky="ew", pady=(0, 10))
        options.columnconfigure(0, weight=1)

        ttk.Checkbutton(options, text="安装 Python 依赖", variable=self.install_deps_var).grid(row=0, column=0, sticky="w")
        ttk.Checkbutton(options, text="保存后运行一次登录测试", variable=self.run_test_var).grid(row=1, column=0, sticky="w", pady=4)
        ttk.Checkbutton(options, text="开机时自动尝试连接目标 Wi-Fi", variable=self.auto_connect_wifi_var).grid(row=2, column=0, sticky="w")
        ttk.Checkbutton(options, text="安装或更新开机/登录自启", variable=self.install_startup_var).grid(row=3, column=0, sticky="w", pady=(4, 0))

        output_frame = ttk.LabelFrame(container, text="运行日志", padding=10)
        output_frame.grid(row=3, column=0, sticky="nsew")
        output_frame.columnconfigure(0, weight=1)
        output_frame.rowconfigure(0, weight=1)

        self.output = ScrolledText(output_frame, height=12, wrap="word")
        self.output.grid(row=0, column=0, sticky="nsew")
        self.output.configure(state="disabled")

        buttons = ttk.Frame(container)
        buttons.grid(row=4, column=0, sticky="ew", pady=(12, 0))
        buttons.columnconfigure(0, weight=1)

        self.save_button = ttk.Button(buttons, text="保存配置", command=self.save_config_from_ui)
        self.save_button.grid(row=0, column=1, padx=(0, 8))

        self.test_button = ttk.Button(buttons, text="测试登录", command=self.run_login_test)
        self.test_button.grid(row=0, column=2, padx=(0, 8))

        self.start_button = ttk.Button(buttons, text="保存并执行", command=self.run_setup)
        self.start_button.grid(row=0, column=3)

    def add_entry(self, parent: ttk.Frame, row: int, label: str, variable: StringVar, show: str | None = None) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", pady=6)
        entry = ttk.Entry(parent, textvariable=variable, show=show)
        entry.grid(row=row, column=1, sticky="ew", pady=6)

    def update_custom_service_state(self) -> None:
        state = "normal" if self.service_label_var.get() == "自定义" else "disabled"
        self.custom_service_entry.configure(state=state)

    def append_output(self, text: str) -> None:
        self.output.configure(state="normal")
        self.output.insert("end", text)
        self.output.see("end")
        self.output.configure(state="disabled")

    def drain_output_queue(self) -> None:
        while True:
            try:
                text = self.output_queue.get_nowait()
            except queue.Empty:
                break
            self.append_output(text)
        self.root.after(100, self.drain_output_queue)

    def set_running(self, running: bool) -> None:
        self.running = running
        state = "disabled" if running else "normal"
        self.save_button.configure(state=state)
        self.test_button.configure(state=state)
        self.start_button.configure(state=state)

    def get_service_value(self) -> str:
        label = self.service_label_var.get()
        value = SERVICES.get(label, "")
        if label == "自定义":
            value = self.custom_service_var.get().strip()
        return value

    def read_target_ssids(self, config: dict) -> list[str]:
        value = config.get("target_ssids", ["upc"])
        if isinstance(value, str):
            return [value]
        if isinstance(value, list):
            return [str(item) for item in value if str(item).strip()]
        return ["upc"]

    def get_target_ssids(self) -> list[str]:
        return [
            item.strip()
            for item in self.target_ssids_var.get().replace("，", ",").split(",")
            if item.strip()
        ]

    def validate_inputs(self) -> bool:
        if not self.username_var.get().strip():
            messagebox.showerror("配置不完整", "请填写校园网账号。")
            return False
        if not self.password_var.get():
            messagebox.showerror("配置不完整", "请填写校园网密码。")
            return False
        if not self.get_service_value():
            messagebox.showerror("配置不完整", "请填写 service。")
            return False
        if not self.portal_base_var.get().strip():
            messagebox.showerror("配置不完整", "请填写门户地址。")
            return False
        if not self.login_url_var.get().strip():
            messagebox.showerror("配置不完整", "请填写登录接口。")
            return False
        if not self.get_target_ssids():
            messagebox.showerror("配置不完整", "请填写目标 Wi-Fi。")
            return False
        return True

    def save_config_from_ui(self) -> bool:
        if not self.validate_inputs():
            return False

        config = load_config()
        config["username"] = self.username_var.get().strip()
        config["password"] = self.password_var.get()
        config["service"] = self.get_service_value()
        config["portal_base"] = self.portal_base_var.get().strip()
        config["login_url"] = self.login_url_var.get().strip()
        config["target_ssids"] = self.get_target_ssids()
        config["auto_connect_wifi"] = bool(self.auto_connect_wifi_var.get())
        save_config(config)
        self.append_output(f"Saved config: {CONFIG_PATH}\n")
        return True

    def run_command(self, command: list[str], title: str) -> int:
        self.output_queue.put(f"\n== {title} ==\n")
        self.output_queue.put(" ".join(command) + "\n")

        process = subprocess.Popen(
            command,
            cwd=PROJECT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

        assert process.stdout is not None
        for line in process.stdout:
            self.output_queue.put(line)

        return_code = process.wait()
        self.output_queue.put(f"Exit code: {return_code}\n")
        return return_code

    def startup_command(self) -> list[str]:
        system = platform.system()
        if system == "Windows":
            return [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(PROJECT_DIR / "install_task.ps1"),
                "-ProjectDir",
                str(PROJECT_DIR),
                "-PythonExe",
                sys.executable,
            ]
        if system == "Darwin":
            return [
                "bash",
                str(PROJECT_DIR / "install_launch_agent.sh"),
                "--project-dir",
                str(PROJECT_DIR),
                "--python-exe",
                sys.executable,
            ]
        raise RuntimeError(f"Unsupported platform: {system}")

    def run_in_thread(self, worker) -> None:
        if self.running:
            return
        self.set_running(True)

        def wrapped() -> None:
            try:
                worker()
            except Exception as exc:
                self.output_queue.put(f"ERROR: {exc}\n")
            finally:
                self.root.after(0, lambda: self.set_running(False))

        threading.Thread(target=wrapped, daemon=True).start()

    def run_login_test(self) -> None:
        if not self.save_config_from_ui():
            return

        def worker() -> None:
            self.run_command(
                [sys.executable, str(LOGIN_SCRIPT_PATH), "--config", str(CONFIG_PATH)],
                "测试登录",
            )

        self.run_in_thread(worker)

    def run_setup(self) -> None:
        if not self.save_config_from_ui():
            return

        def worker() -> None:
            if self.install_deps_var.get():
                if self.run_command(
                    [sys.executable, "-m", "pip", "install", "-r", str(REQUIREMENTS_PATH)],
                    "安装依赖",
                ) != 0:
                    return

            if self.run_test_var.get():
                if self.run_command(
                    [sys.executable, str(LOGIN_SCRIPT_PATH), "--config", str(CONFIG_PATH)],
                    "测试登录",
                ) != 0:
                    return

            if self.install_startup_var.get():
                self.run_command(self.startup_command(), "安装自启")

        self.run_in_thread(worker)


def main() -> int:
    root = Tk()
    SetupApp(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
