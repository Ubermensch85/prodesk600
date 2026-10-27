#!/usr/bin/env bash
# =============================================================================
#  verify.sh — Verifica catena DNS: dnsproxy (DoQ+DoH) → Pi-hole → Quad9/CF
# =============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ ERRORE ] Questo script richiede privilegi di root. Esegui con: sudo $0${RESET}"
  exit 1
fi
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
PASS="${GREEN}[  OK  ]${RESET}"; FAIL="${RED}[ FAIL ]${RESET}"
WARN="${YELLOW}[ WARN ]${RESET}"; INFO="${CYAN}[ INFO ]${RESET}"
ERRORS=0; WARNINGS=0
# ── Configurazione ──────────────────────────────────────────
PIHOLE_IP="127.0.0.1";   PIHOLE_PORT="53"
DNSPROXY_IP="127.0.0.1"; DNSPROXY_PORT="5353"
ADS_DOMAIN="ad.it.doubleclick.net"
TEST_DOMAIN="google.com"
DNSSEC_FAIL_DOMAIN="dnssec-failed.org"
# IP diretti upstream (per test indipendenti dal resolver locale)
QUAD9_IP="9.9.9.9"
CLOUDFLARE_IP="1.1.1.2"
# ────────────────────────────────────────────────────────────
banner()  { echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗
║     DNS Chain Checker — Pi-hole + dnsproxy (DoQ/DoH) ║
╚══════════════════════════════════════════════════════╝${RESET}\n  Data: $(date '+%Y-%m-%d %H:%M:%S')\n"; }
section() { echo -e "\n${BOLD}▶ $1${RESET}"; }
ok()      { echo -e "  ${PASS} $1"; }
fail()    { echo -e "  ${FAIL} $1"; ((ERRORS++)); }
warn()    { echo -e "  ${WARN} $1"; ((WARNINGS++)); }
info()    { echo -e "  ${INFO} $1"; }

check_deps() {
  section "Dipendenze"
  for cmd in dig systemctl grep awk ip timeout tcpdump lsof curl; do
    command -v "$cmd" &>/dev/null \
      && ok "Comando '$cmd' disponibile" \
      || warn "Comando '$cmd' mancante (alcuni check potrebbero saltare)"
  done
}

check_services() {
  section "1. Stato servizi"
  for svc in pihole-FTL dnsproxy; do
    state=$(systemctl is-active "$svc" 2>/dev/null)
    [[ "$state" == "active" ]] \
      && ok "Servizio '$svc' è ACTIVE" \
      || fail "Servizio '$svc' è '$state'"
  done
}

check_proxy() {
  section "2. dnsproxy (${DNSPROXY_IP}:${DNSPROXY_PORT})"
  result=$(dig @"${DNSPROXY_IP}" -p "${DNSPROXY_PORT}" "${TEST_DOMAIN}" +short +time=3 2>/dev/null)
  if [[ -n "$result" ]]; then
    ok "dnsproxy risponde: ${result}"
  else
    fail "Nessuna risposta da dnsproxy sulla porta ${DNSPROXY_PORT}"
  fi
}

check_pihole() {
  section "3. Pi-hole (${PIHOLE_IP}:${PIHOLE_PORT})"
  result=$(dig @"${PIHOLE_IP}" -p "${PIHOLE_PORT}" "${TEST_DOMAIN}" +short +time=3 2>/dev/null)
  [[ -n "$result" ]] && ok "Pi-hole risponde: ${result}" || fail "Nessuna risposta da Pi-hole"

  PIHOLE_CONFIG="/etc/pihole/pihole.toml"
  if [[ -f "$PIHOLE_CONFIG" ]]; then
    if grep -q "${DNSPROXY_PORT}" "$PIHOLE_CONFIG"; then
      ok "Pi-hole v6 configurato verso porta ${DNSPROXY_PORT} (in pihole.toml)"
    else
      fail "Upstream porta ${DNSPROXY_PORT} non trovato in $PIHOLE_CONFIG"
    fi
    # Mostra upstream effettivi usati da Pi-hole (solo valori, no commenti)
    upstream_vals=$(grep -A10 'upstreams = \[' "$PIHOLE_CONFIG" 2>/dev/null \
      | grep -oP '"[^"]+"' | tr -d '"')
    if [[ -n "$upstream_vals" ]]; then
      info "Upstream Pi-hole configurati:"
      while IFS= read -r u; do info "  $u"; done <<< "$upstream_vals"
    else
      warn "Impossibile leggere upstream da $PIHOLE_CONFIG"
    fi
  else
    warn "File $PIHOLE_CONFIG non trovato — impossibile verificare configurazione upstream"
  fi
}

check_blocking() {
  section "4. Blocco annunci (${ADS_DOMAIN})"
  output=$(dig @"${PIHOLE_IP}" "${ADS_DOMAIN}" +time=2 2>/dev/null)
  result=$(echo "$output" | awk '/^;; ANSWER/{found=1; next} found && /IN\s+A/{print $NF; exit}')
  status=$(echo "$output" | grep -o "NXDOMAIN\|NOERROR\|SERVFAIL" | head -1)

  if [[ -z "$result" || "$result" == "0.0.0.0" || "$status" == "NXDOMAIN" ]]; then
    local note=""
    [[ -z "$result" && "$status" == "NOERROR" ]] && note=" — risposta vuota = blocco Pi-hole v6"
    ok "Annunci bloccati correttamente (status: ${status:-empty}, IP: ${result:-none})${note}"
  else
    warn "Annunci NON bloccati (status: ${status}, IP: ${result})"
  fi
}

check_upstream_quad9() {
  section "5. Upstream & protocolli"

  svc_file="/etc/systemd/system/dnsproxy.service"
  cfg_file="/etc/dnsproxy/config.yaml"

  if [[ -f "$cfg_file" ]]; then
    quic_upstreams=$(awk '/^upstream:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag' "$cfg_file" | grep -oP 'quic://\S+')
    doh_upstreams=$(awk '/^upstream:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag' "$cfg_file" | grep -oP 'https://\S+')
    fallback_upstreams=$(awk '/^fallback:/{flag=1; next} /^[a-zA-Z]/{flag=0} flag' "$cfg_file" | grep -oP '(quic|https)://\S+')
    upstream_mode=$(grep '^upstream-mode:' "$cfg_file" 2>/dev/null | awk '{print $2}')
  elif [[ -f "$svc_file" ]]; then
    # Mostra tutti gli upstream configurati
    # Upstream primari: righe con -u (distinte da --fallback)
    quic_upstreams=$(grep -P '^\s+-u quic://' "$svc_file" 2>/dev/null | grep -oP 'quic://[^\s\\]+')
    doh_upstreams=$(grep -P '^\s+-u https://' "$svc_file" 2>/dev/null | grep -oP 'https://[^\s\\]+')
    fallback_upstreams=$(grep -P '^\s+--fallback' "$svc_file" 2>/dev/null | grep -oP '(quic|https)://[^\s\\]+')
    upstream_mode=$(grep -oP '(?<=--upstream-mode=)\S+' "$svc_file" 2>/dev/null)
  else
    fail "Configurazione dnsproxy non trovata"
  fi

  if [[ -n "$quic_upstreams" ]]; then
    ok "Upstream primari DoQ (QUIC):"
    while IFS= read -r u; do info "  $u"; done <<< "$quic_upstreams"
  else
    warn "Nessun upstream QUIC primario trovato"
  fi

  if [[ -n "$doh_upstreams" ]]; then
    ok "Upstream primari DoH:"
    while IFS= read -r u; do info "  $u"; done <<< "$doh_upstreams"
  else
    info "Nessun upstream DoH primario configurato"
  fi

  if [[ -n "$fallback_upstreams" ]]; then
    ok "Fallback configurati:"
    while IFS= read -r u; do info "  $u"; done <<< "$fallback_upstreams"
  else
    info "Nessun fallback configurato"
  fi

  [[ -n "$upstream_mode" ]] && info "Modalità upstream: ${upstream_mode}"

  # Socket UDP attivi
  udp_sockets=$(lsof -a -i udp -c dnsproxy 2>/dev/null | grep -v "COMMAND")
  if [[ -n "$udp_sockets" ]]; then
    ok "Socket UDP attivi per dnsproxy (QUIC richiede UDP):"
    while IFS= read -r line; do info "  $line"; done <<< "$udp_sockets"
  else
    warn "Nessun socket UDP trovato per dnsproxy"
  fi

  # Verifica traffico QUIC live
  if command -v timeout &>/dev/null && command -v tcpdump &>/dev/null; then
    info "Verifica pacchetti QUIC in corso (3 secondi)..."
    # Forza una query per generare traffico
    dig @"${DNSPROXY_IP}" -p "${DNSPROXY_PORT}" "quad9-quic-test.${TEST_DOMAIN}" +short &>/dev/null &
    quic_packets=$(timeout 3 tcpdump -i any -n udp port 853 2>/dev/null | wc -l)
    if [[ "$quic_packets" -gt 0 ]]; then
      ok "Pacchetti UDP/853 catturati: $quic_packets (conferma traffico DoQ)"
    else
      info "Nessun pacchetto su :853 nel periodo di campionamento (potrebbe essere in cache)"
    fi
  fi
}

check_upstreams_direct() {
  section "6. Verifica upstream diretti"

  # Test Quad9 diretto via UDP
  result=$(dig @"${QUAD9_IP}" "${TEST_DOMAIN}" +short +time=3 2>/dev/null)
  if [[ -n "$result" ]]; then
    ok "Quad9 (${QUAD9_IP}) raggiungibile direttamente: ${result}"
  else
    fail "Quad9 (${QUAD9_IP}) non risponde"
  fi

  # Test Cloudflare diretto via UDP
  result=$(dig @"${CLOUDFLARE_IP}" "${TEST_DOMAIN}" +short +time=3 2>/dev/null)
  if [[ -n "$result" ]]; then
    ok "Cloudflare (${CLOUDFLARE_IP}) raggiungibile direttamente: ${result}"
  else
    fail "Cloudflare (${CLOUDFLARE_IP}) non risponde"
  fi

  # Test Cloudflare DoH via curl (porta 443)
  if command -v curl &>/dev/null; then
    doh_result=$(curl -sf "https://${CLOUDFLARE_IP}/dns-query?name=${TEST_DOMAIN}&type=A" \
      -H "Accept: application/dns-json" --max-time 5 2>/dev/null | grep -o '"data":"[^"]*"' | head -1)
    if [[ -n "$doh_result" ]]; then
      ok "Cloudflare DoH (https://${CLOUDFLARE_IP}/dns-query) funzionante: ${doh_result}"
    else
      warn "Cloudflare DoH non risponde o risposta non parsabile"
    fi
  fi

  # Test QUIC porta 853 raggiungibilità
  if command -v nc &>/dev/null; then
    if nc -vzu "${QUAD9_IP}" 853 &>/dev/null 2>&1; then
      ok "UDP 853 verso Quad9 (${QUAD9_IP}) aperto"
    else
      warn "UDP 853 verso Quad9 (${QUAD9_IP}) potrebbe essere bloccato"
    fi
  fi
}

check_dnssec() {
  section "7. Validazione DNSSEC"
  # Test su dnsproxy (chi valida DNSSEC è l'upstream, non Pi-hole)
  output_proxy=$(dig @"${DNSPROXY_IP}" -p "${DNSPROXY_PORT}" "${DNSSEC_FAIL_DOMAIN}" +time=3 2>/dev/null)
  output_pihole=$(dig @"${PIHOLE_IP}" "${DNSSEC_FAIL_DOMAIN}" +time=3 2>/dev/null)

  if echo "$output_proxy" | grep -q "SERVFAIL"; then
    ok "DNSSEC validato da dnsproxy: ${DNSSEC_FAIL_DOMAIN} correttamente bloccato (SERVFAIL)"
  else
    warn "DNSSEC non validato da dnsproxy (mancato SERVFAIL su ${DNSSEC_FAIL_DOMAIN})"
  fi

  if echo "$output_pihole" | grep -q "SERVFAIL"; then
    ok "DNSSEC propagato correttamente attraverso Pi-hole (SERVFAIL)"
  else
    info "Pi-hole non propaga SERVFAIL DNSSEC — verifica impostazioni DNSSEC in Pi-hole"
  fi
}

check_tailscale() {
  section "8. Tailscale"
  ts_ip=$(ip addr show tailscale0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
  if [[ -z "$ts_ip" ]]; then
    warn "Tailscale non rilevato"
    return
  fi
  ok "Tailscale attivo (IP: ${ts_ip})"
  result=$(dig @"${ts_ip}" "${TEST_DOMAIN}" +short +time=2 2>/dev/null)
  [[ -n "$result" ]] \
    && ok "Pi-hole risponde su interfaccia Tailscale: ${result}" \
    || fail "Pi-hole non risponde su interfaccia Tailscale (${ts_ip})"
}

summary() {
  echo -e "\n${BOLD}${CYAN}══════════════════════ RIEPILOGO ══════════════════════${RESET}"
  if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}✔ Catena DNS-over-QUIC/DoH perfettamente operativa!${RESET}"
  else
    [[ $ERRORS -gt 0 ]] && echo -e "  ${RED}${BOLD}✘ Errori critici: $ERRORS${RESET}"
    [[ $WARNINGS -gt 0 ]] && echo -e "  ${YELLOW}${BOLD}⚠ Avvisi: $WARNINGS${RESET}"
  fi
  echo -e "${CYAN}═══════════════════════════════════════════════════════${RESET}\n"
  # Exit codes: 0=tutto ok, 1+=errori critici, 99=solo warning
  if [[ $ERRORS -gt 0 ]]; then
    exit $ERRORS
  elif [[ $WARNINGS -gt 0 ]]; then
    exit 99
  else
    exit 0
  fi
}

banner
check_deps
check_services
check_proxy
check_pihole
check_blocking
check_upstream_quad9
check_upstreams_direct
check_dnssec
check_tailscale
summary
