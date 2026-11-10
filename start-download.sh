#!/usr/bin/env bash
# Telegram Video Downloader - Termux (Android) / Linux version
# Add a whole channel or individual video links, then download them 3 at a time.
# Run with:  bash start-download.sh

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1
LINKS="$DIR/links.txt"; DONE="$DIR/done.txt"; FAILED="$DIR/failed.txt"
CFG="$DIR/download_folder.txt"; TODO="$DIR/todo.tmp"
BATCH=3; MAXTRY=3
touch "$LINKS" "$DONE" "$FAILED"

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

choose_folder() {
  OUT=""
  [[ -f "$CFG" ]] && OUT="$(head -n1 "$CFG" | tr -d '\r')"
  local def="$DIR/Downloads"
  [[ -d /storage/emulated/0 ]] && def="/storage/emulated/0/Download/Telegram"
  while [[ -z "$OUT" ]]; do
    echo
    read -rp "Where should videos be saved? (Enter for $def): " ans
    ans="${ans:-$def}"; ans="${ans/#\~/$HOME}"
    if mkdir -p "$ans" 2>/dev/null && [[ -w "$ans" ]]; then
      OUT="$(cd "$ans" && pwd)"
      echo "$OUT" > "$CFG"
      echo "${G}Saved. Videos will go to: $OUT${N}"
      echo "(To change this later, delete download_folder.txt)"
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

waiting() {
  tr -d '\r' < "$LINKS" | sed '/^[[:space:]]*$/d' \
    | grep -vxF -f <(awk 1 "$DONE" "$FAILED" | tr -d '\r' | sed '/^[[:space:]]*$/d') | grep -c .
}

# ---------- download ----------
download_all() {
  choose_folder
  echo "Saving videos to: $OUT"
  have termux-wake-lock && termux-wake-lock
  local tries=0
  while true; do
    tr -d '\r' < "$LINKS" | sed '/^[[:space:]]*$/d' \
      | grep -vxF -f <(awk 1 "$DONE" "$FAILED" | tr -d '\r' | sed '/^[[:space:]]*$/d') > "$TODO"
    local left; left=$(grep -c . "$TODO")
    if ((left == 0)); then
      : > "$LINKS"; rm -f "$TODO"
      echo; echo "${G}All done! Downloaded: $(grep -c . "$DONE")  Failed: $(grep -c . "$FAILED")${N}"
      break
    fi
    local now=(); mapfile -t now < <(head -n "$BATCH" "$TODO")
    echo; echo "${C}[$left left] Downloading:${N}"; printf '  %s\n' "${now[@]}"
    local args=(); for l in "${now[@]}"; do args+=(-u "$l"); done
    if "$TDL" dl -d "$OUT" -l "$BATCH" --skip-same --continue "${args[@]}"; then
      ensure_nl "$DONE"; printf '%s\n' "${now[@]}" >> "$DONE"; tries=0
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
    tail -n +$((${#now[@]} + 1)) "$TODO" > "$LINKS"
  done
  have termux-wake-unlock && termux-wake-unlock
}

# ---------- main ----------
setup_deps
setup_tdl

echo "============================================================"
echo "                 TELEGRAM VIDEO DOWNLOADER"
echo "============================================================"
echo " Downloads 3 at a time. Finished links move to done.txt and"
echo " are never downloaded again. Links that fail 3 times go to"
echo " failed.txt. Safe to close any time - run again to continue."
echo " Save folder is in download_folder.txt (delete it to change)."

while true; do
  echo
  echo "  1      Add a whole channel"
  echo "  2      Add video links (one or many)"
  echo "  Enter  Start downloading ($(waiting) waiting)"
  echo "  q      Quit"
  read -rp " Choose: " choice
  case "${choice,,}" in
    1)  add_channel ;;
    2)  add_videos ;;
    "") download_all; break ;;
    q)  exit 0 ;;
    *)  echo "${Y} Please type 1, 2, q or just press Enter.${N}" ;;
  esac
done