# HP ProDesk 600 — Server Infrastructure & Backup Repository

Questo repository contiene la configurazione completa, ottimizzata e documentata del server casalingo **HP ProDesk 600**, adibito a:
1. **Infrastruttura DNS e Sicurezza LAN / Tailnet** (Pi-hole v6, AdGuard dnsproxy DoQ/DoH3, Tailscale Exit Node & Subnet Router, Sentinel Watchdog).
2. **Server Multimediale & File Sharing** (Samba SMB3 cifrato con estensioni Apple macOS, Plex Media Server, Transmission Daemon e script di smistamento automatico).

---

## 1. Specifiche Hardware & Rete

* **Hardware**: HP ProDesk 600 Mini PC
* **CPU**: Intel(R) Core(TM) i5-6500T (4 Core, 4 Thread @ 2.50GHz, turbo 3.10GHz)
* **RAM**: 16 GB DDR4 (14 GB liberi costanti)
* **Storage**: SSD NVMe/SATA interno + HDD multimediale esterno
* **OS**: Debian GNU/Linux 13 (Trixie) x86_64
* **Connessione WAN**: FTTH Iliadbox EPON 5 Gbit/s Down / 900 Mbit/s Up (Area Perugia, PG)
* **Topologia Elettrica**: Il server ProDesk e l'Iliadbox sono alimentati dalla **stessa presa elettrica**. In caso di interruzione di corrente, i servizi DNS attendono la sincronizzazione dell'albero ottico PON prima di avviare le verifiche di connettività (`OnBootSec=5min`).

---

## 2. Architettura Logica dei Servizi

### A. Catena DNS ad Altissima Resilienza (DoQ + DoH3)

```
[ Client LAN (192.168.1.0/24) ] ──┐
[ Nodi Tailscale (100.64.0.0/10) ] ─┴─> [ Pi-hole v6 FTL (:53) ]
                                            ├── Blocco Ads & Tracker (gravity.db)
                                            ├── Dominio locale *.home -> 192.168.1.254 (Iliadbox)
                                            ├── MagicDNS *.ts.net & PTR -> 100.100.100.100
                                            └── Upstream -> 127.0.0.1:5353
                                                    │
                                                    ▼
                                     [ AdGuard dnsproxy (:5353) ]
                                     • upstream-mode: parallel (zero impuntamenti)
                                     • timeout: 3s
                                     • cache-optimistic: true (16 MB in RAM)
                                     • DNSSEC: true (bit DO attivo)
                                        ├── DoQ (UDP 853): Quad9 (9.9.9.9 / 149.112.112.9)
                                        └── DoH3 (HTTPS 443): Cloudflare (1.1.1.2 / 1.0.0.2)
```

* **Latenze Tipiche da Perugia**:
  * Cache locale: `0 ms`
  * Query ricorsiva verso Quad9 (DoQ): `13–15 ms`
  * Query ricorsiva verso Cloudflare (DoH): `14–16 ms`
* **Sentinel Watchdog (`dns-sentinel.sh`)**:
  Demone orario su systemd che esegue auto-healing, test DNSSEC, cattura pacchetti UDP/853 e notifica aggiornamenti software (GitHub API per `dnsproxy`, `pihole -v`, `tailscale`) su Telegram.

---

### B. Stack Multimediale & Archiviazione

```
               [ Download Torrent ]
                        │
                        ▼
            [ Transmission Daemon ]
                        │  (download completato)
                        ▼  chiama torrent-done.sh
          [ sort-plex-media.py ] 
          • Smistamento Film / Serie TV
          • Rinominazione automatica
                        │
                        ▼
            [ Plex Media Server ] <──> Streaming LAN / Remoto
                        │
            [ Samba SMB3 Cifrato ] <──> Client Mac / PC / iOS
```

