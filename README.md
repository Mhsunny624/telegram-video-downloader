# Telegram Video Downloader

A simple double-click downloader for Windows that saves every video from a Telegram
channel to your PC. It is a friendly wrapper around [tdl](https://github.com/iyear/tdl).

- Paste a channel link and it collects every post for you
- Downloads 3 videos at a time
- Never downloads the same post twice
- Safe to close at any time; run it again to carry on
- Links that keep failing are set aside so the rest keep going

## Requirements

- Windows 10 or 11
- A Telegram account (you can only download from channels your account can see)

## Getting started

1. Click **Code > Download ZIP** on this page and extract it to any folder.
2. Double-click **`Start Download.bat`**.
3. **First run only:**
   - It downloads `tdl.exe` automatically.
   - It asks you to sign in to Telegram: enter your phone number with country code
     (e.g. `+441234567890`), then the code Telegram sends to your Telegram app.
   - It asks where to save videos. Press Enter to use a `Downloads` folder next to the
     scripts, or type any folder path.

## Using it

When you open `Start Download.bat`, it asks for a channel. Any of these work:

| What you paste | Example |
|---|---|
| Private channel link | `https://t.me/c/1234567890` |
| A post from a channel | `https://t.me/c/1234567890/25` |
| Public channel link | `https://t.me/channelname` |
| Channel username | `@channelname` |

It finds every video post in that channel, adds the links to `links.txt`, then starts
downloading.

**Just press Enter** instead to download whatever is already in `links.txt`.
When nothing is left, it says **All done!**

You can also paste individual post links into `links.txt` yourself, one per line.

## Files it creates

| File | What it's for |
|---|---|
| `links.txt` | Posts waiting to be downloaded |
| `done.txt` | Posts already downloaded (these are skipped in future) |
| `failed.txt` | Posts that failed 3 times. Move them back to `links.txt` to retry |
| `download_folder.txt` | Your chosen save folder. Delete it to pick a new one |

These files are personal and are excluded from git.

## Scripts

| File | What it does |
|---|---|
| `Start Download.bat` | The one you double-click |
| `add-channel.ps1` | Exports a channel's posts and adds them to `links.txt` |
| `download.ps1` | Downloads `links.txt` in batches and tracks progress |
| `setup-tdl.ps1` | Downloads tdl and signs you in (first run) |

## Tips

- Sign in again any time by running `tdl.exe login -T code` in this folder.
- If you already use Telegram Desktop on this PC, you can import that login instead:
  `tdl.exe login`
- Your Telegram login is stored in your user folder (`%USERPROFILE%\.tdl`), not in this
  folder. Never share that folder.

## Credits & licence

- Downloads are done by [tdl](https://github.com/iyear/tdl) by iyear, licensed under
  AGPL-3.0. tdl is not included in this repository; it is downloaded from its official
  releases on first run.
- The scripts in this repository are released under the [MIT License](LICENSE).

Only download content you have the right to access and save.
