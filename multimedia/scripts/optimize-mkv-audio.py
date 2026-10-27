#!/usr/bin/env python3
import sys
import os
import json
import subprocess
from pathlib import Path

def is_italian(track):
    props = track.get("properties", {})
    lang = (props.get("language") or "").lower()
    lang_ietf = (props.get("language_ietf") or "").lower()
    name = (props.get("track_name") or "").lower()
    if lang in ("ita", "it"):
        return True
    if lang_ietf.startswith("it"):
        return True
    if "ita" in name or "italian" in name or "italiano" in name:
        return True
    return False

def get_codec_score(track):
    codec = (track.get("codec") or "").upper()
    props = track.get("properties", {})
    name = (props.get("track_name") or "").lower()
    channels = props.get("audio_channels", 2)

    # Higher score = more compatible / preferred for TV playback
    if "AC-3" in codec and "E-AC-3" not in codec:
        score = 100
    elif "AAC" in codec:
        score = 95
    elif "E-AC-3" in codec:
        score = 40 if "atmos" in name else 50
    elif "DTS-HD" in codec:
        score = 20
    elif "DTS" in codec:
        score = 30
    elif "TRUEHD" in codec:
        score = 15
    elif "FLAC" in codec:
        score = 25
    else:
        score = 10

    if channels in (2, 6):
        score += 2

    return score

def process_mkv(file_path, verbose=False):
    path = Path(file_path)
    if not path.is_file() or path.suffix.lower() != ".mkv":
        return

    try:
        res = subprocess.run(
            ["mkvmerge", "-J", str(path)],
            capture_output=True,
            text=True,
            check=True
        )
        data = json.loads(res.stdout)
    except Exception as e:
        print(f"[ERROR] Could not inspect {path.name}: {e}")
        return

    all_tracks = data.get("tracks", [])
    audio_tracks = [t for t in all_tracks if t.get("type") == "audio"]

    if not audio_tracks:
        return

    ita_tracks = [t for t in audio_tracks if is_italian(t)]
    candidate_tracks = ita_tracks if ita_tracks else audio_tracks

    best_track = max(candidate_tracks, key=get_codec_score)
    best_id = best_track.get("id")

    needs_update = False
    for t in audio_tracks:
        is_best = (t.get("id") == best_id)
        current_default = t.get("properties", {}).get("default_track", False)
        if is_best and not current_default:
            needs_update = True
        elif not is_best and current_default:
            needs_update = True

    if not needs_update:
        if verbose:
            props = best_track.get("properties", {})
            print(f"[OK-ALREADY] {path.name} -> already optimal: #{best_id} ({best_track.get("codec")}, {props.get("language")})")
        return

    cmd = ["mkvpropedit", str(path)]
    for idx, t in enumerate(audio_tracks, start=1):
        is_best = (t.get("id") == best_id)
        cmd.extend(["--edit", f"track:a{idx}", "--set", f"flag-default={1 if is_best else 0}"])

    try:
        subprocess.run(cmd, capture_output=True, text=True, check=True)
        props = best_track.get("properties", {})
        codec = best_track.get("codec")
        lang = props.get("language") or "und"
        name = props.get("track_name") or ""
        print(f"[UPDATED] {path.name} -> default track set to #{best_id} ({codec}, {lang}, {name})")
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] mkvpropedit failed on {path.name}: {e.stderr}")

def main():
    args = sys.argv[1:]
    verbose = "-v" in args or "--verbose" in args
    paths = [a for a in args if not a.startswith("-")]

    if not paths:
        print("Usage: optimize-mkv-audio.py [-v|--verbose] <file-or-dir> ...")
        sys.exit(1)

    for arg in paths:
        p = Path(arg)
        if p.is_file():
            process_mkv(p, verbose=verbose)
        elif p.is_dir():
            for root, _, files in os.walk(p):
                for f in sorted(files):
                    if f.lower().endswith(".mkv"):
                        process_mkv(Path(root) / f, verbose=verbose)

if __name__ == "__main__":
    main()
