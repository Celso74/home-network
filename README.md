# Home Network — Shanghai, China

Transparent GFW-bypass network. Every device in the house routes through the correct path without any manual proxy configuration. Built over multiple weeks of engineering sessions.

---

## Physical Topology

```
China Telecom ONT (192.168.71.1, DHCP)
        │
        │ coax/fiber
        ▼
┌─────────────────────────────────────┐
│      Intel N100 Mini PC             │
│      iStoreOS 24.10.5 (OpenWrt)    │
│      Transparent L2 Bridge          │
│      eth0 ──► br-wan ◄── eth1      │  ← NO IP on br-wan — EVER
│      eth3 = Management 192.168.100.1│
└────────────────┬────────────────────┘
                 │ eth1 (CT modem traffic passes through invisibly)
                 ▼
        MikroTik RB750Gr3 (hEX)
        192.168.111.1 — L3 router, DHCP server, NAT
                 │
                 │ ether2 (LAN bridge)
                 ▼
        Ruijie RG-ES25GC (L2 switch, mgmt 192.168.13.1)
                 │
        ┌────────┴──────────┐
        │                   │
        N100 eth2            Ruijie EG110G-P (AP Controller + PoE switch)
        (192.168.110.45)     192.168.110.1
                             │
                    ┌────────┼────────┬───────────┐
                    │        │        │           │
                   AP       AP       AP          AP
                  Ayi   Living Rm  Master Rm    HB
                  (EAP102E × 4, cloud-managed mesh)
```

> **Why N100 is inline:** N100 acts as a transparent L2 bridge between the CT modem and MikroTik. It intercepts DNS queries silently via nftables on the FORWARD chain, running the GFW-bypass chain without any IP address on the bridge. CT modem sees MikroTik directly — zero double NAT.

---

## Device Inventory

### Intel N100 Mini PC

| Field | Value |
|-------|-------|
| OS | iStoreOS 24.10.5 (OpenWrt-based), kernel 6.6.119 |
| Role | Transparent L2 bridge + GFW bypass appliance |
| Management IP | 192.168.100.1/24 (eth3 — permanent rescue port) |
| SSH | `ssh root@192.168.100.1` |
| LuCI | http://192.168.100.1 |
| Disk | 476.94 GiB NVMe SSD |

**Network interfaces:**

| Interface | IP | Role |
|-----------|----|------|
| eth0 | NONE | br-wan member — CT modem side |
| eth1 | NONE | br-wan member — MikroTik WAN side |
| eth2 | 192.168.110.45 (DHCP from Ruijie) | N100 own internet egress |
| eth3 | 192.168.100.1/24 (STATIC — never changes) | Management / rescue port |
| br-wan | **NO IP — NEVER ADD ONE** | Transparent bridge eth0+eth1 |
| br-lan | 192.168.100.1/24 | Management bridge |

**Rescue IPs on br-lan (all survive reboot via UCI aliases):**
- 192.168.100.254/24
- 192.168.100.253/24
- 192.168.100.252/24
- 192.168.100.251/24

**Software stack:**

| Software | Port | Role |
|----------|------|------|
| OpenClash (Mihomo Meta v1.19.19) | TUN / 9090 (API) | GFW bypass, fake-IP routing |
| PassWall (xray-core) | 1080 (SOCKS) | GFW bypass (legacy/fallback) |
| dnsmasq | 53 | DNS intercept, forward to AGH |
| AdGuard Home | 5353 (localhost only) | Ad block, upstream to chinadns-ng |
| chinadns-ng | 15353 | Split DNS: CN direct, GFW via proxy |
| Ralph watchdog | — | Auto-reverts bad configs |
| Dropbear SSH | 22 | Remote access |

---

### MikroTik RB750Gr3 (hEX)

| Field | Value |
|-------|-------|
| OS | RouterOS 7.18.2 |
| Role | Primary WAN router, DHCP server, NAT, firewall |
| LAN IP | 192.168.111.1/24 |
| WAN | ether1 — DHCP from CT modem (gets 192.168.71.15/24) |
| LAN ports | ether2–ether5 (bridge) |
| DHCP pool | `lan-pool-111`: 192.168.111.5–192.168.111.250 |
| DNS | 223.5.5.5, 223.6.6.6 (clients never actually reach these — N100 intercepts) |
| SSH | `ssh admin@192.168.111.1` (locally) or port 2231 via VPS |

