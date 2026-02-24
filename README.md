# Home Network — Shanghai, China

Transparent GFW-bypass network. Every device in the house gets the right routing path with zero manual proxy configuration. Built over multiple weeks of engineering sessions.

---

## Physical Topology

```
China Telecom ONT (fiber)
        │ DHCP → gives WAN IP to MikroTik
        ▼
MikroTik RB750Gr3 (hEX)
  192.168.111.1
  L3 router · DHCP server · NAT · firewall
        │ ether2 (LAN bridge)
        ▼
Ruijie ES205GC (5-port switch)
  192.168.13.1 (mgmt)
  Pure L2 — no routing
        │
   ┌────┴────────────────┐
   │                     │
   ▼                     ▼
N100 Mini PC        Ruijie ES209GC-P (PoE switch)
192.168.111.2        L2 · PoE · Ruijie Cloud managed
GFW bypass /             │
DNS engine               ├── EAP102E "Ayi"
                         ├── EAP102E "Living Room"
                         ├── EAP102E "Master Bedroom"
                         └── EAP102E "HB"
```

---

## Physical Cabling

| # | From | Port | To | Port | Cable |
|---|------|------|----|------|-------|
| 1 | CT Modem | LAN out | MikroTik | ether1 (WAN) | CAT5e/6 |
| 2 | MikroTik | ether2 | ES205GC | P1 | CAT5e/6 |
| 3 | ES205GC | P2 | Laptop | NIC | CAT5e/6 |
| 4 | ES205GC | P3 | ES209GC-P | uplink | CAT5e/6 |
| 5 | ES205GC | P4 | N100 | eth2 | CAT5e/6 |
| 6 | N100 | eth3 | Laptop | NIC | CAT5e/6 — rescue only, plug in when needed |
| 7 | ES209GC-P | PoE port | EAP102E "Ayi" | PoE in | CAT5e/6 |
| 8 | ES209GC-P | PoE port | EAP102E "Living Room" | PoE in | CAT5e/6 |
| 9 | ES209GC-P | PoE port | EAP102E "Master Bedroom" | PoE in | CAT5e/6 |
| 10 | ES209GC-P | PoE port | EAP102E "HB" | PoE in | CAT5e/6 |

> **N100 eth0 and eth1** are physically unconnected in the current deployment. They are bridged into `br-wan` (no IP) and reserved for a future inline transparent-proxy configuration.

---

## Device Inventory

### MikroTik RB750Gr3 (hEX)

