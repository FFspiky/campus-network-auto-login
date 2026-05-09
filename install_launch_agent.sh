#!/usr/bin/env bash
set -euo pipefail

label="com.ffspiky.campus-network-auto-login"
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python_exe=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)
      label="$2"
      shift 2
      ;;
    --project-dir)
      project_dir="$2"
      shift 2
      ;;
    --python-exe)
      python_exe="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$python_exe" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python_exe="$(command -v python3)"
  elif command -v python >/dev/null 2>&1; then
    python_exe="$(command -v python)"
  else
    echo "Python was not found. Install Python 3 first, then rerun this script." >&2
    exit 1
  fi
fi

script_path="$project_dir/run_on_wifi.py"
config_path="$project_dir/config.json"
log_dir="$project_dir/logs"
plist_dir="$HOME/Library/LaunchAgents"
plist_path="$plist_dir/$label.plist"

if [[ ! -f "$script_path" ]]; then
  echo "run_on_wifi.py not found at $script_path" >&2
  exit 1
fi

if [[ ! -f "$config_path" ]]; then
  echo "config.json not found. Copy config.example.json to config.json and fill in your account first." >&2
  exit 1
fi

mkdir -p "$plist_dir" "$log_dir"

cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$python_exe</string>
    <string>$script_path</string>
    <string>--config</string>
    <string>$config_path</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$project_dir</string>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>300</integer>
  <key>KeepAlive</key>
  <dict>
    <key>NetworkState</key>
    <true/>
  </dict>
  <key>StandardOutPath</key>
  <string>$log_dir/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$log_dir/launchd.err.log</string>
</dict>
</plist>
PLIST

plutil -lint "$plist_path" >/dev/null

launchctl bootout "gui/$(id -u)" "$plist_path" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$plist_path"
launchctl enable "gui/$(id -u)/$label"
launchctl kickstart -k "gui/$(id -u)/$label"

echo "LaunchAgent '$label' installed."
echo "Plist: $plist_path"
echo "It runs at user login, on network availability changes, and every 300 seconds."
echo "It runs run_on_wifi.py, which only submits login when the current SSID matches config.json target_ssids."
