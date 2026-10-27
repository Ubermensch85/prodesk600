#!/usr/bin/env bash
# =============================================================================
#  UFW SETUP — ProDesk G3 600 | Debian
#  Autore: generato per ubermensch
#  Data:    2026-04-15 (Aggiornato per dnsproxy DoQ)
#
#  Rete locale:  192.168.1.0/24  (IliadBox gateway: 192.168.1.1)
#  IP server:    192.168.1.118
#  Tailscale:    100.116.94.86  (range Tailscale: 100.64.0.0/10)
#
#  Servizi attivi:
#    - Pi-hole FTL      (DNS :53, HTTP :80, HTTPS :443)
#    - dnsproxy (DoQ)   (solo loopback :5353 — interroga Quad9 UDP :853)
#    - SSH              (:22)
#    - Samba SMB3       (:445)
#    - Plex             (:32400)
#    - Transmission     (web UI :9091, BitTorrent :51413)
#    - Tailscale        (UDP :41641)
# =============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Esegui come root: sudo bash ufw-setup.sh"
    exit 1
fi

echo ""
echo "=========================================="
echo "  UFW SETUP — ProDesk Debian (DoQ Edition)"
echo "=========================================="
echo ""

# =============================================================================
#  STEP 1 — Installazione ufw
# =============================================================================
echo "[1/8] Installazione ufw (se non presente)..."
apt-get install -y ufw > /dev/null 2>&1
echo "      OK"

# =============================================================================
#  STEP 2 — Abilita gestione IPv6 in ufw
# =============================================================================
echo "[2/8] Configurazione IPv6 in ufw..."
sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw
grep -q "^IPV6=yes" /etc/default/ufw || echo "IPV6=yes" >> /etc/default/ufw
echo "      OK — IPV6=yes impostato"

# =============================================================================
#  STEP 3 — Reset completo
# =============================================================================
echo "[3/8] Reset regole ufw esistenti..."
ufw --force reset > /dev/null 2>&1
echo "      OK — tabula rasa"

# =============================================================================
#  STEP 4 — Policy di default
# =============================================================================
echo "[4/8] Policy di default..."
ufw default deny incoming  > /dev/null
ufw default allow outgoing > /dev/null
ufw default deny routed    > /dev/null
echo "      OK — deny incoming, allow outgoing, deny routed"

# =============================================================================
#  STEP 5 — Regole per servizio
# =============================================================================
echo "[5/8] Applicazione regole per servizio..."

# LOOPBACK — Fondamentale per Pi-hole <-> dnsproxy
ufw allow in on lo comment "Consenti traffico interno (DNS loopback)" > /dev/null
echo "      [OK] Loopback lo (Interno)"

# DNS QUIC OUTGOING — Assicuriamoci che DoQ possa uscire
ufw allow out 853/udp comment "Allow Quad9 DoQ Outgoing" > /dev/null
echo "      [OK] DoQ Outgoing UDP 853"

# TAILSCALE — UDP 41641
ufw allow in on eno1 to any port 41641 proto udp \
    comment "Tailscale WireGuard handshake" > /dev/null
echo "      [OK] Tailscale UDP 41641"

# SSH — TCP 22
ufw allow in on eno1 from 192.168.1.0/24 to any port 22 proto tcp \
    comment "SSH da LAN" > /dev/null
ufw allow in on tailscale0 to any port 22 proto tcp \
    comment "SSH da Tailscale" > /dev/null
echo "      [OK] SSH TCP 22 (LAN + Tailscale)"

# PI-HOLE DNS — TCP+UDP 53
ufw allow in on eno1 from 192.168.1.0/24 to any port 53 proto udp \
    comment "Pi-hole DNS UDP da LAN" > /dev/null
ufw allow in on eno1 from 192.168.1.0/24 to any port 53 proto tcp \
    comment "Pi-hole DNS TCP da LAN" > /dev/null
ufw allow in on tailscale0 to any port 53 proto udp \
    comment "Pi-hole DNS UDP da Tailscale" > /dev/null
ufw allow in on tailscale0 to any port 53 proto tcp \
    comment "Pi-hole DNS TCP da Tailscale" > /dev/null
