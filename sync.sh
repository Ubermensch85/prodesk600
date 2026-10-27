#!/usr/bin/env bash
# =============================================================================
#  sync.sh — Sincronizzazione automatica configurazioni ProDesk600 -> GitHub
# =============================================================================
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

echo "=== Sincronizzazione configurazioni HP ProDesk 600 ==="

# 1. Debian & Systemd
echo "[+] Copia configurazioni di sistema..."
cp /etc/systemd/system/dnsproxy.service "$REPO_DIR/debian-system/systemd/" 2>/dev/null || true
cp /etc/systemd/system/dns-check.service "$REPO_DIR/debian-system/systemd/" 2>/dev/null || true
cp /etc/systemd/system/dns-check.timer "$REPO_DIR/debian-system/systemd/" 2>/dev/null || true
cp /etc/dhcpcd.conf "$REPO_DIR/debian-system/network/" 2>/dev/null || true
sudo ufw status verbose > "$REPO_DIR/debian-system/ufw/ufw-status.txt" 2>/dev/null || true
cp /home/ubermensch/ufw-setup.sh "$REPO_DIR/debian-system/ufw/" 2>/dev/null || true

# 2. DNS & Network
echo "[+] Copia stack DNS & dnsproxy..."
cp /etc/dnsproxy/config.yaml "$REPO_DIR/dns-network/dnsproxy/" 2>/dev/null || true

# Sanitizzazione Pi-hole
if [[ -f /etc/pihole/pihole.toml ]]; then
  sudo sed -e 's/pwhash = .*/pwhash = "<REDACTED>"/' \
           -e 's/totp_secret = .*/totp_secret = "<REDACTED>"/' \
           -e 's/app_pwhash = .*/app_pwhash = "<REDACTED>"/' \
           /etc/pihole/pihole.toml > "$REPO_DIR/dns-network/pihole/pihole.toml"
fi

cp /home/ubermensch/verify.sh "$REPO_DIR/dns-network/scripts/" 2>/dev/null || true
cp /home/ubermensch/update-dnsproxy.sh "$REPO_DIR/dns-network/scripts/" 2>/dev/null || true

# Sanitizzazione Script Telegram
if [[ -f /usr/local/bin/dns-sentinel.sh ]]; then
  sed -e 's/BOT_TOKEN=".*"/BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-YOUR_BOT_TOKEN}"/' \
      -e 's/CHAT_ID=".*"/CHAT_ID="${TELEGRAM_CHAT_ID:-YOUR_CHAT_ID}"/' \
      /usr/local/bin/dns-sentinel.sh > "$REPO_DIR/dns-network/scripts/dns-sentinel.sh"
fi

if [[ -f /usr/local/bin/dns-report-telegram.sh ]]; then
  sed -e 's/BOT_TOKEN=".*"/BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-YOUR_BOT_TOKEN}"/' \
      -e 's/CHAT_ID=".*"/CHAT_ID="${TELEGRAM_CHAT_ID:-YOUR_CHAT_ID}"/' \
      /usr/local/bin/dns-report-telegram.sh > "$REPO_DIR/dns-network/scripts/dns-report-telegram.sh"
fi

# 3. Multimedia Stack
echo "[+] Copia configurazioni multimedia (Samba, Transmission, Plex)..."
cp /etc/samba/smb.conf "$REPO_DIR/multimedia/samba/" 2>/dev/null || true

if [[ -f /etc/transmission-daemon/settings.json ]]; then
  sudo sed -e 's/"rpc-password": .*/"rpc-password": "<REDACTED>",/' \
           /etc/transmission-daemon/settings.json > "$REPO_DIR/multimedia/transmission/settings.json"
fi

cp /var/lib/transmission-daemon/torrent-done.sh "$REPO_DIR/multimedia/transmission/" 2>/dev/null || true
cp /usr/local/bin/plex-media-watcher.py "$REPO_DIR/multimedia/plex/" 2>/dev/null || true
cp /usr/local/bin/sort-plex-media.py "$REPO_DIR/multimedia/scripts/" 2>/dev/null || true
cp /usr/local/bin/optimize-mkv-audio.py "$REPO_DIR/multimedia/scripts/" 2>/dev/null || true
cp /home/ubermensch/scaricamp3.sh "$REPO_DIR/multimedia/scripts/" 2>/dev/null || true

# 4. Git commit & push
git add .

if git diff --staged --quiet; then
  echo "✔ Nessuna modifica rilevata. Il repository è già allineato."
else
  echo "[+] Modifiche rilevate. Creazione commit..."
  COMMIT_MSG="${1:-Auto-backup configurazioni ProDesk600: $(date '+%Y-%m-%d %H:%M')}"
  git commit -m "$COMMIT_MSG"
  echo "[+] Esecuzione push su GitHub..."
  git push origin main
  echo "✔ Backup caricato con successo su GitHub!"
fi
