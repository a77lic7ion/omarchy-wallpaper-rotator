#!/bin/bash
# Control the user systemd timer that rotates the Omarchy wallpaper.
# Used by the shaun.wallpaper-rotator bar widget. All writes stay in the
# user's own config/state dirs; packaged Omarchy files are never touched.
#
# Usage: rotatectl.sh status|set <minutes>|pause|resume|next|reset
#                        themes|theme <slug> on|off|toggle|all-themes on|off
#                        folders|add-folder <path>|remove-folder <path>
# Every successful action prints a single JSON object.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/theme-lib.sh"

UNIT="omarchy-bg-rotate.timer"
SERVICE="omarchy-bg-rotate.service"
OVERRIDE_DIR="$HOME/.config/systemd/user/${UNIT}.d"
OVERRIDE="$OVERRIDE_DIR/override.conf"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/shaun.wallpaper-rotator"
SETTINGS="$STATE_DIR/settings.json"
THEME_NAME=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

ensure_settings() {
  mkdir -p "$STATE_DIR"
  if [[ ! -f "$SETTINGS" ]]; then
    printf '{"interval":5,"themes":[],"folders":[]}\n' > "$SETTINGS"
  fi
  # Older settings files only had interval — add the new keys.
  jq '. + {themes:(.themes // []), folders:(.folders // [])}' "$SETTINGS" > "$SETTINGS.tmp" \
    && mv "$SETTINGS.tmp" "$SETTINGS"
}

write_settings() {
  local filter="$1" slug="$2"
  jq --arg s "$slug" "$filter" "$SETTINGS" > "$SETTINGS.tmp" \
    && mv "$SETTINGS.tmp" "$SETTINGS"
}

current_interval() {
  local n=""
  if [[ -f "$OVERRIDE" ]]; then
    n=$(sed -n 's/^[[:space:]]*OnUnitActiveSec=[[:space:]]*\([0-9][0-9]*\)min.*/\1/p' "$OVERRIDE" | tail -1)
  fi
  if [[ -z "$n" && -f "$SETTINGS" ]]; then
    n=$(jq -r '.interval // 5' "$SETTINGS" 2>/dev/null)
  fi
  [[ "$n" =~ ^[0-9]+$ ]] || n=5
  printf '%s' "$n"
}

pool_count() {
  bash "$SCRIPT_DIR/rotate.sh" count 2>/dev/null | tail -1
}

next_minutes() {
  local interval="$1" started epoch elapsed remainder
  started=$(systemctl --user show "$UNIT" -p ActiveEnterTimestamp --value 2>/dev/null || true)
  [[ -n "$started" ]] || { printf '0'; return; }
  epoch=$(date -d "$started" +%s 2>/dev/null || true)
  [[ -n "$epoch" ]] || { printf '0'; return; }
  elapsed=$(( $(date +%s) - epoch ))
  (( elapsed < 0 )) && elapsed=0
  remainder=$(( interval * 60 - elapsed % (interval * 60) ))
  printf '%s' "$(( (remainder + 59) / 60 ))"
}

emit() {
  local interval active enabled remainder pool themes folders
  interval=$(current_interval)
  active=$(systemctl --user is-active "$UNIT" 2>/dev/null || true)
  enabled=$(systemctl --user is-enabled "$UNIT" 2>/dev/null || true)
  remainder=$(next_minutes "$interval")
  pool=$(pool_count)
  themes=$(jq -c '.themes // []' "$SETTINGS" 2>/dev/null || printf '[]')
  folders=$(jq -c '.folders // []' "$SETTINGS" 2>/dev/null || printf '[]')
  if [[ "$active" == "active" ]]; then
    active_json=true
    error_json=""
  else
    active_json=false
    error_json="Timer is not running"
  fi
  printf '{"interval":%s,"active":%s,"enabled":"%s","theme":"%s","wallpapers":%s,"nextMin":%s,"themes":%s,"folders":%s,"error":"%s"}\n' \
    "$interval" "$active_json" "$(json_escape "$enabled")" \
    "$(json_escape "${THEME_NAME:-unknown}")" "$pool" "$remainder" \
    "$themes" "$folders" "$(json_escape "$error_json")"
}

