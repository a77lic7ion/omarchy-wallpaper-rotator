#!/bin/bash
# Shared theme/background discovery for the wallpaper rotator.
# Sourced by rotate.sh and rotatectl.sh; never run directly.

OMARCHY_ROOT="${OMARCHY_PATH:-/usr/share/omarchy}"
USER_THEME_ROOT="$HOME/.config/omarchy/themes"
STOCK_THEME_ROOT="$OMARCHY_ROOT/themes"
USER_BG_ROOT="$HOME/.config/omarchy/backgrounds"

IMAGE_TEST=( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif'
  -o -iname '*.bmp' -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.m4v'
  -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.avi' )

# Background directories that belong to a theme slug (user fork, stock theme,
# and the user's extra backgrounds for that theme).
theme_background_dirs() {
  local slug="$1" dir
  [[ -n "$slug" ]] || return 0
  for dir in "$USER_THEME_ROOT/$slug/backgrounds" "$STOCK_THEME_ROOT/$slug/backgrounds" "$USER_BG_ROOT/$slug"; do
    [[ -d "$dir" ]] && printf '%s\n' "$dir"
  done
}

# Every installed theme slug, user and stock, sorted, de-duplicated.
installed_theme_slugs() {
  local root dir slug
  local -A seen=()
  for root in "$USER_THEME_ROOT" "$STOCK_THEME_ROOT"; do
    [[ -d "$root" ]] || continue
    for dir in "$root"/*; do
      [[ -d "$dir" ]] || continue
      slug="$(basename "$dir")"
      [[ -n "${seen[$slug]:-}" ]] && continue
      seen[$slug]=1
      printf '%s\n' "$slug"
    done
  done | sort
}

# Number of background files available for a theme slug.
theme_background_count() {
  local slug="$1" dir n total=0
  while IFS= read -r dir; do
    n=$(find -L "$dir" -maxdepth 1 -type f \( "${IMAGE_TEST[@]}" \) -print 2>/dev/null | wc -l)
    total=$(( total + n ))
  done < <(theme_background_dirs "$slug")
  printf '%s' "$total"
}

# Number of background files in an arbitrary local folder (top level only).
folder_background_count() {
  local dir="$1"
  [[ -d "$dir" ]] || { printf '0'; return; }
  find -L "$dir" -maxdepth 1 -type f "${IMAGE_TEST[@]}" -print 2>/dev/null | wc -l | tr -d ' '
}

prettify_theme() {
  local s="${1//[-_]/ }"
  local -a words=()
  read -r -a words <<< "$s"
  local out="" w
  for w in "${words[@]}"; do
    out+="${w^} "
  done
  printf '%s' "${out% }"
}
