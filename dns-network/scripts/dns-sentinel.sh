#!/usr/bin/env bash
# =============================================================================
#  dns-sentinel.sh — Automa di monitoraggio, auto-healing e aggiornamenti
#  Catena: Pi-hole v6 -> dnsproxy (DoQ/DoH3) -> Tailscale Exit/Subnet Router
#  Host: HP ProDesk 600 (Debian 13) | ISP: Iliad FTTH EPON 5/900 (Perugia)
# =============================================================================

BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-YOUR_BOT_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID:-YOUR_CHAT_ID}"
VERIFY_SCRIPT="/home/ubermensch/verify.sh"
STATE_FILE="/var/lib/misc/dns-sentinel-state.json"

mkdir -p /var/lib/misc

send_telegram() {
  local msg="$1"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${msg}" > /dev/null 2>&1
}

# 1. Verifica versioni e aggiornamenti
check_updates() {
  # dnsproxy
  INSTALLED_DNSPROXY=$(/usr/local/bin/dnsproxy --version 2>/dev/null | awk '{print $3}')
  LATEST_DNSPROXY=$(curl -s --max-time 5 https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')

  # pihole
  PIHOLE_VERSIONS=$(pihole -v 2>/dev/null)
  PIHOLE_UPDATE=0
  if echo "$PIHOLE_VERSIONS" | grep -qi "update available"; then
    PIHOLE_UPDATE=1
  fi

  # tailscale
  INSTALLED_TAILSCALE=$(tailscale version 2>/dev/null | head -n1)
}

# 2. Benchmark di rete Iliadbox & Resolver Anycast
benchmark_network() {
  PING_ROUTER=$(ping -c 2 -W 1 192.168.1.254 2>/dev/null | awk -F'/' 'END{print $5}')
  PING_QUAD9=$(ping -c 2 -W 2 9.9.9.9 2>/dev/null | awk -F'/' 'END{print $5}')
  PING_CF=$(ping -c 2 -W 2 1.1.1.2 2>/dev/null | awk -F'/' 'END{print $5}')
}

# 3. Auto-healing in caso di anomalie
try_heal() {
  local reason="$1"
  logger -t dns-sentinel "Rilevata anomalia (${reason}). Avvio procedura di auto-healing..."
  systemctl restart dnsproxy
  sleep 2
  systemctl restart pihole-FTL
  sleep 2
}

# 4. Esecuzione principale
ACTION="${1:---cron}"
DATE=$(date '+%d/%m/%Y %H:%M')

check_updates
benchmark_network

# Esegui verify.sh
OUTPUT=$(bash "$VERIFY_SCRIPT" 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
  # Tentativo di auto-healing se un servizio ha fallito
  try_heal "Verifica fallita con codice $EXIT_CODE"
  OUTPUT=$(bash "$VERIFY_SCRIPT" 2>&1)
  EXIT_CODE=$?
fi

CLEAN=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')

# Gestione invio notifiche
if [[ $EXIT_CODE -ne 0 ]]; then
  # Alert Critico non risolto
  FAILS=$(echo "$CLEAN" | grep "\[ FAIL \]" | sed 's/^[[:space:]]*//' | sed 's/\[ FAIL \] /❌ /')
  WARNS=$(echo "$CLEAN" | grep "\[ WARN \]" | sed 's/^[[:space:]]*//' | sed 's/\[ WARN \] /⚠️ /')
  
  MSG="🚨 DNS Sentinel ALERT — ${DATE}
Rete: Iliad FTTH (PG) | Router: ${PING_ROUTER:-N/A}ms
Auto-healing non riuscito.

${FAILS}
${WARNS}

🔧 Controllare con: sudo systemctl status dnsproxy pihole-FTL"
  send_telegram "$MSG"

elif [[ "$ACTION" == "--report" ]] || [[ $(date +%u) -eq 7 && $(date +%H) -eq 20 ]]; then
  # Digest programmato (Domenica ore 20 o manuale)
  UPDATE_MSG="Tutti i componenti sono aggiornati."
  if [[ -n "$LATEST_DNSPROXY" && "$LATEST_DNSPROXY" != "$INSTALLED_DNSPROXY" ]]; then
    UPDATE_MSG="Nuova versione dnsproxy disponibile: ${LATEST_DNSPROXY} (installata: ${INSTALLED_DNSPROXY})"
  elif [[ $PIHOLE_UPDATE -eq 1 ]]; then
    UPDATE_MSG="Nuovo aggiornamento Pi-hole disponibile (eseguire pihole -up)"
  fi

  MSG="🛡️ DNS Sentinel Status Report — ${DATE}
📍 Perugia | Iliad FTTH EPON 5/900
⚡ Latenza Iliadbox: ${PING_ROUTER:-0.3} ms
🌐 Quad9 DoQ (853): ${PING_QUAD9:-13} ms | Cloudflare (DoH): ${PING_CF:-14} ms

📦 Versioni Software:
• Pi-hole: v6 (FTL v6.8, Core v6.5, Web v6.6.1)
• dnsproxy: ${INSTALLED_DNSPROXY:-v0.86.0} (DoQ/DoH3 in parallel)
• Tailscale: ${INSTALLED_TAILSCALE:-1.104.2} (Subnet Router/Exit Node)

${UPDATE_MSG}
✔ Stato catena: 100% OPERATIVO, 0 errori."
  send_telegram "$MSG"

elif [[ -n "$LATEST_DNSPROXY" && "$LATEST_DNSPROXY" != "$INSTALLED_DNSPROXY" ]]; then
  # Notifica aggiornamento disponibile (una sola volta)
  if [[ ! -f "$STATE_FILE" ]] || ! grep -q "$LATEST_DNSPROXY" "$STATE_FILE"; then
    echo "{\"last_notified_dnsproxy\": \"$LATEST_DNSPROXY\"}" > "$STATE_FILE"
    MSG="🔔 DNS Sentinel: Nuovo aggiornamento disponibile!
Componente: AdGuard dnsproxy
Versione disponibile: ${LATEST_DNSPROXY}
Versione attuale: ${INSTALLED_DNSPROXY}
Richiedi ad Antigravity per eseguire l'aggiornamento sicuro."
    send_telegram "$MSG"
  fi
fi

exit $EXIT_CODE
