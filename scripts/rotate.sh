#!/bin/bash
# Rotate the wallpaper through the selected themes and/or extra folders.
# Shares discovery with rotatectl.sh so the panel's counts and the rotation
# always agree. With no selection it falls back to the active theme's art.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/theme-lib.sh"

SETTINGS="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/shaun.wallpaper-rotator/settings.json"
CURRENT_LINK="$HOME/.local/state/omarchy/current/background"
declare -a BACKGROUNDS=()

selected_themes() {
  [[ -f "$SETTINGS" ]] || return 0
  jq -r '.themes[]?' "$SETTINGS" 2>/dev/null || true
}

selected_folders() {
  [[ -f "$SETTINGS" ]] || return 0
  jq -r '.folders[]?' "$SETTINGS" 2>/dev/null || true
}

build_list() {
  local -a slugs=() folders=() files=()
  mapfile -t slugs < <(selected_themes)
  mapfile -t folders < <(selected_folders)

  # Nothing selected: behave like the stock rotator (active theme only).
  if (( ${#slugs[@]} == 0 && ${#folders[@]} == 0 )); then
    local current
    current=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)
    [[ -n "$current" ]] && slugs+=("$current")
  fi

  local slug dir file
  for slug in "${slugs[@]}"; do
    while IFS= read -r dir; do
      while IFS= read -r -d '' file; do files+=("$file"); done \
        < <(find -L "$dir" -maxdepth 1 -type f \( "${IMAGE_TEST[@]}" \) -print0 2>/dev/null)
    done < <(theme_background_dirs "$slug")
  done

  for dir in "${folders[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' file; do files+=("$file"); done \
      < <(find -L "$dir" -maxdepth 1 -type f "${IMAGE_TEST[@]}" -print0 2>/dev/null)
  done

  (( ${#files[@]} == 0 )) && return 1
  mapfile -d '' -t BACKGROUNDS < <(printf '%s\0' "${files[@]}" | sort -z -u)
  return 0
}

case "${1:-rotate}" in
  count)
    if build_list; then
      printf '%s\n' "${#BACKGROUNDS[@]}"
    else
      printf '0\n'
    fi
    ;;
  rotate|*)
    build_list || exit 0
    local_count=${#BACKGROUNDS[@]}
    current=""
    [[ -L "$CURRENT_LINK" ]] && current=$(readlink "$CURRENT_LINK")
    index=-1
    for ((i = 0; i < local_count; i++)); do
      if [[ "${BACKGROUNDS[$i]}" == "$current" ]]; then index=$i; break; fi
    done
    if (( index == -1 )); then
      next="${BACKGROUNDS[0]}"
    else
      next="${BACKGROUNDS[$(((index + 1) % local_count))]}"
    fi
    omarchy-theme-bg-set "$next"
    ;;
esac
