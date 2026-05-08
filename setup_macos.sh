#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force|-f)
      force=1
      shift
      ;;
    --project-dir)
      project_dir="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ask_yes_no() {
  local prompt="$1"
  local default="${2:-yes}"
  local suffix="[Y/n]"
  [[ "$default" == "no" ]] && suffix="[y/N]"

  while true; do
    read -r -p "$prompt $suffix " answer
    if [[ -z "$answer" ]]; then
      [[ "$default" == "yes" ]]
      return
    fi
    answer_lower="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    case "$answer_lower" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "Please enter y or n." >&2 ;;
    esac
  done
}

read_required() {
  local prompt="$1"
  local value=""
  while [[ -z "$value" ]]; do
    read -r -p "$prompt " value
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    [[ -z "$value" ]] && echo "This value is required." >&2
  done
  printf '%s' "$value"
}

read_password_text() {
  local prompt="$1"
  local value=""
  while [[ -z "$value" ]]; do
    read -r -s -p "$prompt " value
    echo
    [[ -z "$value" ]] && echo "This value is required." >&2
  done
  printf '%s' "$value"
}

select_service_value() {
  echo >&2
  echo "Select service:" >&2
  echo "1. China Mobile (cmcc)" >&2
  echo "2. Campus network (default)" >&2
  echo "3. Campus intranet (local)" >&2
  echo "4. China Unicom (unicom)" >&2
  echo "5. China Telecom (ctcc)" >&2
  echo "6. Custom" >&2

  while true; do
    read -r -p "Service [1] " choice
    case "${choice:-1}" in
      1) printf '%s' "cmcc"; return ;;
      2) printf '%s' "default"; return ;;
      3) printf '%s' "local"; return ;;
      4) printf '%s' "unicom"; return ;;
      5) printf '%s' "ctcc"; return ;;
      6) read_required "Custom service value"; return ;;
      *) echo "Please enter 1-6." >&2 ;;
    esac
  done
}

get_python_command() {
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return
  fi
  if command -v python >/dev/null 2>&1; then
    command -v python
    return
  fi
  return 1
}

config_template_path="$project_dir/config.example.json"
config_path="$project_dir/config.json"
requirements_path="$project_dir/requirements.txt"
login_script_path="$project_dir/campus_login.py"
install_script_path="$project_dir/install_launch_agent.sh"

echo "Campus network auto login setup for macOS"
echo "Project directory: $project_dir"
echo

python_exe="$(get_python_command)" || {
  echo "Python was not found. Install Python 3 first, then rerun setup_macos.sh." >&2
  exit 1
}
echo "Python: $python_exe"

if ask_yes_no "Install Python dependencies now?" "yes"; then
  "$python_exe" -m pip install -r "$requirements_path"
fi

if [[ -f "$config_path" && "$force" -eq 0 ]]; then
  if ask_yes_no "config.json already exists. Overwrite it?" "no"; then
    cp "$config_template_path" "$config_path"
  else
    echo "Keeping existing config.json."
  fi
else
  cp "$config_template_path" "$config_path"
fi

username="$(read_required "Campus network username")"
password="$(read_password_text "Campus network password")"
service="$(select_service_value)"

"$python_exe" - "$config_path" "$username" "$password" "$service" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
config = json.loads(config_path.read_text(encoding="utf-8-sig"))
config["username"] = sys.argv[2]
config["password"] = sys.argv[3]
config["service"] = sys.argv[4]
config_path.write_text(
    json.dumps(config, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

echo
echo "config.json updated. Password is stored in plain text locally; do not commit this file."

if ask_yes_no "Run a manual login test now?" "yes"; then
  if ! "$python_exe" "$login_script_path" --config "$config_path"; then
    echo "Manual test failed. Check campus_login.log before installing the LaunchAgent."
  fi
fi

if ask_yes_no "Install or update the macOS LaunchAgent?" "yes"; then
  "$install_script_path" --project-dir "$project_dir" --python-exe "$python_exe"
fi

echo
echo "Setup complete."
echo "You can check the LaunchAgent with:"
echo "  ./check_launch_agent.sh"
