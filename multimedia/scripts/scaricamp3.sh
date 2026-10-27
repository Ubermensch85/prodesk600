#!/usr/bin/env bash
set -euo pipefail
usage() { echo "Uso: $0 -i <URL> [-t <TITOLO>]"; exit 1; }
URL=""
TITLE="%(title)s"
OUTDIR="${HOME}/Musica/Catona"
while getopts "i:t:h" opt; do
  case $opt in
    i) URL="$OPTARG" ;;
    t) TITLE="$OPTARG" ;;
    *) usage ;;
  esac
done
[[ -z "$URL" ]] && usage
mkdir -p "$OUTDIR"
CLEAN_TITLE=$(echo "$TITLE" | tr ' ' '_')
yt-dlp -x --audio-format mp3 --audio-quality 0 \
    --no-embed-metadata --no-embed-thumbnail \
    --restrict-filenames \
    -o "${OUTDIR}/${CLEAN_TITLE}.%(ext)s" "$URL"