**Critical DHCP option 121 (fake-IP route pushed to clients):**
```
Routes 198.18.0.0/15 → N100 LAN IP
Without this, OpenClash fake-IP breaks for routed clients.
```

**Config backups on Google Drive:** `LD:N100 Super Device - Saves and Images/MIKROTIK ROUTER/`
- `M1-BASELINE-SAFE-ACCESS.rsc` — clean baseline
- `M4-PHYSICAL-INTEGRATION-PREP.rsc` — ready for N100 inline
- `M4.6-EAL-HARDENED.rsc` — hardened (current)

---

### Ruijie RG-ES25GC (Core Switch)

| Field | Value |
|-------|-------|
| Role | L2 distribution switch — no routing |
| Management IP | 192.168.13.1 (changed from factory 10.44.77.254) |
| Ports | 25-port Gigabit managed |

**Port map:**

| Port | Connected to |
|------|-------------|
| P1 | MikroTik LAN (ether2) |
| P2 | Laptop |
| P3 | Ruijie EG110G-P |
| P4 | N100 eth2/eth3 |
| P5 | Spare |

> Factory reset IP is `10.44.77.254`, not `192.168.111.1`. Required factory reset once to restore local web management from Ruijie cloud.

---

### Ruijie EG110G-P (AP Controller + PoE Switch)

| Field | Value |
|-------|-------|
| Role | AP controller + PoE distribution for mesh APs |
| IP | 192.168.110.1/24 |
| DHCP | Hands out 192.168.110.x to clients |
| Management | Ruijie Cloud app (Chinese cloud management) |

---

### Wi-Fi APs (Ruijie EAP102E × 4)

Ceiling-mounted, cloud-managed mesh. All are pure L2 bridges — no routing, no NAT, no DHCP. PoE-powered from EG110G-P.

| AP Name | Location |
|---------|----------|
| Ayi | Ayi's room |
| Living Room | Living room |
| Master Bedroom | Master bedroom |
| HB | HB's room |

---

### VPS (Hetzner, Germany)

| Field | Value |
|-------|-------|
| Hostname | core-vps-1 |
| IP | 5.75.182.153 |
| User | celso |
| Role | SSH tunnel relay, compute, Claude Code |
| Disk | 75 GB |
| Rclone mount | GDrive `LD:` → `/mnt/gdrive` or `/mnt/LivingDocument_AI` |
| N100 backups | `~/n100_backups/` |

**Docker services on VPS:** n8n, doorway, litellm, openwebui_clean, postgres_n8n, uptime-kuma, caddy

**Required sshd_config setting:** `GatewayPorts yes` (reverse tunnel binds on 0.0.0.0)

---

### Laptop (Windows)

| Field | Value |
|-------|-------|
| Hostname | Celso-2 / celso-laptop-shanghai |
| User | C:\Users\Celso |
| LAN IP | 192.168.110.16 |
| SSH key | `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOc2G9yjmLAZSPjA4GXzFU9nstv3n2LNZbGi0Z1IWJVw celso-laptop-shanghai` |

---

### Devices

| Device | IP | MAC | Notes |
|--------|----|-----|-------|
| S22 Ultra (phone) | 192.168.111.194 | CE:50:7F:01:1B:AA | Static DHCP lease |
| Nvidia Shield TV 4K | 192.168.111.183 | 00:04:4B:83:98:AF | SACRED — never disrupt |
| PS5 | 192.168.111.161 | — | Gaming |
| Sonos Speaker | 192.168.110.7 | — | House LAN |
| Laptop | 192.168.111.181 | 30:05:05:93:1B:47 | Torrent → DIRECT |

---

## Subnet Map

