# Network Standard Operating Procedures

Day-to-day operations guide. See REPLICATION_GUIDE.md for full setup from scratch.

---

## Change Management

All config changes to N100 follow this procedure:

1. **Arm Ralph** before touching anything
   ```bash
   ralph arm 120      # 120s window — auto-reverts if you don't confirm
   ```
2. **Make the change**
3. **Test** — verify tunnel alive, SHIELD-STABLE on JP1-Reality, spot-check a GFW site
4. **Confirm or let revert**
   ```bash
   ralph confirm      # signal OK — disarm
   # OR just wait — Ralph auto-reverts after timeout if you don't confirm
   ```

Config changes are reviewed by a 5-model AI council (Claude + 4 external models) before deployment. No change deploys without unanimous pass.

---

## Access Commands

```bash
# From VPS (core-vps-1 / 5.75.182.153)
ssh -p 2226 root@127.0.0.1         # N100
ssh -p 2228 celso@127.0.0.1        # Laptop
ssh -p 2227 admin@127.0.0.1        # MikroTik

# From laptop on LAN
ssh root@192.168.100.1              # N100 (eth3 cable)
ssh admin@192.168.111.1             # MikroTik

# N100 LuCI web UI
http://192.168.100.1                # LuCI
http://192.168.100.1:3000           # AdGuard Home
http://127.0.0.1:9090               # OpenClash API (accessible via SSH tunnel)
```

---

## Health Check

```bash
# Full status check (run from laptop)
echo "=== Tunnel ===" && ssh -p 2226 root@127.0.0.1 "echo OK"

echo "=== SHIELD-STABLE ===" && \
  curl -s http://127.0.0.1:9090/proxies/SHIELD-STABLE \
    -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'

echo "=== AUTO-FAST ===" && \
  curl -s http://127.0.0.1:9090/proxies/AUTO-FAST \
    -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'

echo "=== JP-TUIC delay ===" && \
  curl -s 'http://127.0.0.1:9090/proxies/JP-TUIC' \
    -H 'Authorization: Bearer lBJEqlqp' | grep -o '"delay":[0-9]*' | tail -1

echo "=== JP1-Reality delay ===" && \
  curl -s 'http://127.0.0.1:9090/proxies/JP1-Reality' \
    -H 'Authorization: Bearer lBJEqlqp' | grep -o '"delay":[0-9]*' | tail -1

echo "=== br-wan (must have NO IP) ===" && \
  ssh -p 2226 root@127.0.0.1 "ip addr show br-wan | grep inet || echo CLEAN"
```

**Expected:**
- Tunnel: `OK`
- SHIELD-STABLE: `"now":"JP1-Reality"`
- AUTO-FAST: `"now":"JP-TUIC"`
- JP-TUIC: < 150ms
- JP1-Reality: < 500ms
- br-wan: `CLEAN` (no IP)

---

## JP1-Reality Degradation Alert

Monitor cron (`*/5 * * * *`) runs `/home/celso/axiom/bin/jp1_monitor.sh`.
Sends push alert to ntfy.sh topic `axiom-jp1-celso` if JP1 > 800ms for 3 consecutive checks (15 minutes).

**If alerted:**
1. Check JP1 delay manually (see health check above)
2. If confirmed degraded: log into OpenClash UI, switch SHIELD-STABLE manually to JP-TUIC temporarily
3. Contact VPS provider (Henry) about JP1 node issues
4. Switch back to JP1-Reality once resolved

---

## Adding a New Domain to the Proxy

When a site is blocked by GFW and needs routing through proxy:

1. Check if it's already covered by `GEOSITE,GFW,PROXY` — this catches ~5000 GFW domains automatically
2. If not covered: add an explicit rule in `config.yaml` **before** the `GEOSITE,CN,DIRECT` line
3. Add DoH override in `nameserver-policy` section for the domain
4. Run council review, then deploy with Ralph armed

**Rule placement guide (config.yaml rules section, top to bottom):**
```
CRL/OCSP revocation rules         ← HIGHEST priority, route via PROXY
SHIELD-STABLE per-device rule     ← never move (SRC-IP-CIDR,183)
LAN-wide QUIC block               ← AND,((NETWORK,UDP),(DST-PORT,443)),REJECT
Phone PHONE-FAST rules            ← SRC-IP AND DOMAIN-SUFFIX combos
Per-device rules (phones etc)
AI services (claude.ai, chatgpt.com → AI-PINNED)
CDN domains (githubassets, discordapp.net, etc → PROXY)
VPS DIRECT rule                   ← IP-CIDR,5.75.182.153/32,DIRECT
GEOSITE,CN,DIRECT                 ← China sites go direct
GEOSITE,GFW,PROXY                 ← GFW catch-all (~5000 domains)
Laptop DIRECT catch-all           ← torrent bandwidth saver
MATCH,PROXY                       ← everything else
```