echo "      [OK] Pi-hole DNS TCP+UDP 53 (LAN + Tailscale)"

# PI-HOLE Web UI — TCP 80+443
ufw allow in on eno1 from 192.168.1.0/24 to any port 80 proto tcp \
    comment "Pi-hole Web UI HTTP da LAN" > /dev/null
ufw allow in on eno1 from 192.168.1.0/24 to any port 443 proto tcp \
    comment "Pi-hole Web UI HTTPS da LAN" > /dev/null
ufw allow in on tailscale0 to any port 80 proto tcp \
    comment "Pi-hole Web UI HTTP da Tailscale" > /dev/null
ufw allow in on tailscale0 to any port 443 proto tcp \
    comment "Pi-hole Web UI HTTPS da Tailscale" > /dev/null
echo "      [OK] Pi-hole Web UI TCP 80+443 (LAN + Tailscale)"

# SAMBA — TCP 445
ufw allow in on eno1 from 192.168.1.0/24 to any port 445 proto tcp \
    comment "Samba SMB3 da LAN" > /dev/null
ufw allow in on tailscale0 to any port 445 proto tcp \
    comment "Samba SMB3 da Tailscale" > /dev/null
echo "      [OK] Samba TCP 445 (LAN + Tailscale)"

# PLEX — TCP 32400
ufw allow in on eno1 from 192.168.1.0/24 to any port 32400 proto tcp \
    comment "Plex da LAN" > /dev/null
ufw allow in on tailscale0 to any port 32400 proto tcp \
    comment "Plex da Tailscale" > /dev/null
echo "      [OK] Plex TCP 32400 (LAN + Tailscale)"

# TRANSMISSION Web UI — TCP 9091
ufw allow in on eno1 from 192.168.1.0/24 to any port 9091 proto tcp \
    comment "Transmission Web UI da LAN" > /dev/null
ufw allow in on tailscale0 to any port 9091 proto tcp \
    comment "Transmission Web UI da Tailscale" > /dev/null
echo "      [OK] Transmission Web UI TCP 9091 (LAN + Tailscale)"

# TRANSMISSION BitTorrent — TCP+UDP 51413
ufw allow in on eno1 to any port 51413 proto tcp \
    comment "Transmission BitTorrent TCP IPv4" > /dev/null
ufw allow in on eno1 to any port 51413 proto udp \
    comment "Transmission BitTorrent UDP IPv4" > /dev/null
echo "      [OK] Transmission BitTorrent TCP+UDP 51413 (IPv4)"

# =============================================================================
#  STEP 6 — Attivazione
# =============================================================================
echo "[6/8] Attivazione ufw..."
ufw --force enable > /dev/null
echo "      OK — ufw attivo"

# =============================================================================
#  STEP 7 — Pulizia regole IPv6 ALLOW su eno1 + blocco IPv6 pubblico
# =============================================================================
echo "[7/8] Pulizia IPv6 ALLOW su eno1 e blocco IPv6 pubblico..."

while true; do
    num=$(ufw status numbered 2>/dev/null \
        | grep -P '\(v6\).*on eno1.*ALLOW IN' \
        | head -1 \
        | grep -oP '^\[\s*\K[0-9]+' || true)
    [[ -z "$num" ]] && break
    ufw --force delete "$num" > /dev/null 2>&1
done
echo "      [OK] Regole IPv6 ALLOW su eno1 rimosse"

ufw deny in on eno1 from 2000::/3 to any \
    comment "Blocco IPv6 globale in ingresso su eno1" > /dev/null
echo "      [OK] Blocco 2000::/3 aggiunto su eno1"

# =============================================================================
#  STEP 8 — Riepilogo finale
# =============================================================================
echo "[8/8] Verifica finale..."
echo ""
echo "=========================================="
echo "  REGOLE ATTIVE (ordinate)"
echo "=========================================="
ufw status numbered
echo ""
echo "=========================================="
echo "  VERIFICA RAPIDA"
echo "=========================================="
echo "  sudo journalctl -u dnsproxy -f"
echo "  drill -t txt proto.quad9.net @127.0.0.1"
echo ""