| Subnet | Gateway | DHCP Server | Used For |
|--------|---------|-------------|----------|
| 192.168.71.0/24 | 192.168.71.1 | CT Modem | WAN side (modem → MikroTik) |
| 192.168.100.0/24 | 192.168.100.1 | None (static) | N100 management only |
| 192.168.110.0/24 | 192.168.110.1 | Ruijie EG110G-P | AP-side devices |
| 192.168.111.0/24 | 192.168.111.1 | MikroTik | Main LAN — all clients |
| 192.168.13.0/24 | 192.168.13.1 | — | Ruijie switch management |
| 198.18.0.0/15 | — | — | OpenClash fake-IP range |

---

## SSH Tunnel Map (all via VPS 5.75.182.153)

| VPS Port | Forwards To | Device |
|----------|-------------|--------|
| 2223 | 192.168.100.1:22 | N100 (Claude's tunnel) |
| 2224 | 192.168.100.1:22 | N100 (Codex's tunnel) |
| 2226 | 127.0.0.1:22 | Laptop |
| 2231 | 192.168.111.1:22 | MikroTik |

**Connect from VPS:**
```bash
ssh -p 2223 root@localhost      # N100
ssh -p 2226 celso@localhost     # Laptop
ssh -p 2231 admin@localhost     # MikroTik
```

**Tunnel keepalive scripts (Windows PowerShell — run on laptop startup):**

```powershell
# C:\Users\Celso\tunnel_n100.ps1
while ($true) {
    ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=3 `
        -R 2223:192.168.100.1:22 `
        -R 2224:192.168.100.1:22 `
        -R 2226:127.0.0.1:22 `
        celso@5.75.182.153
    Start-Sleep 5
}

# C:\Users\Celso\tunnel_mikrotik.ps1
while ($true) {
    ssh -R 2231:192.168.111.1:22 celso@core-vps-1
    Start-Sleep 5
}
```

---

## DNS Architecture — "God-Level DNS"

Clients believe they're using `223.5.5.5`. N100 silently hijacks all port 53 traffic via nftables on the FORWARD chain. If N100 dies, clients fall back to `223.5.5.5` — China DNS still works, GFW bypass just stops.

```
All LAN clients
  └─► query 223.5.5.5:53
        │
        │ [HIJACKED by N100 nftables FORWARD chain]
        ▼
dnsmasq :53 on N100
  noresolv=1, server=127.0.0.1#5353
        │
        ▼
AdGuard Home :5353 (127.0.0.1 only)
  upstream: [::1]:15353
        │
        ▼
chinadns-ng :15353
  ├─► China domains    → 223.5.5.5 / 119.29.29.29 (direct)
  └─► GFW/Global       → TCP://1.1.1.1#53 via proxy
```

| Config File | Key Setting |
|-------------|-------------|
| `/etc/config/dhcp` | `noresolv='1'`, `server='127.0.0.1#5353'` |
| `/opt/AdGuardHome/AdGuardHome.yaml` | bind: `127.0.0.1:5353`, upstream: `[::1]:15353` |
| `/tmp/etc/passwall/acl/default/chinadns_ng.conf` | china-dns: `223.5.5.5`, trust-dns: `tcp://1.1.1.1#53` |

---

## GFW Bypass Proxy

### OpenClash (current)
- Core: Mihomo Meta v1.19.19
- Mode: fake-IP + TUN
- API: `http://127.0.0.1:9090`, Bearer token `lBJEqlqp`
- GeoSite.dat: updated February 2026 (Loyalsoldier v2ray-rules-dat)

### Proxy Nodes

| Node | Protocol | Server | Use |
|------|----------|--------|-----|
| JP1-Reality | VLESS+Reality (TCP) | 147.79.20.20:30187 | Stability-critical (Shield TV, AI services) |
| JP-TUIC | TUIC v5 (QUIC/UDP) | 147.79.20.20 | Fast/phones (AUTO-FAST) |
| JP-Hysteria2 | Hysteria2 (QUIC/UDP) | 147.79.20.20 | Dead — passive fallback only |

### Per-Device Routing

| Device | IP | Group | Node |
|--------|----|-------|------|
| Shield TV 4K | 192.168.111.183 | SHIELD-STABLE | JP1-Reality (pinned — NEVER changes) |
| All phones | 192.168.111.155–157, .194 | PHONE-FAST | JP-TUIC |
| Laptop | 192.168.111.181 | Mixed | Explicit rules; torrent → DIRECT |
| Everything else | * | PROXY → AUTO-FAST | JP-TUIC |

---

## Double NAT Elimination

N100's `br-wan` has NO IP. CT modem sees MikroTik's MAC directly. MikroTik handles the only NAT in the chain.

**The critical rule:** `br-wan` must always be `proto=none` with no IP. Adding any IP kills SSH tunnels within ~30 seconds.

---

## Ralph Watchdog

Custom safety daemon on N100. Before every config change, Ralph is armed. If SSH or LuCI goes down within the timeout window, Ralph automatically restores the last backup and reboots.

```bash
ralph arm 120        # arm — auto-revert if no confirm within 120s
ralph confirm        # signal "everything OK" — disarm
ralph status         # show watchdog state
ralph restore        # force-restore last backup NOW
```

---

## Monitoring

JP1-Reality degradation monitor: cron `*/5 * * * *` runs `/home/celso/axiom/bin/jp1_monitor.sh`.
Sends push notification via ntfy.sh topic `axiom-jp1-celso` if JP1 latency > 800ms for 3 consecutive checks.
Install ntfy app and subscribe to `axiom-jp1-celso`.

---

## Quick Health Check

```bash
# Tunnel alive?
ssh -p 2226 root@127.0.0.1 "echo OK"

# SHIELD-STABLE on JP1-Reality? (must always be yes)
curl -s http://127.0.0.1:9090/proxies/SHIELD-STABLE \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'

# AUTO-FAST on JP-TUIC?
curl -s http://127.0.0.1:9090/proxies/AUTO-FAST \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'

# JP-TUIC latency
curl -s 'http://127.0.0.1:9090/proxies/JP-TUIC' \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"delay":[0-9]*' | tail -1

# br-wan must show NO IP
ssh -p 2223 root@localhost "ip addr show br-wan"
```

**Expected healthy state:**
- Tunnel: `OK`
- SHIELD-STABLE: `"now":"JP1-Reality"`
- AUTO-FAST: `"now":"JP-TUIC"`
- JP-TUIC delay: < 150ms
- JP1-Reality delay: < 500ms

---

## Key Config File Locations (N100)

| Path | Contents |
|------|----------|
| `/etc/config/network` | UCI network config (bridges, interfaces, IPs) |
| `/etc/config/dhcp` | dnsmasq + DNS config |
| `/etc/config/firewall` | nftables firewall rules |
| `/etc/config/passwall` | PassWall proxy config |
| `/opt/AdGuardHome/AdGuardHome.yaml` | Full AGH YAML |
| `/etc/openclash/config/config.yaml` | OpenClash Mihomo config |
| `/root/MILESTONES/` | Named config checkpoints |
| `/usr/bin/ralph` | Safety watchdog script |
| `/root/ai_handoff.txt` | Multi-session collaboration log |

---

## The 8 Sacred Rules

1. **NEVER add IP to br-wan** — kills tunnels in ~30s
2. **NEVER touch eth3** — permanent rescue lifeline
3. **NEVER disrupt Nvidia Shield** — SACRED
4. **ALWAYS arm Ralph before risky changes** — `ralph arm 120`
5. **ALWAYS use VPS tunnels for remote access** — never expose N100 directly
6. **Management subnet 192.168.100.0/24 is ALWAYS bypassed from proxy** — keeps SSH working
7. **CT modem subnet 192.168.71.0/24 must never appear on N100 br-wan** — breaks bridge
8. **Rescue IPs (.254/.253/.252/.251) always exist on br-lan** — multiple fallback paths to N100

---

## Further Documentation

- [Replication Guide](./docs/REPLICATION_GUIDE.md) — complete from-scratch setup instructions, every device, every command
- [Standard Operating Procedures](./docs/NETWORK_SOP.md) — day-to-day operations, change management, troubleshooting
- [Network Audit 2026-02-24](./docs/NETWORK_AUDIT_2026-02-24.md) — full config snapshot, proxy rules, DNS architecture
- [OpenClash config example](./config.yaml.example) — redacted live config with all rules
