#!/usr/bin/env python3
import sys
import os
import re
import time
import sqlite3
import threading
import subprocess
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET

PLEX_URL = "http://127.0.0.1:32400"
PLEX_TOKEN = "XdnTDZYKkk4Y32H4jaTp"
PLEX_DB = "/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"

BOT_TOKEN = "8418915846:AAHJwMZ9isa3iAmoN_nIUArhW5tUfr-bpOI"
CHAT_ID = "132696855"

FILM_DIR = "/home/ubermensch/Scaricati/Film"
SERIE_DIR = "/home/ubermensch/Scaricati/Serie TV"
SECTION_FILM = 1
SECTION_SERIE = 2

VIDEO_EXTS = {".mkv", ".mp4", ".avi", ".mov", ".m4v", ".ts", ".iso"}
IGNORE_EXTS = {".part", ".tmp", ".crdownload", ".download"}

# Debounce timers per section
timers = {
    SECTION_FILM: {"del": None, "add": None},
    SECTION_SERIE: {"del": None, "add": None}
}
lock = threading.Lock()

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
        print(f"[Telegram] Error: {e}", file=sys.stderr)

def plex_call(endpoint, method="GET"):
    sep = "&" if "?" in endpoint else "?"
    url = f"{PLEX_URL}{endpoint}{sep}X-Plex-Token={PLEX_TOKEN}"
    req = urllib.request.Request(url, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status
    except Exception as e:
        print(f"[Plex API] Error {method} {endpoint}: {e}", file=sys.stderr)
        return None

def clean_show_or_movie_title(raw_title):
    # Normalize dots, underscores, dashes
    s = re.sub(r"[\._]+", " ", raw_title).strip()
    
    # Match season or episode markers (e.g. S01, S01E02, 1x01, Season 1, Stagione 1)
    m = re.search(r"\b(?:s\d{1,2}(?:e\d{1,2})?|\d{1,2}x\d{1,2}|season\s*\d{1,2}|stagione\s*\d{1,2})\b", s, re.IGNORECASE)
    if m:
        s = s[:m.start()].strip()

    # Strip release groups and audio/video tags
    tags = [
        r"\b(?:1080p|720p|2160p|4k|bluray|bdrip|webrip|web-dl|webdl|nfrip|amzn|sky|h264|h265|x264|x265|hevc|aac|ac3|ddp5\.1|dts|ita|italian|italiano|eng|sub)\b.*",
        r"-\s*(?:pir8|dd-crew|dragon|fhc|wrm|mem|gp).*$",
        r"\s+\d{1,2}\s*[\(\[]?\d{4}[\)\]]?",  # e.g. " 2 (2026)"
        r"[\(\[]?\b(19\d\d|20\d\d)\b[\)\]]?", # isolated year
        r"\s+\d{1,2}$"                        # trailing season number digit
    ]
    for tag in tags:
        s = re.sub(tag, "", s, flags=re.IGNORECASE).strip()

    s = re.sub(r"\s+", " ", s).strip()
    return s

def auto_fix_unmatched_items():
    if not os.path.exists(PLEX_DB):
        return
    try:
        conn = sqlite3.connect(f"file:{PLEX_DB}?mode=ro", uri=True)
        c = conn.cursor()
        # Find unmatched items in Film (1) or Serie TV (2) (metadata_type: 1=movie, 2=show)
        c.execute("""
            SELECT id, title, library_section_id, metadata_type
            FROM metadata_items
            WHERE (guid LIKE 'local://%' OR guid LIKE 'tv.plex.agents.none://%')
              AND library_section_id IN (1, 2)
              AND metadata_type IN (1, 2)
        """)
        unmatched = c.fetchall()
        conn.close()

        for item_id, raw_title, section_id, meta_type in unmatched:
            cleaned = clean_show_or_movie_title(raw_title)
            print(f"[Auto-Fix] Found unmatched item ID {item_id} ('{raw_title}'). Cleaned query: '{cleaned}'")
            if not cleaned or len(cleaned) < 2:
                continue

            query = urllib.parse.urlencode({
                "manual": "1",
                "title": cleaned,
                "X-Plex-Token": PLEX_TOKEN
            })
            url = f"{PLEX_URL}/library/metadata/{item_id}/matches?{query}"
            try:
                with urllib.request.urlopen(url, timeout=10) as resp:
                    xml_data = resp.read()
                root = ET.fromstring(xml_data)
                results = root.findall(".//SearchResult")
                if results:
                    best = results[0]
                    guid = best.get("guid")
                    name = best.get("name")
                    year = best.get("year", "")
                    if guid and name:
                        match_params = urllib.parse.urlencode({
                            "guid": guid,
                            "name": name,
                            "X-Plex-Token": PLEX_TOKEN
                        })
                        match_url = f"{PLEX_URL}/library/metadata/{item_id}/match?{match_params}"
                        req = urllib.request.Request(match_url, method="PUT")
                        with urllib.request.urlopen(req, timeout=10) as match_resp:
                            pass
                        print(f"[Auto-Fix] Successfully matched ID {item_id} to '{name}' ({year}) [{guid}]!")
                        send_telegram(f"🎨 Locandina e metadati recuperati automaticamente:\n📺 {name} ({year})")
            except Exception as e:
                print(f"[Auto-Fix] Error querying match for {item_id}: {e}", file=sys.stderr)

    except Exception as e:
        print(f"[Auto-Fix] DB Error: {e}", file=sys.stderr)

def trigger_delete_actions(section_id):
    section_name = "Film" if section_id == SECTION_FILM else "Serie TV"
    ts = time.strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{ts}] [Watcher] Executing deletion cleanup for section {section_id} ({section_name})...")
    plex_call(f"/library/sections/{section_id}/refresh")
    time.sleep(2)
    plex_call(f"/library/sections/{section_id}/emptyTrash", method="PUT")
    ts2 = time.strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{ts2}] [Watcher] Trash emptied for section {section_id} ({section_name}).")