> **Why CRL/OCSP rules must be at the top:** Without explicit domain rules, CRL/OCSP
> domains fall through to GeoIP matching. The GFW poisons DNS for foreign PKI domains
> (e.g., `c.pki.goog` resolves to a Chinese IP), causing them to match `GeoIP(CN)` and
> go DIRECT — which the GFW blocks. This breaks Windows TLS certificate revocation
> checking. See `docs/TROUBLESHOOTING_2026-02-26.md` for the full investigation.

---

## Updating GeoSite.dat

Run every few months to keep GFW domain list current.

```bash
# MUST run on router directly — DO NOT SCP through tunnel (kills connection)
ssh -p 2223 root@localhost

# On N100:
curl -L -o /tmp/GeoSite.dat.new \
  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat

mv /tmp/GeoSite.dat.new /etc/openclash/GeoSite.dat
/etc/init.d/openclash restart
```

---

## N100 Config Backup

```bash
# Quick config backup (keeps in /root/MILESTONES/)
ralph backup

# Manual backup with name
ssh -p 2223 root@localhost \
  "tar czf /root/MILESTONES/\$(date +%Y%m%d-%H%M%S).tar.gz /etc/config/ /etc/openclash/"

# Copy backup to laptop
scp -P 2223 root@localhost:/root/MILESTONES/latest.tar.gz ~/backups/
```

---

## MikroTik Config Backup

```routeros
# In WinBox terminal or SSH
/export file=backup-$(date +%Y%m%d)
# Then download via WinBox Files menu
```

Upload to Google Drive: `LD:N100 Super Device - Saves and Images/MIKROTIK ROUTER/`

---

## N100 Rescue (Locked Out)

1. Connect laptop directly to N100 eth3 with ethernet cable
2. Set laptop to static IP `192.168.100.10/24`
3. `ssh root@192.168.100.1` (or `.254`, `.253`, `.252`, `.251`)
4. If still no response: reboot N100 (hold power 5s), try again
5. If totally bricked: flash from USB (see REPLICATION_GUIDE.md Step 1)

---

## SSH Tunnel Recovery

Tunnels run from Windows laptop via PowerShell scripts. They reconnect automatically on failure.

**If tunnels are down and laptop is not accessible:**
- Tunnels are NOT auto-started server-side — requires laptop to be powered on and scripts running
- Have someone physically at the laptop run `C:\Users\Celso\tunnel_n100.ps1`

**If laptop is accessible but tunnels dropped:**
```powershell
# Kill stale SSH processes
Get-Process ssh | Stop-Process -Force

# Restart tunnel scripts
& C:\Users\Celso\tunnel_n100.ps1
```

---

## Ruijie Switch Recovery

If switch management (192.168.13.1) is not reachable:
1. Connect laptop directly to any switch port
2. Set laptop to static IP `192.168.13.10/24`
3. Browse to `http://192.168.13.1`
4. If factory reset needed: press and hold reset button 10s. IP resets to `10.44.77.254`.

---

## Laptop Proxy Troubleshooting

If browsers show `ERR_PROXY_CONNECTION_FAILED` but `curl.exe` works:

```bash
# Check Windows system proxy (from VPS via tunnel)
ssh -p 2228 celso@127.0.0.1 'reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable'
```

If `ProxyEnable` is `1`, a proxy client (Hiddify, Clash for Windows, v2rayN, etc.) left an orphaned proxy setting. The transparent proxy architecture does NOT need a local proxy client.

**Fix:**
```cmd
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "" /f
```

> **Note:** Windows `curl.exe` does NOT use the system proxy. It connects directly.
> So curl tests can succeed while browsers fail. Always check the system proxy when
> debugging browser-only connectivity issues.

---

## DoH Tag Configuration

All `nameserver-policy` DoH entries must use `#JP1-Reality` (TCP-based). Do NOT change to `#JP-TUIC` (UDP/QUIC) — the GFW throttles UDP traffic patterns after ~10 days, causing DNS resolution failures across the entire network.

**Verify current tags:**
```bash
ssh -p 2226 root@127.0.0.1 'grep "dns-query#" /etc/openclash/config/config.yaml | head -5'
# Should show: #JP1-Reality (NOT #JP-TUIC)
```

