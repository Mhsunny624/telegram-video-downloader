#!/usr/bin/env bash
# Telegram Video Downloader - Termux (Android) / Linux version
# Add a whole channel or individual video links, then download them 3 at a time.
# Run with:  bash start-download.sh

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1
LINKS="$DIR/links.txt"; DONE="$DIR/done.txt"; FAILED="$DIR/failed.txt"
CFG="$DIR/download_folder.txt"; TODO="$DIR/todo.tmp"
BATCH=3; MAXTRY=3

C=$'\e[36m'; G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; N=$'\e[0m'
have() { command -v "$1" >/dev/null 2>&1; }

# ---------- setup ----------
setup_deps() {
  local missing=()
  for p in jq curl tar; do have "$p" || missing+=("$p"); done
  ((${#missing[@]} == 0)) && return
  if have pkg; then
    echo "${C}Installing: ${missing[*]}${N}"
    pkg install -y "${missing[@]}" || exit 1
  else
    echo "${R}Please install: ${missing[*]}${N}"; exit 1
  fi
}

setup_tdl() {
  if have tdl; then TDL="$(command -v tdl)"; return; fi
  local bindir="${PREFIX:-$HOME/.local}/bin"
  TDL="$bindir/tdl"
  [[ -x "$TDL" ]] && return
  local arch
  case "$(uname -m)" in
    aarch64|arm64) arch=arm64 ;;
    x86_64)        arch=64bit ;;
    armv7*|armv8l) arch=armv7 ;;
    i?86)          arch=32bit ;;
    *) echo "${R}Unsupported CPU: $(uname -m)${N}"; exit 1 ;;
  esac
  echo "${C}tdl not found. Downloading it...${N}"
  mkdir -p "$bindir"
  local tmp; tmp="$(mktemp -d)"
  if curl -fL "https://github.com/iyear/tdl/releases/latest/download/tdl_Linux_${arch}.tar.gz" -o "$tmp/tdl.tgz" \
     && tar -xzf "$tmp/tdl.tgz" -C "$tmp" \
     && cp "$tmp/tdl" "$TDL" && chmod 755 "$TDL"; then
    rm -rf "$tmp"
    echo "${G}tdl installed.${N}"
  else
    rm -rf "$tmp"
    echo "${R}Could not install tdl. Get it from https://github.com/iyear/tdl/releases${N}"; exit 1
  fi
  echo
  echo "${C}Now sign in to your Telegram account.${N}"
  echo "Enter your phone number with country code (e.g. +441234567890),"
  echo "then the code Telegram sends to your Telegram app."
  "$TDL" login -T code
}

# Lets you walk through your phone's folders by number and pick one (sets PICKED)
browse_folder() {
  local cur="$1" choice nm i
  local dirs=()
  while true; do
    mapfile -t dirs < <(find "$cur" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | sort -f)
    echo
    echo "${C} Folder: $cur${N}"
    echo "   0   >> Save videos HERE <<"
    echo "   u   Go up one level"
    for i in "${!dirs[@]}"; do printf '   %-3d %s\n' $((i + 1)) "$(basename "${dirs[i]}")"; done
    ((${#dirs[@]} == 0)) && echo "       (no folders here)"
    echo "   n   Make a new folder here"
    echo "   c   Cancel"
    read -rp " Choose: " choice
    case "${choice,,}" in
      0) PICKED="$cur"; return 0 ;;
      u) [[ "$cur" != "/" ]] && cur="$(dirname "$cur")" ;;
      n) read -rp " New folder name: " nm
         if [[ -n "$nm" ]] && mkdir -p "$cur/$nm" 2>/dev/null; then cur="$cur/$nm"
         else echo "${R} Couldn't create that folder.${N}"; fi ;;
      c) return 1 ;;
      *) if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#dirs[@]})); then
           cur="${dirs[choice - 1]}"
         else
           echo "${Y} Type a number from the list, or u / n / c.${N}"
         fi ;;
    esac
  done
}

