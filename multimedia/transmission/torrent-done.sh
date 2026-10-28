#!/bin/bash
# =============================================================================
#  Transmission hook: Post-torrent completion
# =============================================================================
# Environment variables: TR_TORRENT_DIR, TR_TORRENT_NAME, TR_TORRENT_ID

LOG="/var/lib/transmission-daemon/torrent-done.log"

{
  echo "=== Torrent completed: $(date) ==="
  echo "DIR: $TR_TORRENT_DIR | NAME: $TR_TORRENT_NAME | ID: $TR_TORRENT_ID"
} >> "$LOG" 2>/dev/null || true

if [ -n "$TR_TORRENT_DIR" ] && [ -n "$TR_TORRENT_NAME" ]; then
    /usr/local/bin/sort-plex-media.py "$TR_TORRENT_DIR" "$TR_TORRENT_NAME" "$TR_TORRENT_ID" >> "$LOG" 2>&1 || \
    /usr/local/bin/sort-plex-media.py "$TR_TORRENT_DIR" "$TR_TORRENT_NAME" "$TR_TORRENT_ID" || true
fi

exit 0