* **Samba (`/etc/samba/smb.conf`)**:
  * Protocolli forzati: **SMB2 / SMB3** (SMB1 disabilitato, NetBIOS disabilitato).
  * Cifratura e firma dei pacchetti obbligatoria (`smb encrypt = required`, `server signing = mandatory`).
  * Estensioni macOS Apple (`vfs objects = catia fruit streams_xattr`) per navigazione veloce e zero file `.DS_Store` orfani.
  * Accesso ristretto rigorosamente a: subnet locale `192.168.1.0/24`, Tailscale `100.64.0.0/10` e ULA IPv6 `fd00::/64`.
* **Transmission & Plex Automation**:
  * Web GUI e daemon integrato.
  * Al termine di ogni download viene invocato `torrent-done.sh` che lancia `sort-plex-media.py` per catalogare e pulire i media prima che Plex esegua il refresh della libreria.

---

## 3. Struttura del Repository

```text
prodesk600/
├── README.md                          # Questo documento
├── sync.sh                            # Script di sincronizzazione automatica bidirezionale
├── .gitignore                         # Esclusione log, file temporanei e segreti
│
├── debian-system/
│   ├── sysctl.d/
│   │   └── 99-prodesk-tuning.conf     # Buffer UDP (16MB) e IP forwarding (IPv4/IPv6)
│   ├── network/
│   │   └── dhcpcd.conf                # Configurazione client di rete interfaccia eno1
│   ├── systemd/
│   │   ├── dnsproxy.service           # Unità systemd per dnsproxy (DoQ/DoH3)
│   │   ├── dns-check.service          # Unità systemd per esecuzione DNS Sentinel
│   │   └── dns-check.timer            # Timer orario con OnBootSec=5min
│   └── ufw/
│       ├── ufw-setup.sh               # Script per ripristinare il set di regole UFW
│       └── ufw-status.txt             # Dump dettagliato delle regole firewall attive
│
├── dns-network/
│   ├── dnsproxy/
│   │   └── config.yaml                # File di configurazione AdGuard dnsproxy
│   ├── pihole/
│   │   └── pihole.toml                # Configurazione nativa Pi-hole v6 (sanitizzata)
│   ├── tailscale/
│   │   └── tailscale-setup.md         # Istruzioni Subnet Router, Exit Node e GRO offload
│   └── scripts/
│       ├── verify.sh                  # Suite di validazione a 8 controlli della catena DNS
│       ├── dns-sentinel.sh            # Watchdog, monitoraggio versioni e Telegram bot
│       ├── dns-report-telegram.sh     # Notificatore leggero di anomalie
│       └── update-dnsproxy.sh         # Procedura per scaricare e aggiornare dnsproxy
│
└── multimedia/
    ├── samba/
    │   └── smb.conf                   # Configurazione sicura Samba SMB3 con moduli Apple
    ├── transmission/
    │   ├── settings.json              # Configurazione transmission-daemon (sanitizzata)
    │   └── torrent-done.sh            # Hook post-completamento torrent
    ├── plex/
    │   └── plex-media-watcher.py      # Monitor del filesystem per notifiche libreria
    └── scripts/
        ├── sort-plex-media.py         # Parser e catalogatore media Plex
        ├── optimize-mkv-audio.py      # Ottimizzazione tracce audio contenitori MKV
        └── scaricamp3.sh              # Script rapido download e conversione audio
```

---

## 4. Come Mantenere Aggiornato il Repository

È presente lo script [`sync.sh`](./sync.sh) nella root del progetto. Eseguendolo:

```bash
cd /home/ubermensch/prodesk600
./sync.sh "Descrizione delle modifiche apportate"
```

Lo script:
1. Copia automaticamente tutte le configurazioni attive dal sistema (`/etc/`, `/usr/local/bin/`, systemd).
2. Sanitizza password, token e chiavi private per evitare esposizioni accidentali.
3. Esegue `git add`, `git commit` e il `git push` su GitHub.

---

## 5. Sicurezza e Sanitizzazione dei Dati

Tutti i file presenti in questo repository sono stati preventivamente depurati da dati sensibili:
* `BOT_TOKEN` e `CHAT_ID` di Telegram sostituiti con variabili di ambiente.
* Password e token di hash di Pi-hole e Transmission sostituiti con marcatori `<REDACTED>`.
* Chiavi private e credenziali OAuth escluse tramite `.gitignore`.
