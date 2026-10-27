#!/usr/bin/env python3
import sys
import os
import re
import shutil
import time
import urllib.parse
import urllib.request
import subprocess

PLEX_URL = "http://127.0.0.1:32400"
PLEX_TOKEN = "XdnTDZYKkk4Y32H4jaTp"
BOT_TOKEN = "8418915846:AAHJwMZ9isa3iAmoN_nIUArhW5tUfr-bpOI"
CHAT_ID = "132696855"

FILM_DIR = "/home/ubermensch/Scaricati/Film"
SERIE_DIR = "/home/ubermensch/Scaricati/Serie TV"
SECTION_FILM = 1
SECTION_SERIE = 2

PATTERNS = [
    r"\bS\d{1,2}(?:E\d{1,2})?\b",
    r"\b\d{1,2}x\d{1,2}\b",
    r"\bseason[\s\._-]*\d{1,2}\b",
    r"\bstagione[\s\._-]*\d{1,2}\b",
    r"\bepisodi?o?[\s\._-]*\d{1,2}\b"
]
REGEX_TV = re.compile("|".join(PATTERNS), re.IGNORECASE)

VIDEO_EXTS = {".mkv", ".mp4", ".avi", ".mov", ".m4v", ".ts"}

def is_tv_show(name, full_path):
    if REGEX_TV.search(name):
        return True
    if os.path.isdir(full_path):
        for root, _, files in os.walk(full_path):
            video_count = 0
            for f in files:
                if REGEX_TV.search(f):
                    return True
                ext = os.path.splitext(f)[1].lower()
                if ext in VIDEO_EXTS:
                    video_count += 1
            if video_count > 1:
                return True
    return False

def plex_refresh(section_id):
    try:
        url = f"{PLEX_URL}/library/sections/{section_id}/refresh?X-Plex-Token={PLEX_TOKEN}"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            pass
    except Exception as e:
        print(f"[Plex] Error refreshing section {section_id}: {e}", file=sys.stderr)

def plex_empty_trash(section_id):
    try:
        url = f"{PLEX_URL}/library/sections/{section_id}/emptyTrash?X-Plex-Token={PLEX_TOKEN}"
        req = urllib.request.Request(url, method="PUT")
        with urllib.request.urlopen(req, timeout=10) as resp:
            pass
    except Exception as e:
        print(f"[Plex] Error emptying trash section {section_id}: {e}", file=sys.stderr)

def send_telegram(message):
    try:
        url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
        data = urllib.parse.urlencode({
            "chat_id": CHAT_ID,
            "text": message
        }).encode("utf-8")
        req = urllib.request.Request(url, data=data)
        with urllib.request.urlopen(req, timeout=10) as resp:
            pass
    except Exception as e:
        print(f"[Telegram] Error sending message: {e}", file=sys.stderr)

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <torrent_dir_or_path> [torrent_name] [torrent_id]")
        sys.exit(1)

    if len(sys.argv) == 2:
        source_path = os.path.abspath(sys.argv[1])
        torrent_name = os.path.basename(source_path)
        torrent_dir = os.path.dirname(source_path)
        torrent_id = None
    else:
        torrent_dir = sys.argv[1]
        torrent_name = sys.argv[2]
        torrent_id = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
        source_path = os.path.join(torrent_dir, torrent_name)

    if not os.path.exists(source_path):
        print(f"Error: {source_path} does not exist", file=sys.stderr)
        sys.exit(1)

    # Do not process if already inside Film or Serie TV
    real_source = os.path.realpath(source_path)
    if real_source.startswith(FILM_DIR) or real_source.startswith(SERIE_DIR):
        print(f"{source_path} is already in destination folder.")
        dest_path = source_path
        is_tv = real_source.startswith(SERIE_DIR)
        section_id = SECTION_SERIE if is_tv else SECTION_FILM
        label = "📺 Serie TV" if is_tv else "🎬 Film"
    else:
        is_tv = is_tv_show(torrent_name, source_path)
        dest_dir = SERIE_DIR if is_tv else FILM_DIR
        dest_path = os.path.join(dest_dir, torrent_name)
        section_id = SECTION_SERIE if is_tv else SECTION_FILM
        label = "📺 Serie TV" if is_tv else "🎬 Film"

        print(f"Classified as {label} -> destination: {dest_dir}")

        moved = False
        if torrent_id:
            print(f"Moving via transmission-remote -t {torrent_id} --move {dest_dir}...")
            res = subprocess.run(["transmission-remote", "-t", str(torrent_id), "--move", dest_dir], capture_output=True, text=True)
            print("transmission-remote:", res.stdout.strip())
            # Wait up to 5 seconds for file to appear in destination
            for _ in range(10):
                if os.path.exists(dest_path):
                    moved = True
                    break
                time.sleep(0.5)

        if not moved:
            print(f"Moving via filesystem move to {dest_path}...")
            shutil.move(source_path, dest_path)

    # Fix permissions
    try:
        subprocess.run(["chmod", "-R", "u=rwX,g=rwX,o=rX", dest_path], check=False)
    except Exception as e:
        print(f"chmod error: {e}", file=sys.stderr)

    # Audio optimization if script exists
    if os.path.exists("/usr/local/bin/optimize-mkv-audio.py"):
        try:
            print("Running audio optimizer...")
            subprocess.run(["/usr/local/bin/optimize-mkv-audio.py", dest_path], check=False)
        except Exception as e:
            print(f"Audio optimizer error: {e}", file=sys.stderr)

    # Trigger Plex immediate indexing
    print(f"Triggering Plex scan for section {section_id}...")
    plex_refresh(section_id)

    # Telegram notification
    msg = f"✅ Download completato: {label}\n📁 {torrent_name}\n🔄 Indicizzato su Plex!"
    send_telegram(msg)
    print("Done!")

if __name__ == "__main__":
    main()