reload_if_active() {
  systemctl --user daemon-reload >/dev/null 2>&1
  if [[ "$(systemctl --user is-active "$UNIT" 2>/dev/null)" == "active" ]]; then
    systemctl --user restart "$UNIT" >/dev/null 2>&1
  fi
}

ensure_settings

case "${1:-status}" in
  status)
    emit
    ;;
  set)
    n="${2:-}"
    if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > 240 )); then
      printf '{"error":"Interval must be a whole number from 1 to 240 minutes"}\n'
      exit 1
    fi
    mkdir -p "$OVERRIDE_DIR"
    cat > "$OVERRIDE" <<EOF
# Managed by shaun.wallpaper-rotator — change it from the bar panel.
[Timer]
OnUnitActiveSec=${n}min
EOF
    write_settings ".interval = $n" ""
    reload_if_active
    emit
    ;;
  themes)
    selected=$(jq -c '.themes // []' "$SETTINGS" 2>/dev/null || printf '[]')
    printf '['
    first=1
    while IFS= read -r slug; do
      [[ -n "$slug" ]] || continue
      count=$(theme_background_count "$slug")
      name=$(prettify_theme "$slug")
      yes=$(jq --arg s "$slug" 'any((.themes // [])[]; . == $s)' "$SETTINGS" 2>/dev/null || printf false)
      [[ $first -eq 1 ]] || printf ','
      first=0
      printf '{"id":"%s","name":"%s","count":%s,"selected":%s}' \
        "$(json_escape "$slug")" "$(json_escape "$name")" "$count" "$yes"
    done < <(installed_theme_slugs)
    printf ']'
    ;;
  theme)
    slug="${2:-}"
    mode="${3:-toggle}"
    [[ -n "$slug" ]] || { printf '{"error":"No theme given"}\n'; exit 1; }
    case "$mode" in
      on) filter='.themes = ((.themes // []) + [$s] | unique)' ;;
      off) filter='.themes = ((.themes // []) | map(select(. != $s)))' ;;
      toggle) filter='if any((.themes // [])[]; . == $s) then .themes = ((.themes // []) | map(select(. != $s))) else .themes = ((.themes // []) + [$s] | unique) end' ;;
      *) printf '{"error":"Unknown theme action"}\n'; exit 1 ;;
    esac
    write_settings "$filter" "$slug"
    emit
    ;;
  all-themes)
    mode="${2:-off}"
    if [[ "$mode" == "on" ]]; then
      jq -R -s 'split("\n") | map(select(length > 0))' > "$SETTINGS.themes.tmp" \
        < <(installed_theme_slugs)
      jq --slurpfile list "$SETTINGS.themes.tmp" '.themes = $list[0]' "$SETTINGS" > "$SETTINGS.tmp" \
        && mv "$SETTINGS.tmp" "$SETTINGS"
      rm -f "$SETTINGS.themes.tmp"
    elif [[ "$mode" == "off" ]]; then
      write_settings '.themes = []' ""
    else
      printf '{"error":"Use on or off"}\n'; exit 1
    fi
    emit
    ;;
  folders)
    jq -c '.folders // []' "$SETTINGS" 2>/dev/null || printf '[]'
    ;;
  add-folder)
    dir="${2:-}"
    if [[ -z "$dir" || ! -d "$dir" ]]; then
      printf '{"error":"Not a folder"}\n'; exit 1
    fi
    dir=$(realpath "$dir")
    write_settings '.folders = ((.folders // []) + [$s] | unique)' "$dir"
    emit
    ;;
  remove-folder)
    dir="${2:-}"
    write_settings '.folders = ((.folders // []) | map(select(. != $s)))' "$dir"
    emit
    ;;
  pause)
    systemctl --user disable --now "$UNIT" >/dev/null 2>&1
    emit
    ;;
  resume)
    systemctl --user enable --now "$UNIT" >/dev/null 2>&1
    emit
    ;;
  next)
    systemctl --user start "$SERVICE" >/dev/null 2>&1
    emit
    ;;
  reset)
    rm -f "$OVERRIDE"
    rmdir "$OVERRIDE_DIR" 2>/dev/null || true
    write_settings '.interval = 5' ""
    reload_if_active
    emit
    ;;
  *)
    printf '{"error":"Unknown action"}\n' >&2
    exit 1
    ;;
esac
