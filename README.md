# Telegram Video Downloader

A simple downloader that saves videos from Telegram channels, for **Windows** and
**Android (Termux)**. It is a friendly wrapper around [tdl](https://github.com/iyear/tdl).

- Add a **whole channel**, or paste **one or many video links**
- Downloads 1 to 4 videos at a time (your choice, default 3)
- Never downloads the same post twice, and skips the same video posted under a
  different link (matched by file name + size)
- Safe to close at any time; run it again to carry on
- Links that keep failing are set aside so the rest keep going
- Installs tdl and signs you in automatically on first run

## Windows

1. Click **Code > Download ZIP** on this page and extract it to any folder.
2. Double-click **`Start Download.bat`**.

## Android (Termux)

### 1. Install Termux

Download Termux from [GitHub](https://github.com/termux/termux-app/releases) or
[F-Droid](https://f-droid.org/packages/com.termux/). **Don't use the Play Store version** -
it's outdated and no longer works properly.

- On the GitHub releases page, open **Assets** and pick the file ending in
  **`arm64-v8a.apk`** (right for almost all modern phones). If unsure, use
  **`universal.apk`**.
- If Android blocks the install, tap **Settings > Allow from this source**, then go back
  and tap **Install**.
- If you see an **"Android App Compatibility"** warning about a debuggable app or
  16 KB pages, tap **Don't Show Again**. It's harmless - Termux works fine.

### 2. Set up Termux (first time only)

Open Termux and run these one at a time:

```bash
pkg update && pkg upgrade -y
```

> If it stops and asks about a configuration file (`openssl.cnf`, `sources.list`,
> `bash.bashrc` ...), type **`y`** and press Enter each time.

```bash
termux-setup-storage
```

> Tap **Allow** on the popup. This lets Termux save videos to your phone storage.

```bash
pkg install -y git
git clone https://github.com/Mhsunny624/telegram-video-downloader ~/telegram-video-downloader
```

### 3. Run it

```bash
bash ~/telegram-video-downloader/start-download.sh
```

On the first run it installs everything else it needs (`jq`, `curl`, tdl) and asks you
to sign in to Telegram.

**Tip - make a short command.** Run this once:

```bash
echo "alias tgdl='bash ~/telegram-video-downloader/start-download.sh'" >> ~/.bashrc && source ~/.bashrc
```

From then on, just type **`tgdl`** to start the downloader.

### Updating

```bash
cd ~/telegram-video-downloader && git pull
```

Your links, settings and download history are kept.

### Termux tips

- **Keep downloads running:** the script holds a wake lock while downloading so Android
  doesn't pause it. Leave Termux open (it can be in the background) and avoid swiping it
  away from recent apps.
- **Files location:** videos go to `Download/Telegram` on your phone by default
  (change with option 3). Your link lists (`links.txt`, `done.txt`, `failed.txt`) are
  kept in the same folder, so you can see and edit them with your file manager. If you
  change the folder, the lists move with it.
- **"Can't use that folder" / permission errors:** run `termux-setup-storage` again and
  allow access.
- **SD card:** Android only lets Termux write inside its own folder on the card, e.g.
  `/storage/XXXX-XXXX/Android/media/com.termux/Telegram`.
- **Download stopped with a connection error:** turn off any VPN, stay on Wi-Fi, and run
  the downloader again - it carries on where it left off.
- **Sign in again:** `tdl login -T code`
- **Paste in Termux:** long-press the screen and tap **Paste**.

It also works on any Linux PC the same way.

## First run

- It downloads tdl automatically.
- It asks you to sign in to Telegram: enter your phone number with country code
  (e.g. `+441234567890`), then the code Telegram sends to your Telegram app.
- Before the first download it asks where to save videos. Press Enter for the default
  (`Downloads` next to the scripts on Windows, `Download/Telegram` on Android), press
  **B** to browse for a folder, or type any folder path.

## Using it

You get a menu:

```
  1      Add a whole channel
  2      Add video links (one or many)
  3      Change download folder (D:\Videos\Telegram)
  4      Downloads at a time (now 3 | default 3, max 4)
  Enter  Start downloading (12 waiting)
  Q      Quit
```

You can use 1 and 2 as many times as you like, then press **Enter** to start downloading.
When nothing is left, it says **All done!**

**1 - Add a whole channel.** Any of these work:

| What you paste | Example |
|---|---|
| Private channel link | `https://t.me/c/1234567890` |
| A post from the channel | `https://t.me/c/1234567890/25` |
| Public channel link | `https://t.me/channelname` |
| Channel username | `@channelname` |

**2 - Add video links.** Paste one or more post links (one per line, or several on one
line), then press Enter on an empty line. Copy a post's link in Telegram with
right-click (or long-press) > **Copy Post Link**.

```
https://t.me/c/1234567890/25
https://t.me/c/1234567890/31 https://t.me/channelname/7
```

You can also paste links into `links.txt` yourself, one per line.

**3 - Change download folder.**
- **Windows:** opens the normal Windows folder picker.
- **Android:** opens a simple folder browser - type a folder's number to open it, `0` to
  save there, `u` to go up, `n` to make a new folder. (Android's own file manager can't
  hand a folder back to Termux, so the browser is built into the script.) You can also
  type a path directly, e.g. `/storage/emulated/0/Movies/Telegram`.

**4 - Downloads at a time.** Choose how many videos download together, from 1 to 4
(default 3). More is faster, but too many at once can make Telegram slow you down.

## Duplicate videos

Before downloading, it looks up each post's file name and size. If a video with the
same name and size was already downloaded (from any link), the post is skipped and
shown as **Skipped (already downloaded)**. Videos already in your download folder count
too. Names are compared ignoring capitals, spaces and punctuation, so `My Video.mp4` and
`my_video.mp4` match - but only if the size is exactly the same.

## Files it creates

| File | What it's for |
|---|---|
| `links.txt` | Posts waiting to be downloaded |
| `done.txt` | Posts already downloaded (these are skipped in future) |
| `failed.txt` | Posts that failed 3 times. Move them back to `links.txt` to retry |
| `download_folder.txt` | Your chosen save folder. Change it with option 3 |
| `batch_size.txt` | How many download at a time. Change it with option 4 |
| `done_names.txt` | Name + size of every downloaded video, used to skip duplicates |

On Windows these are kept next to the scripts; on Android (Termux) they are kept in
your download folder. These files are personal and are excluded from git.

## Scripts

| File | What it does |
|---|---|
| `Start Download.bat` | Windows: the one you double-click |
| `start.ps1` | Windows: the menu (add channel / add links) |
| `download.ps1` | Windows: downloads `links.txt` in batches and tracks progress |
| `setup-tdl.ps1` | Windows: downloads tdl and signs you in (first run) |
| `start-download.sh` | Termux / Linux: everything in one script |

## Tips

- Sign in again any time with `tdl login -T code` (`tdl.exe login -T code` on Windows).
- On Windows, if you use Telegram Desktop you can import that login instead: `tdl.exe login`
- Your Telegram login is stored in your user folder (`.tdl`), not in this folder.
  Never share that folder.
- On Android, the script keeps the phone awake while downloading so Android doesn't
  pause it.

## Credits & licence

- Downloads are done by [tdl](https://github.com/iyear/tdl) by iyear, licensed under
  AGPL-3.0. tdl is not included in this repository; it is downloaded from its official
  releases on first run.
- The scripts in this repository are released under the [MIT License](LICENSE).

Only download content you have the right to access and save.