| Field | Value |
|-------|-------|
| OS | RouterOS 7.18.2 |
| Role | Edge router, DHCP server, NAT, firewall |
| LAN IP | **192.168.111.1**/24 |
| WAN port | ether1 — DHCP from CT modem (gets 192.168.71.15/24, GW 192.168.71.1) |
| LAN ports | ether2–ether5 (bridge) |
| DHCP pool | 192.168.111.5–192.168.111.250 |
| DNS given to clients | 223.5.5.5, 223.6.6.6 (N100 intercepts before they're used) |
| WebFig UI | http://192.168.111.1 |
| SSH (LAN) | `ssh admin@192.168.111.1` |
| SSH (remote) | `ssh -p 2231 admin@localhost` (from VPS) |

**Static DHCP leases:**

| Device | IP | MAC |
|--------|----|-----|
| S22 Ultra (phone) | 192.168.111.194 | CE:50:7F:01:1B:AA |
| Nvidia Shield TV 4K | 192.168.111.183 | 00:04:4B:83:98:AF |
| Laptop | 192.168.111.181 | 30:05:05:93:1B:47 |
| PS5 | 192.168.111.161 | — |

**Critical static route (required for OpenClash fake-IP):**
```routeros
/ip route add dst-address=198.18.0.0/15 gateway=192.168.111.2
```
Without this, GFW bypass breaks for all routed clients.

**Config backups:** Google Drive → `G:\My Drive\N100 Super Device - Saves and Images\MIKROTIK ROUTER\`
- `M1-BASELINE-SAFE-ACCESS.rsc` — clean baseline with SSH access
- `M4-PHYSICAL-INTEGRATION-PREP.rsc` — integration-ready
- `M4.6-EAL-HARDENED.rsc` — current hardened config

---

### Ruijie ES205GC — Core Switch

| Field | Value |
|-------|-------|
| Model | Ruijie ES205GC (5-port Gigabit) |
| Role | Pure L2 distribution — no routing, no DHCP |
| Management IP | 192.168.13.1 (changed from factory default 10.44.77.254) |
| Management | Local web UI at http://192.168.13.1 or Ruijie Cloud app (锐捷睿易) |

**Factory reset:** Hold reset button 10 seconds → IP resets to 10.44.77.254. Connect laptop at 10.44.77.10/24 to recover.

---

### Intel N100 Mini PC — GFW Bypass Engine

| Field | Value |
|-------|-------|
| OS | iStoreOS 24.10.5 (OpenWrt-based), kernel 6.6.119 |
| Role | GFW bypass via OpenClash TUN + fake-IP. DNS intelligence layer. |
| LAN IP | **192.168.111.2**/24 (on br-lan via eth2 → ES205GC) |
| Management IP | 192.168.100.1/24 on eth3 (rescue — cable only when needed) |
| SSH (remote) | `ssh -p 2223 root@localhost` (from VPS) |
| LuCI | http://192.168.100.1 (requires eth3 rescue cable) |
| Disk | 476.94 GiB NVMe SSD |

**Live interface state:**

| Interface | State | IP | Notes |
|-----------|-------|----|-------|
| eth0 | DOWN (no cable) | none | Reserved — future inline bridge |
| eth1 | DOWN (no cable) | none | Reserved — future inline bridge |
| eth2 | **UP** | — | br-lan member → ES205GC |
| eth3 | DOWN (no cable) | 192.168.100.1/24 | Rescue port — plug in to manage |
| br-lan | **UP** | 192.168.111.2/24 | Main LAN (via eth2) |
| br-wan | DOWN | NO IP EVER | Transparent bridge (eth0+eth1, currently unused) |
| singtun0 | **UP** | 172.19.0.1/30 | OpenClash TUN interface |

**Rescue alias IPs (always on br-lan, survive every reboot):**
192.168.100.254 / .253 / .252 / .251

**Software stack:**

| Software | Bind | Role |
|----------|------|------|
| OpenClash (Mihomo Meta v1.19.19) | TUN + API :9090 | GFW bypass, fake-IP |
| dnsmasq | :53 | DNS intercept, forward to AGH |
| AdGuard Home | 127.0.0.1:5353 | Ad-block, upstream → chinadns-ng |
| chinadns-ng | 127.0.0.1:15353 | Split DNS: CN direct, GFW via proxy |
| Ralph watchdog | — | Auto-reverts bad configs |
| Dropbear | :22 | SSH |

**Full disk image backup:**
- `BASELINE-01-BRIDGE-STABLE.img.gz` on Google Drive `G:\My Drive\N100 Super Device - Saves and Images\`
- SHA256: `15d44acca59936032c213b095f53670d12fd580a969fabe320596a145602a4f0`
- VPS copy: `~/n100_backups/` on core-vps-1
- Restore: `gunzip -c BASELINE-01-BRIDGE-STABLE.img.gz | dd of=/dev/nvme0n1 bs=4M status=progress`

---

### Ruijie ES209GC-P — PoE Switch

| Field | Value |
|-------|-------|
| Model | Ruijie ES209GC-P (9-port Gigabit PoE) |
| Role | PoE power delivery + L2 distribution to all APs |
| Management | Ruijie Cloud app (锐捷睿易) |
| Connected to | ES205GC uplink port |

---

### Wi-Fi APs — Ruijie EAP102E × 4

Ceiling-mounted, PoE-powered from ES209GC-P. Mesh mode. Pure L2 bridge — no routing, no DHCP, no NAT.

| AP Name | Location | IP | MAC prefix |
|---------|----------|----|------------|
| Ayi | Ayi's room | 192.168.111.x (DHCP) | c0:a4:76 |
| Living Room | Living room | 192.168.111.x (DHCP) | c0:a4:76 |
| Master Bedroom | Master bedroom | 192.168.111.x (DHCP) | c0:a4:76 |
| HB | HB's room | 192.168.111.x (DHCP) | c0:a4:76 |

**All AP config (SSID, password, channels, mesh, power) is managed exclusively in the Ruijie Cloud app (锐捷睿易 / Ruijie Easy).** Do not use local web management.

**Re-adding an AP:**
1. Unplug PoE cable, replug
2. AP broadcasts setup SSID for ~2 minutes
3. Ruijie app → Add Device → follow on-screen pairing
4. AP re-joins mesh automatically

---

### VPS — Hetzner Germany

| Field | Value |
|-------|-------|
| Hostname | core-vps-1 |
| IP | 5.75.182.153 |
| User | celso |
| Role | SSH tunnel relay, Claude Code, n8n automation |
| GDrive mount | `LD:` → `/mnt/gdrive` (rclone) |
| N100 backups | `~/n100_backups/` |

**Required in `/etc/ssh/sshd_config`:** `GatewayPorts yes`

Docker containers: n8n, doorway, litellm, openwebui_clean, postgres_n8n, uptime-kuma, caddy

---

### Laptop — Windows

| Field | Value |
|-------|-------|
| Hostname | Celso-2 / celso-laptop-shanghai |
| LAN IP | 192.168.111.181 (static DHCP) |
| MAC | 30:05:05:93:1B:47 |
| Role | Tunnel host — keeps all reverse SSH tunnels alive |
| Plex | 192.168.110.16:32400 |

---

### Other Devices

| Device | IP | MAC | Notes |
|--------|----|-----|-------|
| S22 Ultra | 192.168.111.194 | CE:50:7F:01:1B:AA | Static DHCP |
| Nvidia Shield TV 4K | 192.168.111.183 | 00:04:4B:83:98:AF | **SACRED** — never disrupt |
| PS5 | 192.168.111.161 | — | Gaming |
| Sonos | 192.168.110.7 | — | Speaker |

---

## Subnet Map

| Subnet | Gateway | DHCP Server | Purpose |
|--------|---------|-------------|---------|
| 192.168.71.0/24 | 192.168.71.1 | CT Modem | WAN — modem to MikroTik |
| 192.168.111.0/24 | 192.168.111.1 | MikroTik | Main LAN — all clients |
| 192.168.100.0/24 | 192.168.100.1 | None (static) | N100 rescue/management |
| 192.168.13.0/24 | 192.168.13.1 | — | ES205GC switch management |
| 198.18.0.0/15 | — | — | OpenClash fake-IP range |

---

## SSH Tunnel Map (all reverse tunnels via VPS 5.75.182.153)

| VPS Port | Destination | Device | Opened by |
|----------|-------------|--------|-----------|
| 2223 | 192.168.100.1:22 | N100 | Laptop tunnel script |
| 2224 | 192.168.100.1:22 | N100 (Codex) | Laptop tunnel script |
| 2226 | 127.0.0.1:22 | Laptop | Laptop tunnel script |
| 2231 | 192.168.111.1:22 | MikroTik | Laptop tunnel script |

**Connect from VPS:**
```bash
ssh -p 2223 root@localhost      # N100
ssh -p 2226 celso@localhost     # Laptop
ssh -p 2231 admin@localhost     # MikroTik
```

**PowerShell scripts on laptop (run at startup via Task Scheduler):**
```powershell
# C:\Users\Celso\tunnel_main.ps1
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

## DNS Architecture — Layered "God-Level DNS"

MikroTik hands all clients **itself** as DNS (`192.168.111.1`). MikroTik then forwards all DNS queries upstream to N100. N100 is the DNS intelligence core — it processes every query through the GFW-bypass chain and returns the result back to MikroTik, which returns it to the client.

**If MikroTik has a backup DNS set (e.g. 223.5.5.5), DNS leaks directly to AliDNS, bypassing N100 entirely. This was the primary historical failure mode. MikroTik's upstream DNS must be N100 only.**

```
Client queries DNS → 192.168.111.1 (MikroTik)
        │
        │  MikroTik forwards DNS upstream → N100 IP
        ▼
dnsmasq :53 on N100
  noresolv=1, server=127.0.0.1#5353
        │
        ▼
AdGuard Home 127.0.0.1:5353
  upstream: [::1]:15353
        │
        ▼
chinadns-ng 127.0.0.1:15353
  ├─► CN domains  → 223.5.5.5 (direct)
  └─► GFW/Global  → 1.1.1.1 via proxy → fake-IP returned
        │
        ▼
N100 returns result → MikroTik → Client
```

---

## Traffic Flow (e.g. YouTube from phone)

```
Phone → AP (EAP102E mesh)
     → ES209GC-P
     → ES205GC
     → MikroTik (default gateway)
     ↓ DNS query
     → N100 (MikroTik forwards DNS)
     ← N100 returns fake-IP 198.18.x.x
     ↓ traffic to fake-IP
     → MikroTik routes via static route → N100
     → N100 OpenClash TUN → JP1-Reality / JP-TUIC
     → Response back via MikroTik → Client
```

---

## Design Philosophy

**MikroTik = stability, fail-open. N100 = intelligence.**

This setup was chosen deliberately:
- If OpenClash crashes or N100 reboots, MikroTik keeps routing normally — internet stays up, GFW bypass pauses temporarily
- MikroTik is rock solid; N100 can be updated, broken, rebooted without losing connectivity
- N100 is NOT the default gateway — it's a policy engine that MikroTik defers to for DNS and fake-IP routing

---

## GFW Bypass

### Proxy Nodes (JP VPS 147.79.20.20 — Henry's, ~50 RMB/month, 900 GB/month)

| Node | Protocol | Port | Status | Use |
|------|----------|------|--------|-----|
| JP1-Reality | VLESS+Reality (TCP) | 30187 | LIVE | Shield TV, AI services |
| JP-TUIC | TUIC v5 (QUIC/UDP) | — | LIVE | Phones, AUTO-FAST |
| JP-Hysteria2 | Hysteria2 (QUIC/UDP) | — | DEAD | Passive fallback only |

### Per-Device Routing

| Device | IP | Group | Node |
|--------|----|-------|------|
| Shield TV 4K | 192.168.111.183 | SHIELD-STABLE | JP1-Reality — **pinned, never changes** |
| Phones | .155, .156, .157, .194 | PHONE-FAST | JP-TUIC |
| Laptop | 192.168.111.181 | Mixed | Torrent → DIRECT, GFW domains → PROXY |
| Everything else | * | AUTO-FAST | JP-TUIC |

**OpenClash API:** `http://127.0.0.1:9090` on N100, Bearer `lBJEqlqp`
**GeoSite.dat:** Loyalsoldier v2ray-rules-dat, last updated February 2026

---

## Ralph Watchdog

Safety daemon on N100. Arm before every config change. If SSH or LuCI drops within the window, Ralph automatically restores the last backup and reboots.

```bash
ralph arm 120        # arm — auto-revert if no confirm in 120s
ralph confirm        # all OK — disarm
ralph status         # show current state
ralph restore        # force-revert to last backup NOW
```

---

## JP1 Monitoring

Cron job `*/5 * * * *` runs `/home/celso/axiom/bin/jp1_monitor.sh`.
Sends push notification via ntfy.sh to topic `axiom-jp1-celso` if JP1-Reality > 800ms for 3 consecutive 5-minute checks.
Install the ntfy app and subscribe to `axiom-jp1-celso`.

---

## Quick Health Check

```bash
# Tunnel alive?
ssh -p 2226 root@127.0.0.1 "echo OK"

# SHIELD-STABLE on JP1-Reality? (must always be JP1-Reality)
curl -s http://127.0.0.1:9090/proxies/SHIELD-STABLE \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'

# AUTO-FAST node?
curl -s http://127.0.0.1:9090/proxies/AUTO-FAST \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'

# JP-TUIC latency
curl -s 'http://127.0.0.1:9090/proxies/JP-TUIC' \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"delay":[0-9]*' | tail -1

# JP1-Reality latency
curl -s 'http://127.0.0.1:9090/proxies/JP1-Reality' \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"delay":[0-9]*' | tail -1
```

**Expected healthy state:**
- Tunnel: `OK`
- SHIELD-STABLE: `"now":"JP1-Reality"`
- AUTO-FAST: `"now":"JP-TUIC"`
- JP-TUIC: < 150ms
- JP1-Reality: < 500ms

---

## The 8 Sacred Rules

1. **NEVER add IP to br-wan** — kills tunnels in ~30s
2. **NEVER remove eth3 from br-lan** — permanent rescue lifeline
3. **NEVER disrupt Nvidia Shield** (192.168.111.183) — SACRED
4. **ALWAYS arm Ralph before risky changes** — `ralph arm 120`
5. **Management subnet 192.168.100.0/24 always bypasses proxy** — keeps SSH working
6. **Download GeoSite.dat on-router via curl, NEVER SCP through tunnel** — kills connection
7. **N100 br-wan must always be `proto=none` with no IP**
8. **Rescue IPs (.254/.253/.252/.251) must always exist on br-lan**

---

## Future Improvement Suggestions

| Priority | Improvement | Why |
|----------|------------|-----|
| High | Add a second JP proxy node | Single node = single point of failure. One node dead = full outage. |
| High | Deploy N100 inline (eth0→CT modem, eth1→MikroTik) | True transparent interception; eliminates dependency on MikroTik fake-IP static route |
| Medium | Lock MikroTik DNS via Netwatch | Netwatch has historically restored backup DNS (direct to 223.5.5.5), causing DNS leaks |
| Medium | VLAN segmentation for IoT | Sonos and other IoT devices should be isolated from main LAN |
| Medium | UPS for N100 + MikroTik | Shanghai power fluctuations can corrupt NVMe during writes |
| Medium | GeoSite.dat auto-update cron | Currently manual — was 3.5 years stale (Sep 2022 → Feb 2026) |
| Low | Redundant VPS / tunnel | Hetzner VPS outage = zero remote access |
| Low | MikroTik 4G/5G failover WAN | CT modem outages; USB dongle on spare ether port |
| Low | Move Plex to N100 NVMe | N100 has 476 GB NVMe and is always on; laptop does not need to stay awake |

---

## Further Documentation

- [Replication Guide](./docs/REPLICATION_GUIDE.md) — complete from-scratch rebuild, every command for every device
- [Standard Operating Procedures](./docs/NETWORK_SOP.md) — day-to-day ops, change management, troubleshooting
- [Network Audit 2026-02-24](./docs/NETWORK_AUDIT_2026-02-24.md) — full config snapshot
- [OpenClash config example](./config.yaml.example) — redacted live config with all proxy rules
