#!/bin/bash

# Transmission environment variables:
# TR_TORRENT_DIR, TR_TORRENT_NAME, TR_TORRENT_ID

LOG="/var/lib/transmission-daemon/torrent-done.log"

echo "=== Torrent completed: $(date) ===" >> "$LOG"
echo "DIR: $TR_TORRENT_DIR | NAME: $TR_TORRENT_NAME | ID: $TR_TORRENT_ID" >> "$LOG"

if [ -n "$TR_TORRENT_DIR" ] && [ -n "$TR_TORRENT_NAME" ]; then
    /usr/local/bin/sort-plex-media.py "$TR_TORRENT_DIR" "$TR_TORRENT_NAME" "$TR_TORRENT_ID" >> "$LOG" 2>&1
fi

exit 0
