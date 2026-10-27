#!/bin/bash
set -euo pipefail
BIN_PATH="/usr/local/bin/dnsproxy"
CURRENT_VER=$($BIN_PATH --version 2>/dev/null | awk '{print $3}' || echo "none")
LATEST_VER=$(curl -fsSL https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)

if [ -z "$LATEST_VER" ]; then
    echo "Impossibile verificare l'ultima versione di dnsproxy su GitHub."
    exit 0
fi

if [ "$CURRENT_VER" == "$LATEST_VER" ]; then
    echo "dnsproxy è già aggiornato ($CURRENT_VER)."
    exit 0
fi

echo "Aggiornamento disponibile: $CURRENT_VER -> $LATEST_VER"
URL="https://github.com/AdguardTeam/dnsproxy/releases/download/${LATEST_VER}/dnsproxy-linux-amd64-${LATEST_VER}.tar.gz"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

wget -qO "$TMP_DIR/dnsproxy.tar.gz" "$URL" && \
tar -xzf "$TMP_DIR/dnsproxy.tar.gz" -C "$TMP_DIR" && \
sudo systemctl stop dnsproxy && \
sudo install -m 0755 "$TMP_DIR/linux-amd64/dnsproxy" "$BIN_PATH" && \
sudo systemctl start dnsproxy && \
echo "Aggiornamento completato con successo!"