def trigger_add_actions(section_id, path_to_fix=None):
    section_name = "Film" if section_id == SECTION_FILM else "Serie TV"
    ts = time.strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{ts}] [Watcher] Executing indexing for section {section_id} ({section_name})...")
    if path_to_fix and os.path.exists(path_to_fix):
        try:
            subprocess.run(["chmod", "-R", "u=rwX,g=rwX,o=rX", path_to_fix], check=False)
        except Exception:
            pass
    plex_call(f"/library/sections/{section_id}/refresh")
    ts2 = time.strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{ts2}] [Watcher] Refresh triggered for section {section_id} ({section_name}).")
    
    # Wait for Plex scanner to finish, then automatically resolve any unmatched covers/metadata
    def delayed_check():
        time.sleep(8)
        auto_fix_unmatched_items()

    t_check = threading.Thread(target=delayed_check, daemon=True)
    t_check.start()

def schedule_event(event_type, section_id, path_to_fix=None):
    with lock:
        old_timer = timers[section_id][event_type]
        if old_timer and old_timer.is_alive():
            old_timer.cancel()

        if event_type == "del":
            t = threading.Timer(2.5, trigger_delete_actions, args=[section_id])
        else:
            t = threading.Timer(3.0, trigger_add_actions, args=[section_id, path_to_fix])

        timers[section_id][event_type] = t
        t.daemon = True
        t.start()

def main():
    print(f"Starting Plex Media Watcher & Auto-Matcher on:\n  - {FILM_DIR}\n  - {SERIE_DIR}")
    os.makedirs(FILM_DIR, exist_ok=True)
    os.makedirs(SERIE_DIR, exist_ok=True)

    cmd = [
        "inotifywait",
        "-m",
        "-r",
        "-e", "delete",
        "-e", "moved_from",
        "-e", "close_write",
        "-e", "moved_to",
        "--format", "%w|%e|%f",
        FILM_DIR,
        SERIE_DIR
    ]

    while True:
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            for line in proc.stdout:
                line = line.strip()
                if not line or "|" not in line:
                    continue
                parts = line.split("|", 2)
                if len(parts) < 3:
                    continue
                dir_path, events, filename = parts[0], parts[1], parts[2]
                full_path = os.path.join(dir_path, filename)
                ext = os.path.splitext(filename)[1].lower()

                # Determine section
                if dir_path.startswith(FILM_DIR):
                    section_id = SECTION_FILM
                elif dir_path.startswith(SERIE_DIR):
                    section_id = SECTION_SERIE
                else:
                    continue

                event_list = events.split(",")

                # Deletion events
                if any(ev in ("DELETE", "MOVED_FROM", "DELETE_SELF") for ev in event_list):
                    ts = time.strftime('%H:%M:%S')
                    print(f"[{ts}] Event DELETE: {full_path}")
                    schedule_event("del", section_id)

                # Addition / Finish write events
                elif any(ev in ("CLOSE_WRITE", "MOVED_TO") for ev in event_list):
                    if filename.startswith(".") or ext in IGNORE_EXTS:
                        continue
                    # Check if relevant (video file or directory)
                    if ext in VIDEO_EXTS or os.path.isdir(full_path):
                        ts = time.strftime('%H:%M:%S')
                        print(f"[{ts}] Event ADD/WRITE: {full_path}")
                        schedule_event("add", section_id, path_to_fix=full_path)

        except Exception as e:
            print(f"Watcher exception: {e}", file=sys.stderr)
            time.sleep(2)

if __name__ == "__main__":
    main()
