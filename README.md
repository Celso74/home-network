# Home Network — Shanghai, China

Transparent GFW-bypass network. Every device in the house gets the right routing path with zero manual proxy configuration. Built over multiple weeks of engineering sessions.

---

## Physical Topology

```
China Telecom ONT (fiber)
        │  DHCP → gives WAN IP to MikroTik
        ▼
MikroTik RB750Gr3 (hEX)
  192.168.111.1
  L3 router · DHCP server · NAT · firewall · DNS front-door
        │ ether2 (LAN bridge)
        ▼
Ruijie ES205GC (5-port switch)
  192.168.13.1 (mgmt) — pure L2
        │
   ┌────┴────────────────┐
   │                     │
   ▼                     ▼
N100 Mini PC        Ruijie ES209GC-P (PoE switch)
192.168.111.2        pure L2 · PoE power
GFW bypass /             │
DNS engine               ├── EAP102E "Ayi"
                         ├── EAP102E "Living Room"
                         ├── EAP102E "Master Bedroom"
                         └── EAP102E "HB"
```

---

## Physical Cabling

| # | From | Port | To | Port |
|---|------|------|----|------|
| 1 | CT Modem (ONT) | LAN out | MikroTik | ether1 (WAN) |
| 2 | MikroTik | ether2 | ES205GC | P1 |
| 3 | ES205GC | P2 | Laptop | NIC |
| 4 | ES205GC | P3 | ES209GC-P | uplink |
| 5 | ES205GC | P4 | N100 | eth2 |
| 6 | N100 | eth3 | Laptop | NIC — **rescue only, plug in when needed** |
| 7 | ES209GC-P | PoE port | EAP102E "Ayi" | PoE in |
| 8 | ES209GC-P | PoE port | EAP102E "Living Room" | PoE in |
| 9 | ES209GC-P | PoE port | EAP102E "Master Bedroom" | PoE in |
| 10 | ES209GC-P | PoE port | EAP102E "HB" | PoE in |

All cables are CAT5e/6 ethernet. N100 eth0 and eth1 are unused — the fiber ONT connects directly to MikroTik ether1 and this cannot be changed with a fiber connection.

---

## Wi-Fi Networks

| SSID | Purpose | Devices |
|------|---------|---------|
| *(main SSID)* | Primary — full GFW bypass | Phones, laptop, Shield TV, PS5, Alexa, Sonos |
| CIOT | IoT isolation — no GFW bypass needed | Xiaomi devices |

**Why Alexa and Sonos are on the main network, not CIOT:**
Alexa requires access to Amazon servers (GFW-blocked). Sonos streams Spotify, Apple Music, and Amazon Music (all GFW-blocked). These devices must be on the main network so their traffic goes through the proxy chain. Xiaomi devices communicate only with Chinese servers — no GFW bypass needed, and isolation on CIOT reduces attack surface.

---

## Device Inventory

### MikroTik RB750Gr3 (hEX)

| Field | Value |
|-------|-------|
| OS | RouterOS 7.18.2 |
| Role | Edge router, DHCP server, NAT, firewall, DNS front-door |
| LAN IP | **192.168.111.1**/24 |
| WAN port | ether1 — DHCP from CT modem (gets 192.168.71.15/24, GW 192.168.71.1) |
| LAN ports | ether2–ether5 (bridged) |
| DHCP pool | 192.168.111.5–192.168.111.250 |
| DNS handed to clients | **192.168.111.1** (itself) — MikroTik forwards all DNS to N100 |
| WebFig | http://192.168.111.1 |
| SSH | `ssh admin@192.168.111.1` |

**Static DHCP leases:**

| Device | IP | MAC |
|--------|----|-----|
| S22 Ultra | 192.168.111.194 | CE:50:7F:01:1B:AA |
| Nvidia Shield TV 4K | 192.168.111.183 | 00:04:4B:83:98:AF |
| Laptop | 192.168.111.181 | 30:05:05:93:1B:47 |
| PS5 | 192.168.111.161 | — |

**Critical static route (required for OpenClash fake-IP):**
```routeros
/ip route add dst-address=198.18.0.0/15 gateway=192.168.111.2
```
Without this, GFW bypass is broken for all routed clients.

**WARNING: MikroTik must NOT have a backup DNS (e.g. 223.5.5.5) configured. If Netwatch or any script adds a backup DNS, queries bypass N100 entirely → DNS leak → GFW-blocked sites stop working. This was the primary historical failure mode.**

