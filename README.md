# AXIOM Household Network

A transparent proxy setup running on an OpenWrt N100 mini-PC with OpenClash (Mihomo Meta) managing GFW bypass for all household devices. Every device gets appropriate routing without any manual proxy configuration on the device itself.

---

## What It Does

All LAN traffic on 192.168.111.0/24 passes through Mihomo Meta in TUN + fake-ip mode. The proxy engine applies per-device and per-domain rules to decide whether traffic goes direct (to China ISP) or through one of the Japan VPS proxy nodes. Devices never need to configure anything — routing is handled entirely at the router.

---

## Hardware

| Component | Details |
|-----------|---------|
| Router | iStoreOS/OpenWrt, Intel N100 mini-PC |
| Proxy engine | Mihomo Meta v1.19.19, TUN + fake-ip mode |
| ISP | China Telecom (CT Modem) |
| LAN | 192.168.111.0/24 |
| VPS | 147.79.20.20 (Japan) — Henry's shared VPS, 50 RMB/month, ~900 GB/month |
| Tunnel | SSH reverse tunnel: VPS → Laptop, port 2226 |
| API | Clash REST API on port 9090, Bearer token `lBJEqlqp` |

---

## Proxy Nodes (all on JP VPS 147.79.20.20)

| Node | Protocol | Latency | Status |
|------|----------|---------|--------|
| JP-TUIC | TUIC v5 over QUIC/UDP | ~87ms | LIVE — fastest |
| JP1-Reality | VLESS/XTLS-Vision/Reality over TCP | ~350ms | LIVE — stable |
| JP-Hysteria2 | Hysteria2 over QUIC/UDP | DEAD (3000ms+) | Passive fallback only |

JP-TUIC is the workhorse — used by AUTO-FAST and all phones. JP1-Reality is used for stability-critical devices where stream interruption is unacceptable (Shield TV, AI services, Google auth). JP-Hysteria2 is dead due to a server-side QUIC connection limit on the shared VPS and cannot be fixed without root access.

---

## Per-Device Routing

| Device | IP | Proxy group | Effective node | Notes |
|--------|----|-------------|----------------|-------|
| Shield TV 4K | 192.168.111.183 | SHIELD-STABLE | JP1-Reality | HOLY — first rule, never changes |
| S8+ | 192.168.111.155 | PHONE-FAST | JP-TUIC | |
| S8 | 192.168.111.156 | PHONE-FAST | JP-TUIC | |
| iPhone | 192.168.111.157 | PHONE-FAST | JP-TUIC | |
| S22 Ultra | 192.168.111.194 | PHONE-FAST | JP-TUIC | |
| Laptop | 192.168.111.181 | Mixed (explicit rules) | Varies | Torrent → DIRECT |
| Everything else | * | PROXY → AUTO-FAST | JP-TUIC | |

---

## Key Design Decisions

### Shield TV gets its own pinned proxy (SHIELD-STABLE)
The Shield TV 4K runs YouTube, Netflix, and other streaming services. Auto-switching proxies cause mid-stream interruptions. SHIELD-STABLE is permanently pinned to JP1-Reality (select group type, never url-test or fallback). This is a HOLY rule — the first rule in the rule list, matching on SRC-IP before anything else runs. It has never been changed and should never need to be.

### Laptop torrent traffic goes DIRECT
The JP VPS has a ~900 GB/month bandwidth limit. Torrent traffic is high-volume and does not need GFW bypass. A `SRC-IP-CIDR,192.168.111.181/32,DIRECT` rule near the end of the rule list catches all laptop traffic that was not matched by explicit domain rules above it. This saves significant VPS bandwidth while still routing GFW-blocked domains (GitHub, YouTube, etc.) through the proxy via the explicit rules above the laptop DIRECT line.

### GEOSITE,GFW,PROXY as systemic catch-all
Rather than manually adding every newly-blocked domain, `GEOSITE,GFW` matches approximately 5000 GFW-blocked domains from a regularly-updated community database (Loyalsoldier v2ray-rules-dat). This means new sites blocked by the GFW are handled automatically when GeoSite.dat is updated, without any config changes. GeoSite.dat was last updated February 2026 (from Sep 2022 baseline).

### DoH via JP-TUIC for GFW-sensitive domains
China's GFW poisons DNS responses for blocked domains. Using a plain nameserver (even 8.8.8.8) for these domains returns poisoned results. The nameserver-policy section sends DNS queries for all GFW-sensitive domains over HTTPS via JP-TUIC (`https://1.1.1.1/dns-query#JP-TUIC`), bypassing DNS poisoning entirely. The DoH nameserver must never reference AUTO-FAST — that caused a circular dependency in Phase 8 (AUTO-FAST needed DNS to pick a node, but DNS needed AUTO-FAST to resolve). It is pinned to JP-TUIC directly.

### Ralph watchdog auto-reverts bad configs within 80 seconds
Before every config deployment, a watchdog script (Ralph) is armed. It runs 8 checks at 10-second intervals, monitoring the SSH tunnel and SHIELD-STABLE. If either check fails, Ralph automatically SCPs the last known-good backup to the router and restarts OpenClash. This means a broken config is reverted in under 90 seconds without human intervention, and the Shield TV never goes down for more than ~10 seconds.

### 5-model council reviews all changes
Every config change is reviewed by Claude (planner), Codex, Gemini, Qwen, and DeepSeek before deployment. 4/4 external model PASS is required. The council checks for rule ordering errors, SHIELD-STABLE integrity, circular DNS dependencies, and rule placement relative to the laptop DIRECT line. No change deploys without council approval.

---

## Quick Status Check

```bash
# Is the SSH tunnel alive?
ssh -p 2226 root@127.0.0.1 "echo OK"

# Is SHIELD-STABLE on JP1-Reality? (must always be yes)
curl -s http://127.0.0.1:9090/proxies/SHIELD-STABLE \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'

# Is AUTO-FAST on JP-TUIC? (expected healthy state)
curl -s http://127.0.0.1:9090/proxies/AUTO-FAST \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'

# Current JP-TUIC latency
curl -s 'http://127.0.0.1:9090/proxies/JP-TUIC' \
  -H 'Authorization: Bearer lBJEqlqp' \
  | grep -o '"delay":[0-9]*' | tail -1

# Current JP1-Reality latency
curl -s 'http://127.0.0.1:9090/proxies/JP1-Reality' \
  -H 'Authorization: Bearer lBJEqlqp' \
  | grep -o '"delay":[0-9]*' | tail -1
```

### Expected healthy state
- Tunnel: `OK`
- SHIELD-STABLE: `"now":"JP1-Reality"`
- AUTO-FAST: `"now":"JP-TUIC"`
- JP-TUIC delay: < 150ms
- JP1-Reality delay: < 500ms

---

## Monitoring

JP1-Reality degradation is monitored by a cron job (`*/5 * * * *`) running `/home/celso/axiom/bin/jp1_monitor.sh`. If JP1 exceeds 800ms for 3 consecutive checks (15 minutes), an alert is sent via ntfy.sh to topic `axiom-jp1-celso`. Install the ntfy app and subscribe to that topic to receive push notifications.

---

## Further Documentation

- [Full Network Audit (2026-02-24)](./NETWORK_AUDIT_2026-02-24.md) — complete hardware inventory, proxy topology, DNS architecture, rule list, all optimization phases, known issues
- [Standard Operating Procedures](./NETWORK_SOP.md) — Ralph watchdog, council process, revert procedure, GeoSite.dat update, responding to JP1 alerts, adding new domains
