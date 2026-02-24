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
ssh -p 2223 root@localhost          # N100
ssh -p 2226 celso@localhost         # Laptop
ssh -p 2231 admin@localhost         # MikroTik

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
  ssh -p 2223 root@localhost "ip addr show br-wan | grep inet || echo CLEAN"
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
SHIELD-STABLE per-device rule     ← first, never move
Per-device rules (phones etc)
AI services (claude.ai, chatgpt.com → AI-PINNED)
CDN domains (githubassets, discordapp.net, etc → PROXY)
GEOSITE,CN,DIRECT                 ← China sites go direct
GEOSITE,GFW,PROXY                 ← GFW catch-all (~5000 domains)
Laptop DIRECT catch-all           ← torrent bandwidth saver
MATCH,PROXY                       ← everything else
```

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

## Important Rules (Never Break)

1. **NEVER add IP to br-wan** — kills GFW tunnels in ~30s
2. **NEVER touch eth3 on N100** — permanent rescue lifeline
3. **NEVER disrupt Nvidia Shield** (`192.168.111.183`) — SACRED
4. **ALWAYS arm Ralph before risky changes** — `ralph arm 120`
5. **Management subnet 192.168.100.0/24 always bypasses proxy** — keeps SSH working
6. **Download GeoSite.dat on-router via curl, never SCP through tunnel**
7. **N100 br-wan must always be `proto=none` with no IP**
8. **Rescue IPs (.254/.253/.252/.251) must always exist on br-lan**