**Config backups:** Google Drive `G:\My Drive\N100 Super Device - Saves and Images\MIKROTIK ROUTER\`
- `M1-BASELINE-SAFE-ACCESS.rsc` — clean baseline
- `M4-PHYSICAL-INTEGRATION-PREP.rsc` — pre-integration
- `M4.6-EAL-HARDENED.rsc` — current

---

### Ruijie ES205GC — Core Switch

| Field | Value |
|-------|-------|
| Model | Ruijie ES205GC (5-port Gigabit) |
| Role | Pure L2 distribution — no routing, no DHCP, no DNS |
| Management IP | 192.168.13.1 (factory default: 10.44.77.254) |
| Management | Local web UI at http://192.168.13.1, Ruijie Cloud app (锐捷睿易), or https://noc.ruijie.com.cn/ |

**Factory reset:** Hold reset 10 seconds → IP returns to 10.44.77.254. Connect laptop at 10.44.77.10/24 to recover.

---

### Intel N100 Mini PC — GFW Bypass + DNS Engine

| Field | Value |
|-------|-------|
| OS | iStoreOS 24.10.5 (OpenWrt-based), kernel 6.6.119 |
| Role | GFW bypass (OpenClash TUN + fake-IP), DNS intelligence layer |
| LAN IP | **192.168.111.2**/24 (br-lan via eth2 → ES205GC) |
| Rescue IP | 192.168.100.1/24 on eth3 (plug in eth3 cable when needed) |
| LuCI | http://192.168.100.1 (eth3 cable required) |
| Disk | 476.94 GiB NVMe SSD |

**Network interfaces:**

| Interface | State | IP | Role |
|-----------|-------|----|------|
| eth0 | DOWN | none | Unused |
| eth1 | DOWN | none | Unused |
| eth2 | **UP** | — | br-lan member → ES205GC |
| eth3 | DOWN | 192.168.100.1/24 | Rescue — plug in cable to use |
| br-lan | **UP** | 192.168.111.2/24 | Main LAN interface |
| br-wan | DOWN | **NO IP — EVER** | Unused bridge (eth0+eth1) |
| singtun0 | **UP** | 172.19.0.1/30 | OpenClash TUN interface |

**Rescue alias IPs on br-lan (survive every reboot):**
192.168.100.254 / .253 / .252 / .251

**Software stack:**

| Software | Bind | Role |
|----------|------|------|
| OpenClash (Mihomo Meta v1.19.19) | TUN + API :9090 | GFW bypass, fake-IP |
| dnsmasq | :53 | DNS — forwards to AdGuard Home |
| AdGuard Home | 127.0.0.1:5353 | Ad-block, upstream → chinadns-ng |
| chinadns-ng | 127.0.0.1:15353 | Split DNS: CN direct, GFW via proxy |
| Ralph watchdog | — | Auto-reverts bad configs |
| Dropbear | :22 | SSH |

**Disk image backup:**
- File: `BASELINE-01-BRIDGE-STABLE.img.gz`
- Location: `G:\My Drive\N100 Super Device - Saves and Images\`
- SHA256: `15d44acca59936032c213b095f53670d12fd580a969fabe320596a145602a4f0`
- Restore: `gunzip -c BASELINE-01-BRIDGE-STABLE.img.gz | dd of=/dev/nvme0n1 bs=4M status=progress`

---

### Ruijie ES209GC-P — PoE Switch

| Field | Value |
|-------|-------|
| Model | Ruijie ES209GC-P (9-port Gigabit PoE) |
| Role | PoE power + L2 distribution for all APs |
| Management | Ruijie Cloud app (锐捷睿易) or https://noc.ruijie.com.cn/ |
| Connected to | ES205GC P3 |

---

### Wi-Fi APs — Ruijie EAP102E × 4

Ceiling-mounted, PoE-powered, mesh mode. Pure L2 bridge — no routing, no DHCP, no NAT.

| AP Name | Location |
|---------|----------|
| Ayi | Ayi's room |
| Living Room | Living room |
| Master Bedroom | Master bedroom |
| HB | HB's room |

**All AP config is managed in the Ruijie Cloud app (锐捷睿易 / Ruijie Easy) or web portal at https://noc.ruijie.com.cn/ (login with phone number).** Do not use local web management — use the app or portal for SSID, password, channels, power, and mesh settings.

**Re-adding an AP after factory reset:**
1. Unplug PoE → replug
2. AP broadcasts setup SSID for ~2 minutes
3. Ruijie app → Add Device → follow pairing
4. AP rejoins mesh automatically

---

### Laptop — Windows

| Field | Value |
|-------|-------|
| Hostname | Celso-2 / celso-laptop-shanghai |
| LAN IP | 192.168.111.181 (static DHCP) |
| MAC | 30:05:05:93:1B:47 |
| Role | Keeps all reverse SSH tunnels alive via PowerShell scripts |
| Plex server | 192.168.110.16:32400 |

---

### Devices

| Device | Network | IP | Notes |
|--------|---------|----|-------|
| S22 Ultra | Main | 192.168.111.194 | Static lease, MAC CE:50:7F:01:1B:AA |
| Nvidia Shield TV 4K | Main | 192.168.111.183 | **SACRED** — SHIELD-STABLE, never disrupt |
| PS5 | Main | 192.168.111.161 | Gaming |
| Alexa | Main | DHCP | Needs Amazon (GFW) — must be on main, not CIOT |
| Sonos | Main | DHCP | Needs Spotify/Apple Music/Amazon Music (GFW) — must be on main |
| Xiaomi devices | CIOT | DHCP | IoT isolation — only talk to CN servers |

---

## Subnet Map

| Subnet | Gateway | DHCP | Purpose |
|--------|---------|------|---------|
| 192.168.71.0/24 | 192.168.71.1 | CT Modem | WAN — modem to MikroTik |
| 192.168.111.0/24 | 192.168.111.1 | MikroTik | Main LAN — all clients |
| 192.168.100.0/24 | 192.168.100.1 | None (static) | N100 rescue/management only |
| 192.168.13.0/24 | 192.168.13.1 | — | ES205GC switch management |
| 198.18.0.0/15 | — | — | OpenClash fake-IP range |

---

## Remote Access — Reverse SSH Tunnels

Reverse tunnels are opened from the laptop to the relay server and kept alive by PowerShell scripts. They allow remote access to all home network devices from anywhere.

| Port | Destination | Device |
|------|-------------|--------|
| 2223 | 192.168.100.1:22 | N100 |
| 2224 | 192.168.100.1:22 | N100 (second session) |
| 2226 | 127.0.0.1:22 | Laptop |
| 2231 | 192.168.111.1:22 | MikroTik |

**Connect from the relay server:**
```bash
ssh -p 2223 root@localhost      # N100
ssh -p 2226 celso@localhost     # Laptop
ssh -p 2231 admin@localhost     # MikroTik
```

**PowerShell scripts (run at startup via Task Scheduler):**
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
    ssh -R 2231:192.168.111.1:22 celso@5.75.182.153
    Start-Sleep 5
}
```

