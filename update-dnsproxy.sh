#!/bin/bash
# Percorso binario
BIN_PATH="/usr/local/bin/dnsproxy"
# Versione attuale
CURRENT_VER=$($BIN_PATH --version 2>/dev/null | awk '{print $3}')
# Ultima versione su GitHub
LATEST_VER=$(curl -s https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ "$CURRENT_VER" == "$LATEST_VER" ]; then
    echo "dnsproxy è già aggiornato ($CURRENT_VER)."
    exit 0
fi

echo "Aggiornamento disponibile: $CURRENT_VER -> $LATEST_VER"
URL="https://github.com/AdguardTeam/dnsproxy/releases/download/${LATEST_VER}/dnsproxy-linux-amd64-${LATEST_VER}.tar.gz"

cd /tmp && wget -qO dnsproxy.tar.gz "$URL" && \
tar -xzf dnsproxy.tar.gz && \
sudo systemctl stop dnsproxy && \
sudo mv linux-amd64/dnsproxy $BIN_PATH && \
sudo chmod +x $BIN_PATH && \
sudo systemctl start dnsproxy && \
echo "Aggiornamento completato con successo!"
