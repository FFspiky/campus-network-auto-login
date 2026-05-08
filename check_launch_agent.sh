#!/usr/bin/env bash
set -euo pipefail

label="com.ffspiky.campus-network-auto-login"
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_tail=30

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
    --log-tail)
      log_tail="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

plist_path="$HOME/Library/LaunchAgents/$label.plist"
login_log="$project_dir/campus_login.log"
stdout_log="$project_dir/logs/launchd.out.log"
stderr_log="$project_dir/logs/launchd.err.log"

write_field() {
  printf '%-24s %s\n' "$1:" "$2"
}

echo "LaunchAgent"
echo "-----------"
write_field "Label" "$label"
write_field "Plist" "$plist_path"
write_field "Plist exists" "$([[ -f "$plist_path" ]] && echo Yes || echo No)"
write_field "Project directory" "$project_dir"
write_field "campus_login.py" "$([[ -f "$project_dir/campus_login.py" ]] && echo Yes || echo No)"
write_field "config.json" "$([[ -f "$project_dir/config.json" ]] && echo Yes || echo No)"

if [[ -f "$plist_path" ]]; then
  echo
  echo "Plist validation"
  echo "----------------"
  plutil -lint "$plist_path"

  echo
  echo "Loaded service"
  echo "--------------"
  if ! launchctl print "gui/$(id -u)/$label"; then
    echo "LaunchAgent is not loaded. Run ./install_launch_agent.sh first."
  fi
fi

for log_path in "$login_log" "$stdout_log" "$stderr_log"; do
  echo
  echo "Log: $log_path"
  echo "----------------"
  if [[ -f "$log_path" ]]; then
    tail -n "$log_tail" "$log_path"
  else
    echo "Log file not found."
  fi
done