---

## DNS Architecture — Layered "God-Level DNS"

MikroTik hands all clients **itself** (`192.168.111.1`) as DNS. MikroTik then forwards all queries upstream to N100. N100 is the intelligence layer — it runs every query through the GFW-bypass chain and returns the correct result.

**Critical: MikroTik must have N100 as its only upstream DNS. No backup DNS (e.g. 223.5.5.5). If a backup exists, queries bypass N100 → DNS leak → GFW-blocked sites break. Netwatch restoring backup DNS was the primary historical failure mode.**

```
Client → DNS query → 192.168.111.1 (MikroTik)
                         │
                         │  MikroTik upstream DNS → N100
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
                    └─► GFW/Global  → 1.1.1.1 via proxy → fake-IP
                         │
                         ▼
                    Result → MikroTik → Client
```

---

## Traffic Flow (e.g. YouTube from phone)

```
Phone
  → EAP102E AP (mesh, L2 bridge)
  → ES209GC-P (L2)
  → ES205GC (L2)
  → MikroTik (default gateway)
      │ DNS query → forwarded to N100
      ← N100 returns fake-IP 198.18.x.x
  → MikroTik routes 198.18.x.x via static route → N100
  → N100 OpenClash TUN → JP1-Reality or JP-TUIC
  → Response back → MikroTik → Client
```

---

## Design Philosophy

**MikroTik = stability, fail-open. N100 = intelligence.**

- If OpenClash crashes or N100 reboots, MikroTik keeps routing — internet stays up, GFW bypass pauses
- MikroTik is rock solid; N100 can be updated or rebooted without dropping the house internet
- N100 is not the default gateway — it is a policy engine that MikroTik defers to for DNS and fake-IP routing

---

## Double NAT Elimination (~95%)

The China Telecom ONT is a fiber modem with no accessible admin interface — it cannot be put into bridge mode. This normally means double NAT: ONT nats once, MikroTik nats again. Double NAT causes issues with port forwarding, gaming (PS5), VoIP, and some VPN protocols.

**The solution:** MikroTik handles NAT as the only intelligent layer. The ONT is treated as a dumb upstream DHCP provider. MikroTik gets a public-ish IP from the ONT and does its own srcnat masquerade.

This eliminates double NAT for ~95% of traffic — the remaining ~5% is hairpin/loopback traffic and some ISP-level CGNAT that exists above the ONT and cannot be controlled. For all practical purposes (streaming, gaming, proxy tunnels) the network behaves as single-NAT.

