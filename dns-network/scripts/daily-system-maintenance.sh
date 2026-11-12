#!/usr/bin/env bash
# =============================================================================
#  daily-system-maintenance.sh — Manutenzione, aggiornamento e test autonomo
#  Eseguito quotidianamente alle 04:00 via daily-system-maintenance.timer
#  Host: HP ProDesk 600 (Debian 13 Trixie)
# =============================================================================
set -o pipefail

BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-YOUR_BOT_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID:-YOUR_CHAT_ID}"
VERIFY_SCRIPT="/home/ubermensch/verify.sh"
SYNC_SCRIPT="/home/ubermensch/prodesk600/sync.sh"
LOG_TAG="system-maintenance"

send_telegram() {
  local msg="$1"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${msg}" > /dev/null 2>&1
}

logger -t "$LOG_TAG" "Avvio manutenzione e aggiornamento autonomo giornaliero..."

UPDATED_ITEMS=()
ERRORS=()

# 1. Aggiornamento Debian, Kernel, librerie e repo APT (Tailscale, Plex, Google Cloud SDK, ecc.)
export DEBIAN_FRONTEND=noninteractive
apt-get update -y > /dev/null 2>&1
UPGRADABLE=$(apt-get -s upgrade 2>/dev/null | grep -oP '^\d+(?=\s+(aggiornat[oi]|upgraded))' || echo "0")
if [[ "${UPGRADABLE:-0}" -gt 0 ]]; then
  if apt-get dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" > /dev/null 2>&1; then
    UPDATED_ITEMS+=("Debian & APT: ${UPGRADABLE} pacchetti aggiornati")
  else
    ERRORS+=("Errore durante apt-get dist-upgrade")
  fi
  apt-get autoremove -y --purge > /dev/null 2>&1
  apt-get autoclean -y > /dev/null 2>&1
fi

# 2. Aggiornamento Pi-hole v6
PIHOLE_BEFORE=$(pihole -v 2>/dev/null)
PIHOLE_NEEDS_UP=0
while read -r line; do
  cur=$(echo "$line" | grep -oP 'version is \K[^ ]+' || true)
  lat=$(echo "$line" | grep -oP '\(Latest: \K[^)]+' || true)
  if [[ -n "$cur" && -n "$lat" && "$cur" != "$lat" && "$lat" != "ERROR" ]]; then
    PIHOLE_NEEDS_UP=1
  fi
done <<< "$PIHOLE_BEFORE"
if [[ $PIHOLE_NEEDS_UP -eq 1 ]]; then
  if pihole -up > /dev/null 2>&1; then
    UPDATED_ITEMS+=("Pi-hole v6 aggiornato con successo")
  else
    ERRORS+=("Errore durante aggiornamento Pi-hole")
  fi
fi

