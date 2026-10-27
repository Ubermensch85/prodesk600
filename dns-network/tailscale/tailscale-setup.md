# Configurazione Tailscale — HP ProDesk 600

## 1. Ruolo del Nodo nel Tailnet
* **Hostname**: `prodesk600`
* **IP CGNAT**: `100.116.94.86` / `fd7a:115c:a1e0::c332:5e56`
* **Funzionalità**:
  * **Exit Node**: Pubblicazione di `0.0.0.0/0` e `::/0` per instradare tutto il traffico dei dispositivi mobili (es. iPhone) attraverso la FTTH di casa.
  * **Subnet Router**: Pubblicazione di `192.168.1.0/24` per accedere a tutta la LAN locale senza configurare WireGuard su ogni device.
  * **DNS Server del Tailnet**: I dispositivi collegati a Tailscale usano questo host (`100.116.94.86`) come resolver DNS con blocco annunci Pi-hole attivo ovunque.

## 2. Parametri di Avvio & Preferenze Attive
```bash
sudo tailscale up \
  --advertise-routes=0.0.0.0/0,::/0,192.168.1.0/24 \
  --accept-dns=false \
  --auto-update
```

> [!IMPORTANT]
> `--accept-dns=false` (`CorpDNS: false`) è fondamentale sull'host server per evitare che Tailscale sovrascriva `/etc/resolv.conf` con `100.100.100.100`, creando un loop circolare con Pi-hole locale.

## 3. Ottimizzazioni Kernel WireGuard su interfaccia fisica (`eno1`)
Per massimizzare il throughput e ridurre il carico CPU con carichi WireGuard pesanti:
```bash
sudo ethtool -K eno1 rx-udp-gro-forwarding on rx-gro-list off
```

## 4. Integrazione con Pi-hole v6
In `/etc/pihole/pihole.toml`:
* `listeningMode = "ALL"` (permette risposte su interfaccia `tailscale0`)
* Inoltro MagicDNS: `server=/ts.net/100.100.100.100`
* Reverse Lookup PTR: zone `100.64.0.0/10` e `fd7a:115c:a1e0::/48` inoltrate a `100.100.100.100`.