---

## Important Rules (Never Break)

1. **NEVER add IP to br-wan** — kills GFW tunnels in ~30s
2. **NEVER touch eth3 on N100** — permanent rescue lifeline
3. **NEVER disrupt Nvidia Shield** (`192.168.111.183`) — SACRED
4. **ALWAYS arm Ralph before risky changes** — `ralph arm 120`
5. **Management subnet 192.168.100.0/24 always bypasses proxy** — keeps SSH working
6. **Download GeoSite.dat on-router via curl, never SCP through tunnel**
7. **N100 br-wan must always be `proto=none` with no IP**
8. **Rescue IPs (.254/.253/.252/.251) must always exist on br-lan**
9. **DoH tags must use `#JP1-Reality`** — NEVER switch to `#JP-TUIC` (UDP throttling)
10. **CRL/OCSP rules must be at TOP of rules section** — prevents GFW DNS poisoning trap
11. **QUIC block must be AFTER all phone rules** — phones use JP1-Reality (TCP), so their QUIC is safe to proxy. The QUIC block must sit after the last phone catch-all so phones reach PHONE-FAST first. Only non-phone devices (laptop, IoT) are force-TCP'd by the block.
12. **PHONE-FAST must use JP1-Reality first** — JP-TUIC causes YouTube failures (QUIC-in-QUIC MTU fragmentation). Shield TV proves JP1-Reality delivers 1080p video despite misleading latency probes.
13. **Hysteria2 needs Salamander obfuscation** — bare QUIC is fingerprinted by GFW within ~30s on China Telecom. Ask Henry to enable it on the JP VPS.
14. **Telegram DC IPs need BOTH N100 rules AND MikroTik routes** — Telegram hardcodes DC IPs (149.154.x.x, 91.108.x.x). The architecture uses MikroTik as the LAN gateway, only routing 198.18.0.0/15 (fake-IP) to N100. Hardcoded IP traffic bypasses N100 entirely and hits GFW. Fix: add explicit MikroTik routes for each DC CIDR → gateway 192.168.111.2. See "Hardcoded IP Services" section.
15. **App connection state cache** — when a fix is applied, apps may still show "no connection" due to cached failed DNS/TCP state. Fix: disable WiFi, connect via mobile data + Singbox, load the app, then switch back to WiFi.
16. **MikroTik Phase2 routing architecture** — MikroTik is the default gateway for ALL LAN clients. It only routes fake-IP range (198.18.0.0/15) to N100 via the "Phase2-FakeIP-to-N100" static route. All other traffic goes directly to ISP (192.168.71.1). Any app/service using hardcoded IPs that are GFW-blocked needs an explicit MikroTik route to N100. This includes Telegram DCs, and potentially other services. See rollback: `/ip route remove [find where comment~"your comment"]`

---

## Hardcoded IP Services (MikroTik Routes Required)

Services that bypass DNS and use hardcoded IPs need MikroTik routes → N100 to be proxied.

### Architecture Reminder
```
LAN clients → MikroTik (192.168.111.1) → ISP (192.168.71.1)
                    ↓ (only 198.18.0.0/15)
                   N100 (192.168.111.2) → OpenClash → JP1-Reality
```
Domain-based traffic: DNS returns fake-IP (198.18.x.x) → MikroTik routes to N100 ✅
Hardcoded IP traffic: No fake-IP → MikroTik sends direct to ISP → GFW blocks ❌

### Telegram DC Routes (Applied 2026-02-27)

```routeros
# Add to MikroTik:
/ip route add dst-address=149.154.160.0/20 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.108.4.0/22 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.108.8.0/22 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.108.12.0/22 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.108.16.0/22 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.108.20.0/22 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.108.56.0/22 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.105.192.0/23 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=185.76.151.0/24 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"

# Verify:
/ip route print where comment~"Telegram"

# Rollback:
/ip route remove [find where comment~"Telegram DC -> N100 Proxy"]
```

> **Also required in N100/Mihomo config:** `IP-CIDR,149.154.160.0/20,PROXY,no-resolve` etc.
> Both MikroTik routes AND Mihomo IP-CIDR rules are needed — routes bring traffic to N100, rules route it via PROXY.

### Diagnosing Broken Hardcoded IP Services

```bash
# Check if traffic reaches N100 at all:
tail -f /tmp/openclash.log | grep "IP_ADDRESS"  # If empty, not reaching N100

# Check laptop's default gateway (should be MikroTik):
# Windows: route print 0.0.0.0

# Add MikroTik route for the problematic CIDR, then test again
```

