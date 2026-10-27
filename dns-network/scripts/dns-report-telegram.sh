#!/bin/bash
# =============================================================================
#  dns-report-telegram.sh — Notifica Telegram esito verifica catena DNS
#  Dipende da: verify.sh (exit 0=ok, 1+=errori, 99=solo warning)
# =============================================================================

# ── Configurazione ────────────────────────────────────────────────────────────
BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-YOUR_BOT_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID:-YOUR_CHAT_ID}"
VERIFY_SCRIPT="/home/ubermensch/verify.sh"

# ── Esegui verify.sh ─────────────────────────────────────────────────────────
OUTPUT=$(bash "$VERIFY_SCRIPT" 2>&1)
EXIT_CODE=$?

# Rimuovi codici colore ANSI per testo pulito
CLEAN=$(echo "$OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
DATE=$(date '+%d/%m/%Y %H:%M')

# ── Funzione invio Telegram ───────────────────────────────────────────────────
send_telegram() {
  local message="$1"
  curl -s "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${message}" \
    > /dev/null 2>&1
}

# ── Gestione exit code ────────────────────────────────────────────────────────
# exit 0   → tutto ok, nessuna notifica
# exit 99  → solo warning, notifica leggera
# exit 1+  → errori critici, notifica urgente

if [[ $EXIT_CODE -eq 0 ]]; then
  exit 0

elif [[ $EXIT_CODE -eq 99 ]]; then
  WARNS=$(echo "$CLEAN" | grep "\[ WARN \]" | sed 's/^[[:space:]]*//' | sed 's/\[ WARN \] /⚠️ /')
  WARN_COUNT=$(echo "$WARNS" | grep -c "⚠️" || echo 0)

  MESSAGE="⚠️ DNS Chain WARNING — ${DATE}
Avvisi: ${WARN_COUNT}

${WARNS}

ℹ️ Nessun errore critico — sistema operativo"

  send_telegram "$MESSAGE"

else
  FAILS=$(echo "$CLEAN" | grep "\[ FAIL \]" | sed 's/^[[:space:]]*//' | sed 's/\[ FAIL \] /❌ /')
  WARNS=$(echo "$CLEAN" | grep "\[ WARN \]" | sed 's/^[[:space:]]*//' | sed 's/\[ WARN \] /⚠️ /')
  ERR_COUNT=$(echo "$FAILS" | grep -c "❌" || echo 0)
  WARN_COUNT=$(echo "$WARNS" | grep -c "⚠️" || echo 0)

  MESSAGE="🚨 DNS Chain ALERT — ${DATE}
Errori: ${ERR_COUNT} | Avvisi: ${WARN_COUNT}

${FAILS}
${WARNS}

🔧 Esegui: sudo systemctl status dnsproxy pihole-FTL"

  send_telegram "$MESSAGE"
fi