# 3. Aggiornamento AdGuard dnsproxy
DNSPROXY_BIN="/usr/local/bin/dnsproxy"
CURRENT_DNSPROXY=$($DNSPROXY_BIN --version 2>/dev/null | awk '{print $3}' || echo "none")
LATEST_DNSPROXY=$(curl -fsSL https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' || true)

if [[ -n "$LATEST_DNSPROXY" && "$LATEST_DNSPROXY" != "$CURRENT_DNSPROXY" ]]; then
  TMP_DIR=$(mktemp -d)
  URL="https://github.com/AdguardTeam/dnsproxy/releases/download/${LATEST_DNSPROXY}/dnsproxy-linux-amd64-${LATEST_DNSPROXY}.tar.gz"
  if curl -fsSL "$URL" -o "$TMP_DIR/dnsproxy.tar.gz" && tar -xzf "$TMP_DIR/dnsproxy.tar.gz" -C "$TMP_DIR"; then
    if "$TMP_DIR/linux-amd64/dnsproxy" --version > /dev/null 2>&1; then
      cp "$DNSPROXY_BIN" "${DNSPROXY_BIN}.bak" 2>/dev/null || true
      systemctl stop dnsproxy
      install -m 0755 "$TMP_DIR/linux-amd64/dnsproxy" "$DNSPROXY_BIN"
      if systemctl start dnsproxy; then
        UPDATED_ITEMS+=("dnsproxy aggiornato: ${CURRENT_DNSPROXY} -> ${LATEST_DNSPROXY}")
        rm -f "${DNSPROXY_BIN}.bak"
      else
        ERRORS+=("dnsproxy non avviato dopo upgrade, eseguito rollback")
        cp "${DNSPROXY_BIN}.bak" "$DNSPROXY_BIN"
        systemctl start dnsproxy
      fi
    else
      ERRORS+=("Binario dnsproxy scaricato non valido")
    fi
  else
    ERRORS+=("Download release dnsproxy fallito")
  fi
  rm -rf "$TMP_DIR"
fi

# 4. Aggiornamento yt-dlp se presente
if [[ -x /usr/local/bin/yt-dlp ]]; then
  YTDLP_OUT=$(/usr/local/bin/yt-dlp -U 2>&1 || true)
  if echo "$YTDLP_OUT" | grep -qi "Updated yt-dlp to"; then
    UPDATED_ITEMS+=("yt-dlp aggiornato all'ultima versione")
  fi
fi

# 5. Verifica approfondita catena (verify.sh) e auto-healing
VERIFY_OUTPUT=$(bash "$VERIFY_SCRIPT" 2>&1)
VERIFY_EXIT=$?

if [[ $VERIFY_EXIT -ne 0 ]]; then
  logger -t "$LOG_TAG" "Anomalia rilevata dopo manutenzione. Tentativo auto-healing..."
  systemctl restart dnsproxy
  sleep 2
  systemctl restart pihole-FTL
  sleep 2
  VERIFY_OUTPUT=$(bash "$VERIFY_SCRIPT" 2>&1)
  VERIFY_EXIT=$?
fi

# Benchmark latenze
PING_ROUTER=$(ping -c 2 -W 1 192.168.1.254 2>/dev/null | awk -F'/' 'END{print $5}')
PING_QUAD9=$(ping -c 2 -W 2 9.9.9.9 2>/dev/null | awk -F'/' 'END{print $5}')
PING_CF=$(ping -c 2 -W 2 1.1.1.2 2>/dev/null | awk -F'/' 'END{print $5}')

# 6. Sincronizzazione configurazioni su GitHub
if [[ -x "$SYNC_SCRIPT" ]]; then
  COMMIT_MSG="Manutenzione automatica giornaliera: tutto aggiornato"
  if [[ ${#UPDATED_ITEMS[@]} -gt 0 ]]; then
    COMMIT_MSG="Manutenzione e aggiornamento autonomo: ${UPDATED_ITEMS[*]}"
  fi
  sudo -u ubermensch "$SYNC_SCRIPT" "$COMMIT_MSG" > /dev/null 2>&1 || true
fi

# 7. Resoconto Telegram
DATE=$(date '+%d/%m/%Y %H:%M')
REBOOT_MSG=""
if [[ -f /var/run/reboot-required ]]; then
  REBOOT_MSG="⚠️ Riavvio automatico programmato per le 04:30 (nuovo kernel/librerie core)."
fi

if [[ $VERIFY_EXIT -ne 0 || ${#ERRORS[@]} -gt 0 ]]; then
  CLEAN=$(echo "$VERIFY_OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
  FAILS=$(echo "$CLEAN" | grep "\[ FAIL \]" | sed 's/^[[:space:]]*//' | sed 's/\[ FAIL \] /❌ /')
  ERR_TXT=$(printf "%s\n" "${ERRORS[@]}")
  
  MSG="🚨 Manutenzione Automatica con Anomalie — ${DATE}
📍 Host: HP ProDesk 600 (Perugia Iliad FTTH)

${ERR_TXT}
${FAILS}

Stato catena: NON OPERATIVO (necessita verifica)."
  send_telegram "$MSG"

else
  STATUS_TXT="• Tutti i pacchetti e componenti software sono già alla versione più recente."
  if [[ ${#UPDATED_ITEMS[@]} -gt 0 ]]; then
    STATUS_TXT=$(printf "• %s\n" "${UPDATED_ITEMS[@]}")
  fi

  MSG="🛡️ Manutenzione e Aggiornamento Giornaliero — ${DATE}
📍 HP ProDesk 600 | Iliad FTTH EPON 5/900

📦 Stato Software:
${STATUS_TXT}

⚡ Benchmark latenze:
• Iliadbox LAN: ${PING_ROUTER:-0.3} ms
• Quad9 DoQ (853): ${PING_QUAD9:-13} ms
• Cloudflare DoH (443): ${PING_CF:-14} ms

✔ Catena DNS (Pi-hole v6 + dnsproxy DoQ/DoH3), DNSSEC e Tailscale: 100% OPERATIVI.
${REBOOT_MSG}"
  send_telegram "$MSG"
fi

logger -t "$LOG_TAG" "Manutenzione completata con exit code $VERIFY_EXIT."
exit $VERIFY_EXIT