# Sets OUT to the download folder. Pass "change" to pick a new one even if one is saved.
choose_folder() {
  local mode="${1:-}" old=""
  OUT=""
  [[ -f "$CFG" ]] && old="$(head -n1 "$CFG" | tr -d '\r')"
  [[ "$mode" != change ]] && OUT="$old"
  local def="$DIR/Downloads"
  [[ -d /storage/emulated/0 ]] && def="/storage/emulated/0/Download/Telegram"
  local root="/storage/emulated/0"; [[ -d "$root" ]] || root="$HOME"
  while [[ -z "$OUT" ]]; do
    echo
    echo " Where should videos be saved?"
    [[ -n "$old" ]] && echo "   Current: $old"
    echo "   b      Browse your phone's folders"
    echo "   Enter  Use $def"
    [[ -n "$old" ]] && echo "   c      Cancel (keep current folder)"
    echo "   ...or type a full folder path"
    read -rp " Folder: " ans
    case "${ans,,}" in
      b) if browse_folder "$root"; then ans="$PICKED"; else continue; fi ;;
      c) if [[ -n "$old" ]]; then OUT="$old"; echo " Kept: $OUT"; return; fi; continue ;;
    esac
    ans="${ans:-$def}"; ans="${ans/#\~/$HOME}"
    if mkdir -p "$ans" 2>/dev/null && [[ -w "$ans" ]]; then
      OUT="$(cd "$ans" && pwd)"
      echo "$OUT" > "$CFG"
      echo "${G}Saved. Videos will go to: $OUT${N}"
      echo "(Change it any time with option 3 in the menu)"
    else
      echo "${R}Can't use that folder.${N}"
      [[ "$ans" == /storage/* ]] && echo "Run 'termux-setup-storage' and allow access, then try again."
    fi
  done
}

# ---------- link helpers ----------
known() { awk 1 "$LINKS" "$DONE" "$FAILED" | tr -d '\r' | sed '/^[[:space:]]*$/d'; }

ensure_nl() { [[ -s "$1" && -n "$(tail -c1 "$1")" ]] && echo >> "$1"; }

# Reads links on stdin, appends the new ones to links.txt, prints how many were added
add_links() {
  local tmp; tmp="$(mktemp)"
  awk '!seen[$0]++' | grep -vxF -f <(known) > "$tmp"
  local n; n=$(grep -c . "$tmp")
  if ((n > 0)); then ensure_nl "$LINKS"; cat "$tmp" >> "$LINKS"; fi
  rm -f "$tmp"
  echo "$n"
}

# Pulls every Telegram post link out of text on stdin and tidies it up
extract_links() {
  grep -oE '(https?://)?t\.me/[^[:space:]"<>]+' \
    | sed -E 's|^(https?://)?|https://|; s|[?#].*$||; s|/+$||' \
    | grep -E '^https://t\.me/(c/[0-9]+|[A-Za-z0-9_]{4,})(/[0-9]+){1,2}$'
}

add_channel() {
  echo
  echo " Paste the channel. Any of these work:"
  echo "   https://t.me/c/1234567890      (private channel)"
  echo "   https://t.me/c/1234567890/25   (any post from it)"
  echo "   https://t.me/channelname       (public channel)"
  echo "   @channelname"
  local in chat prefix
  read -rp " Channel: " in
  in="$(printf '%s' "$in" | tr -d '"\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -z "$in" ]] && return
  if [[ $in =~ t\.me/c/([0-9]+) ]]; then
    chat="${BASH_REMATCH[1]}"; prefix="https://t.me/c/$chat"
  elif [[ $in =~ t\.me/(s/)?([A-Za-z0-9_]{4,}) ]]; then
    chat="${BASH_REMATCH[2]}"; prefix="https://t.me/$chat"
  elif [[ $in =~ ^@?([A-Za-z0-9_]{4,})$ ]]; then
    chat="${BASH_REMATCH[1]}"; prefix="https://t.me/$chat"
  else
    echo "${R} Could not understand that channel: $in${N}"; return
  fi
  local tmp="$DIR/channel_export.json"; rm -f "$tmp"
  echo; echo "${C} Exporting posts from $chat ...${N}"
  if ! "$TDL" chat export -c "$chat" -o "$tmp" || [[ ! -s "$tmp" ]]; then
    echo "${R} Export failed. Check the link and that you are signed in.${N}"; rm -f "$tmp"; return
  fi
  local found added
  found=$(jq -r '.messages[].id' "$tmp" | sort -n -u | grep -c .)
  added=$(jq -r '.messages[].id' "$tmp" | sort -n -u | sed "s|^|$prefix/|" | add_links)
  rm -f "$tmp"
  echo "${G} Found $found posts, added $added new links.${N}"
}

add_videos() {
  echo
  echo " Paste video post links - one per line, or several on one line."
  echo " Example: https://t.me/c/1234567890/25"
  echo " Press Enter on an empty line when you're finished."
  local buf="" line
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && break
    buf+="$line"$'\n'
  done
  local list found added
  list="$(printf '%s' "$buf" | extract_links | awk '!seen[$0]++')"
  found=$(printf '%s\n' "$list" | grep -c .)
  if ((found == 0)); then
    echo "${Y} No valid post links found. A post link ends with a number, e.g. .../25${N}"; return
  fi
  added=$(printf '%s\n' "$list" | add_links)
  echo "${G} Found $found links, added $added new ($((found - added)) already listed or downloaded).${N}"
}

BCFG="$DIR/batch_size.txt"

get_batch() {
  local v=""
  [[ -f "$BCFG" ]] && v="$(head -n1 "$BCFG" | tr -d '\r[:space:]')"
  [[ "$v" =~ ^[1-4]$ ]] && echo "$v" || echo 3
}

set_batch() {
  local cur n; cur="$(get_batch)"
  echo
  echo " How many videos should download at the same time? (1 to 4, currently $cur)"
  echo " More is faster, but too many can cause Telegram to slow you down."
  while true; do
    read -rp " Number (Enter to keep $cur): " n
    n="${n//[[:space:]]/}"
    if [[ -z "$n" ]]; then echo " Kept: $cur at a time"; return; fi
    if [[ "$n" =~ ^[1-4]$ ]]; then
      echo "$n" > "$BCFG"; echo "${G} Now downloading $n at a time.${N}"; return
    fi
    echo "${Y} Please type a number from 1 to 4.${N}"
  done
}

waiting() {
  tr -d '\r' < "$LINKS" | sed '/^[[:space:]]*$/d' \
    | grep -vxF -f <(awk 1 "$DONE" "$FAILED" | tr -d '\r' | sed '/^[[:space:]]*$/d') | grep -c .
}

# ---------- download ----------
# The link lists live in the download folder, next to the videos
set_list_paths() {
  LINKS="$OUT/links.txt"; DONE="$OUT/done.txt"; FAILED="$OUT/failed.txt"; TODO="$OUT/todo.tmp"
  NAMES="$OUT/done_names.txt"
  touch "$LINKS" "$DONE" "$FAILED"
}

# Merges link lists from another folder into the current one, then removes the old copies
merge_lists_from() {
  local src="$1" f moved=0
  [[ -z "$src" || "$src" == "$OUT" ]] && return
  for f in links.txt done.txt failed.txt done_names.txt; do
    if [[ -s "$src/$f" ]]; then
      awk 1 "$OUT/$f" "$src/$f" | tr -d '\r' | sed '/^[[:space:]]*$/d' | awk '!s[$0]++' > "$OUT/$f.tmp" \
        && mv "$OUT/$f.tmp" "$OUT/$f" && rm -f "$src/$f" && moved=1
    fi
  done
  ((moved)) && echo "${G} Moved your link lists to: $OUT${N}"
  return 0
}

change_folder() {
  local old="$OUT"
  choose_folder change
  if [[ "$OUT" != "$old" ]]; then set_list_paths; merge_lists_from "$old"; fi
}

# ---------- duplicate check (same file name + size) ----------
declare -A KEY=() NAME=() DK=()

# Turns a file name + size into a match key: size, then the name lower-cased with
# spaces and punctuation removed (so "My Video.mp4" and "my_video.mp4" match)
make_key() {
  local n; n="$(printf '%s' "$2" | tr 'A-Z' 'a-z' | tr -d '\011\040-\057\072-\100\133-\140\173-\176')"
  [[ -n "$1" && -n "$n" ]] && printf '%s|%s' "$1" "$n"
}

# Loads every key already downloaded: from done_names.txt and from videos in the folder
load_done_keys() {
  DK=()
  local k size name
  [[ -f "$NAMES" ]] && while IFS= read -r k; do k="${k%$'\r'}"; [[ -n "$k" ]] && DK["$k"]=1; done < "$NAMES"
  while IFS=$'\t' read -r size name; do
    name="$(printf '%s' "$name" | sed -E 's/^-?[0-9]+_[0-9]+_//')"
    k="$(make_key "$size" "$name")"; [[ -n "$k" ]] && DK["$k"]=1
  done < <(find "$OUT" -maxdepth 1 -type f ! -name '*.tmp' ! -name '*.txt' ! -name '*.json' ! -name '*.sh' -printf '%s\t%f\n' 2>/dev/null)
}

# Looks up the file name and size of each link (one quick tdl export per channel)
lookup_keys() {
  local l chat id ids pfx tmp mid size name
  declare -A MIN=() MAX=() PFX=()
  for l in "$@"; do
    [[ -n "${KEY[$l]+x}" ]] && continue
    if [[ $l =~ ^https://t\.me/c/([0-9]+)/([0-9]+)$ ]]; then
      chat="${BASH_REMATCH[1]}"; id="${BASH_REMATCH[2]}"; PFX[$chat]="https://t.me/c/$chat"
    elif [[ $l =~ ^https://t\.me/([A-Za-z0-9_]{4,})/([0-9]+)$ ]]; then
      chat="${BASH_REMATCH[1]}"; id="${BASH_REMATCH[2]}"; PFX[$chat]="https://t.me/$chat"
    else
      KEY[$l]=""; continue
    fi
    [[ -z "${MIN[$chat]}" ]] || ((id < MIN[$chat])) && MIN[$chat]=$id
    [[ -z "${MAX[$chat]}" ]] || ((id > MAX[$chat])) && MAX[$chat]=$id
  done
  ((${#MIN[@]} == 0)) && return 0
  echo "${C}Checking file names and sizes...${N}"
  tmp="$DIR/lookup_export.json"
  for chat in "${!MIN[@]}"; do
    rm -f "$tmp"
    "$TDL" chat export -c "$chat" -T id -i "${MIN[$chat]},${MAX[$chat]}" --raw -o "$tmp" >/dev/null 2>&1
    [[ -s "$tmp" ]] || continue
    while IFS=$'\t' read -r mid size name; do
      l="${PFX[$chat]}/$mid"
      KEY[$l]="$(make_key "$size" "$name")"; NAME[$l]="$name"
    done < <(jq -r '.messages[] | "\(.id)\t\(.raw.Media.Document.Size // "")\t\(.file // "")"' "$tmp" 2>/dev/null)
  done
  rm -f "$tmp"
  for l in "$@"; do [[ -n "${KEY[$l]+x}" ]] || KEY[$l]=""; done
}

# Removes the given links from links.txt (keeps anything added while downloading)
remove_from_links() {
  local tmp; tmp="$(mktemp)"
  tr -d '\r' < "$LINKS" | grep -vxF -f <(printf '%s\n' "$@") > "$tmp"
  cat "$tmp" > "$LINKS"; rm -f "$tmp"
}

download_all() {
  echo "Saving videos to: $OUT"
  BATCH="$(get_batch)"
  echo "Downloading $BATCH at a time"
  have termux-wake-lock && termux-wake-lock
  load_done_keys
  local tries=0 skipped=0
  while true; do
    tr -d '\r' < "$LINKS" | sed '/^[[:space:]]*$/d' \
      | grep -vxF -f <(awk 1 "$DONE" "$FAILED" | tr -d '\r' | sed '/^[[:space:]]*$/d') > "$TODO"
    local left; left=$(grep -c . "$TODO")
    if ((left == 0)); then
      local finished; finished="$(awk 1 "$DONE" "$FAILED" | tr -d '\r' | sed '/^[[:space:]]*$/d')"
      [[ -n "$finished" ]] && remove_from_links $finished
      rm -f "$TODO"
      echo; echo "${G}All done! Finished: $(grep -c . "$DONE")  Failed: $(grep -c . "$FAILED")  (skipped $skipped duplicates this run)${N}"
      break
    fi
    local todo=(); mapfile -t todo < "$TODO"
    lookup_keys "${todo[@]}"

    # Pick the next batch, skipping files already downloaded under another link
    local now=() dup=() l k
    declare -A PLAN=()
    for l in "${todo[@]}"; do
      k="${KEY[$l]}"
      if [[ -n "$k" && ( -n "${DK[$k]+x}" || -n "${PLAN[$k]+x}" ) ]]; then
        echo "${Y} Skipped (already downloaded): ${NAME[$l]:-$l}${N}"
        dup+=("$l"); continue
      fi
      now+=("$l"); [[ -n "$k" ]] && PLAN[$k]=1
      ((${#now[@]} >= BATCH)) && break
    done
    unset PLAN
    if ((${#dup[@]} > 0)); then
      ensure_nl "$DONE"; printf '%s\n' "${dup[@]}" >> "$DONE"
      remove_from_links "${dup[@]}"; skipped=$((skipped + ${#dup[@]}))
    fi
    ((${#now[@]} == 0)) && continue

    echo; echo "${C}[$left left] Downloading:${N}"
    for l in "${now[@]}"; do echo "  $l  ${NAME[$l]:+(${NAME[$l]})}"; done
    local args=(); for l in "${now[@]}"; do args+=(-u "$l"); done
    if "$TDL" dl -d "$OUT" -l "$BATCH" --skip-same --continue "${args[@]}"; then
      ensure_nl "$DONE"; printf '%s\n' "${now[@]}" >> "$DONE"; tries=0
      for l in "${now[@]}"; do
        k="${KEY[$l]}"
        if [[ -n "$k" ]]; then ensure_nl "$NAMES"; echo "$k" >> "$NAMES"; DK[$k]=1; fi
      done
    else
      tries=$((tries + 1))
      if ((tries >= MAXTRY)); then
        echo "${R}Failed $MAXTRY times, moving these to failed.txt${N}"
        ensure_nl "$FAILED"; printf '%s\n' "${now[@]}" >> "$FAILED"; tries=0
      else
        echo "${Y}Download failed (try $tries of $MAXTRY). Retrying in 10 seconds...${N}"
        sleep 10; continue
      fi
    fi
    remove_from_links "${now[@]}"
  done
  have termux-wake-unlock && termux-wake-unlock
}

# ---------- main ----------
setup_deps
setup_tdl
choose_folder
set_list_paths
merge_lists_from "$DIR"

echo "============================================================"
echo "                 TELEGRAM VIDEO DOWNLOADER"
echo "============================================================"
echo " Downloads up to 4 at a time. Finished links move to done.txt and"
echo " are never downloaded again. Links that fail 3 times go to"
echo " failed.txt. Safe to close any time - run again to continue."
echo " Videos and links.txt / done.txt / failed.txt are kept in the"
echo " download folder (option 3 to change it)."

while true; do
  echo
  echo "  1      Add a whole channel"
  echo "  2      Add video links (one or many)"
  echo "  3      Change download folder ($( [[ -s "$CFG" ]] && head -n1 "$CFG" | tr -d '\r' || echo 'not set yet'))"
  echo "  4      Downloads at a time (now $(get_batch) | default 3, max 4)"
  echo "  Enter  Start downloading ($(waiting) waiting)"
  echo "  q      Quit"
  read -rp " Choose: " choice
  case "${choice,,}" in
    1)  add_channel ;;
    2)  add_videos ;;
    3)  change_folder ;;
    4)  set_batch ;;
    "") download_all; break ;;
    q)  exit 0 ;;
    *)  echo "${Y} Please type 1-4, q or just press Enter.${N}" ;;
  esac
done