---

## GFW Bypass

### Proxy Nodes (JP VPS 147.79.20.20 — Henry's shared, ~50 RMB/month, ~900 GB/month)

| Node | Protocol | Port | Status | Use |
|------|----------|------|--------|-----|
| JP1-Reality | VLESS+Reality (TCP) | 30187 | LIVE | Shield TV, AI services — stability critical |
| JP-TUIC | TUIC v5 (QUIC/UDP) | — | LIVE | Phones, AUTO-FAST — fastest |
| JP-Hysteria2 | Hysteria2 (QUIC/UDP) | — | DEAD | Passive fallback only |

### Per-Device Routing

| Device | IP | Proxy Group | Node |
|--------|----|-------------|------|
| Shield TV 4K | 192.168.111.183 | SHIELD-STABLE | JP1-Reality — **pinned, never changes** |
| Phones | .155, .156, .157, .194 | PHONE-FAST | JP-TUIC |
| Laptop | 192.168.111.181 | Mixed | Torrent → DIRECT, GFW domains → PROXY |
| Everything else | * | AUTO-FAST | JP-TUIC |

**OpenClash API:** `http://127.0.0.1:9090` on N100 · Bearer token `lBJEqlqp`
**GeoSite.dat:** Loyalsoldier v2ray-rules-dat, last updated February 2026

---

## Ralph Watchdog

Safety daemon on N100. Arm before every config change. Auto-reverts and reboots if SSH or LuCI goes down within the timeout.

```bash
ralph arm 120        # arm — auto-revert if no confirm in 120s
ralph confirm        # all OK — disarm
ralph status         # show state
ralph restore        # force-revert to last backup NOW
```

---

## JP1 Monitoring

Cron `*/5 * * * *` runs `/home/celso/axiom/bin/jp1_monitor.sh`.
Push notification via ntfy.sh topic `axiom-jp1-celso` if JP1-Reality > 800ms for 3 consecutive checks.
Install ntfy app, subscribe to `axiom-jp1-celso`.

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

# Latency checks
curl -s 'http://127.0.0.1:9090/proxies/JP-TUIC' \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"delay":[0-9]*' | tail -1

curl -s 'http://127.0.0.1:9090/proxies/JP1-Reality' \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"delay":[0-9]*' | tail -1
```

**Expected healthy state:**
- Tunnel: `OK` · SHIELD-STABLE: `"now":"JP1-Reality"` · AUTO-FAST: `"now":"JP-TUIC"`
- JP-TUIC: < 150ms · JP1-Reality: < 500ms

---

## The 8 Sacred Rules

1. **NEVER add IP to br-wan** — kills tunnels in ~30s
2. **NEVER remove eth3 from br-lan** — permanent rescue lifeline
3. **NEVER disrupt Nvidia Shield** (192.168.111.183) — SACRED
4. **ALWAYS arm Ralph before risky changes** — `ralph arm 120`
5. **Management subnet 192.168.100.0/24 always bypasses proxy** — keeps SSH working
6. **Download GeoSite.dat on-router via curl, NEVER SCP through tunnel** — kills the connection
7. **N100 br-wan must always be `proto=none` with no IP**
8. **Rescue IPs (.254/.253/.252/.251) must always exist on br-lan**

---

## Future Improvement Suggestions

| Priority | Improvement | Why |
|----------|------------|-----|
| High | Add second JP proxy node | JP VPS is single point of failure — if it goes down, no GFW bypass |
| Medium | Disable/remove MikroTik Netwatch DNS restore | Netwatch has historically re-added 223.5.5.5 as backup DNS causing leaks |
| Medium | VLAN for CIOT devices | Xiaomi IoT devices should be fully isolated at L3, not just a separate SSID |
| Medium | UPS for N100 + MikroTik | Shanghai power fluctuations risk NVMe corruption during writes |
| Medium | GeoSite.dat auto-update cron | Currently manual — was 3.5 years stale (Sep 2022 → Feb 2026) |
| Low | MikroTik 4G/5G failover WAN | CT fiber outages; USB dongle on spare ether port for backup WAN |
| Low | Move Plex to N100 NVMe | N100 has 476 GB NVMe, always on — laptop shouldn't need to stay awake for Plex |

---

## Further Documentation

- [Replication Guide](./docs/REPLICATION_GUIDE.md) — complete from-scratch rebuild, every command for every device
- [Standard Operating Procedures](./docs/NETWORK_SOP.md) — day-to-day ops, change management, troubleshooting
- [Network Audit 2026-02-24](./docs/NETWORK_AUDIT_2026-02-24.md) — full config snapshot
- [OpenClash config example](./config.yaml.example) — redacted live config with all proxy rules
