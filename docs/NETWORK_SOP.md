# AXIOM Network — Standard Operating Procedures

**Version:** 2026-02-24
**Applies to:** All changes to `/etc/openclash/config/config.yaml` on the router, proxy group modifications, rule additions, GeoSite.dat updates, and any change that affects proxy routing behavior.

---

## The Golden Rule

> **Every config change → arm Ralph → council review → deploy → verify.**

No exceptions. No "quick fixes" that skip council or Ralph. If Ralph fires and reverts, the change was wrong. Fix it, run council again, redeploy.

---

## 1. Ralph Watchdog

Ralph is the auto-revert safety net. It must be armed before every config change is deployed.

### What Ralph monitors
- SSH reverse tunnel liveness (`ssh -p 2226 root@127.0.0.1 "echo OK"`)
- SHIELD-STABLE proxy group → must resolve to JP1-Reality

### Ralph behavior
- 8 checks × 10-second intervals = 80 seconds total monitoring window
- If either check fails at any point: auto-reverts to `$BACKUP` config, restarts OpenClash
- If all 8 checks pass: change is considered stable, Ralph disarms

### Ralph requirement
Before arming, always set `BACKUP` to the last confirmed-working config file:

```bash
BACKUP=/etc/openclash/config/config.yaml.YYYYMMDD_known_good
```

Never arm Ralph with an untested or unverified backup. If you are unsure which backup is good, use the API to verify SHIELD-STABLE is live on the current config before promoting it to backup.

### Arming Ralph (example invocation)
```bash
BACKUP=/etc/openclash/config/config.yaml.20260220_good \
  /home/celso/axiom/bin/ralph_watchdog.sh
```

Ralph runs in the foreground and prints check results. Watch it complete all 8 checks before moving on.

---

## 2. Council Review Process

All 4 external models must review every proposed config change. 4/4 PASS is required to deploy. A single FAIL or WARN blocks deployment.

### Council members and scripts

| Model | Script |
|-------|--------|
| Codex | `bin/call_codex.sh` |
| Gemini | `bin/call_gemini.sh` |
| Qwen | `bin/call_qwen.sh` |
| DeepSeek R1 | `bin/call_deepseek_r1.sh` |

### Council review checklist
Each reviewer must confirm:
1. SHIELD-STABLE group type remains `select` and its only proxy is `JP1-Reality`
2. Rule #1 remains `SRC-IP-CIDR,192.168.111.183/32,SHIELD-STABLE`
3. No circular DNS dependency introduced (nameserver-policy must not reference AUTO-FAST)
4. The BACKUP config used for Ralph is a confirmed-good baseline
5. New domain rules land in correct position relative to the laptop DIRECT line
6. No dead proxies (JP-Hysteria2, SG1-Reality, TW1-Reality) added back to AUTO-FAST

### Deploying after council
Only deploy after receiving 4/4 PASS. Log the council results (all four model outputs) before deploying. If results are ambiguous, treat as FAIL.

---

## 3. Config File Location

```
/etc/openclash/config/config.yaml
```

This file lives on the router. Access it via the SSH reverse tunnel from the laptop.

---

## 4. SSH Tunnel

The SSH reverse tunnel runs from the router to the laptop on port 2226.

### Check tunnel status
```bash
ssh -p 2226 root@127.0.0.1 "echo OK"
```
Expected output: `OK`

### If tunnel is dead
Do not panic. The router uses autossh (or equivalent) to re-establish the tunnel automatically. Wait 30–60 seconds and retry. Do not force-restart OpenClash while the tunnel is recovering — it will interrupt the reconnect.

### Tunnel recovery sequence
1. Wait 60 seconds
2. Re-check: `ssh -p 2226 root@127.0.0.1 "echo OK"`
3. If still dead after 3 minutes: check if OpenClash is running on the router via the web UI
4. If OpenClash crashed: restart it (see Section 6), then wait for tunnel to re-establish

---

## 5. Restarting OpenClash

```bash
# Via SSH tunnel
ssh -p 2226 root@127.0.0.1 "/etc/init.d/openclash restart"
```

Allow ~10 seconds for the service to come back up and for the SSH tunnel to recover. After restart, verify:

```bash
# Wait 15 seconds, then check
sleep 15
ssh -p 2226 root@127.0.0.1 "echo tunnel OK"
curl -s http://127.0.0.1:9090/proxies/SHIELD-STABLE \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'
```

Expected: tunnel returns `tunnel OK`, API returns `"now":"JP1-Reality"`.

---

## 6. Clash REST API

Base URL: `http://127.0.0.1:9090`
Auth header: `Authorization: Bearer lBJEqlqp`

### Check SHIELD-STABLE (most important health check)
```bash
curl -s http://127.0.0.1:9090/proxies/SHIELD-STABLE \
  -H 'Authorization: Bearer lBJEqlqp'
```
Must return `"now":"JP1-Reality"` at all times.

### Check any proxy node latency
```bash
# JP-TUIC
curl -s 'http://127.0.0.1:9090/proxies/JP-TUIC' \
  -H 'Authorization: Bearer lBJEqlqp' \
  | grep -o '"delay":[0-9]*' | tail -1

# JP1-Reality
curl -s 'http://127.0.0.1:9090/proxies/JP1-Reality' \
  -H 'Authorization: Bearer lBJEqlqp' \
  | grep -o '"delay":[0-9]*' | tail -1
```

### Check AUTO-FAST selected node
```bash
curl -s http://127.0.0.1:9090/proxies/AUTO-FAST \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'
```
Expected: `"now":"JP-TUIC"`

### List all proxy groups
```bash
curl -s http://127.0.0.1:9090/proxies \
  -H 'Authorization: Bearer lBJEqlqp' | python3 -m json.tool
```

---

## 7. Revert Procedure

If a bad config was deployed and Ralph did not auto-revert (e.g., Ralph was not armed, or tunnel was already dead):

```bash
# Step 1: SCP the known-good backup to the router
scp -P 2226 /path/to/known_good_config.yaml \
  root@127.0.0.1:/etc/openclash/config/config.yaml

# Step 2: Restart OpenClash
ssh -p 2226 root@127.0.0.1 "/etc/init.d/openclash restart"

# Step 3: Wait and verify
sleep 15
curl -s http://127.0.0.1:9090/proxies/SHIELD-STABLE \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'
```

Expected after revert: `"now":"JP1-Reality"`

---

## 8. NEVER Touch

These elements are permanently frozen. Any change requires full council 4/4 PASS and written justification in the audit log.

| Item | Constraint |
|------|-----------|
| SHIELD-STABLE group type | Always `select`. Never `url-test`, `fallback`, or `load-balance`. |
| SHIELD-STABLE proxy | Always `JP1-Reality`. Never any other node. |
| Rule #1 | Always `SRC-IP-CIDR,192.168.111.183/32,SHIELD-STABLE`. Never reorder below any other rule. |

If you find yourself typing `url-test` or `fallback` next to `SHIELD-STABLE`, stop. This is wrong.

---

## 9. GeoSite.dat Update Procedure

**Critical:** Do NOT transfer GeoSite.dat via the SCP tunnel. At 9.8 MB it will saturate and kill the SSH connection.

Download directly on the router:

```bash
ssh -p 2226 root@127.0.0.1 "curl -L -o /tmp/GeoSite.dat.new \
  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat \
  && cp /tmp/GeoSite.dat.new /etc/openclash/GeoSite.dat \
  && echo 'GeoSite.dat updated'"
```

Then restart OpenClash and verify:

```bash
ssh -p 2226 root@127.0.0.1 "/etc/init.d/openclash restart"
sleep 15
curl -s http://127.0.0.1:9090/proxies/SHIELD-STABLE \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'
```

Update frequency: when GEOSITE,GFW coverage appears stale, or at least once per quarter.

---

## 10. Responding to JP1 Degradation Alert

When an alert fires on ntfy.sh topic `axiom-jp1-celso`:

1. **Check JP1-Reality latency via API:**
   ```bash
   curl -s 'http://127.0.0.1:9090/proxies/JP1-Reality' \
     -H 'Authorization: Bearer lBJEqlqp' \
     | grep -o '"delay":[0-9]*' | tail -1
   ```

2. **If latency > 800ms sustained:** Consider temporarily switching AI-PINNED to JP-TUIC via the API:
   ```bash
   curl -X PUT http://127.0.0.1:9090/proxies/AI-PINNED \
     -H 'Authorization: Bearer lBJEqlqp' \
     -H 'Content-Type: application/json' \
     -d '{"name":"JP-TUIC"}'
   ```

3. **Investigate VPS status:** Contact Henry (VPS owner) to check 147.79.20.20 status.

4. **Revert AI-PINNED to JP1-Reality** once latency recovers (should return to ~350ms baseline):
   ```bash
   curl -X PUT http://127.0.0.1:9090/proxies/AI-PINNED \
     -H 'Authorization: Bearer lBJEqlqp' \
     -H 'Content-Type: application/json' \
     -d '{"name":"JP1-Reality"}'
   ```

5. **Log the incident** in the audit file with timestamps and resolution.

---

## 11. Adding a New GFW-Blocked Domain

### For a general GFW-blocked domain (goes via PROXY)

1. Add this rule in config.yaml, **before** the `SRC-IP-CIDR,192.168.111.181/32,DIRECT` line:
   ```yaml
   - DOMAIN-SUFFIX,newdomain.com,PROXY
   ```

2. Run council (all 4 models, 4/4 PASS required).

3. Arm Ralph, deploy, verify.

### For an AI service domain (goes via AI-PINNED)

1. Add the rule **before** the `SRC-IP-CIDR,192.168.111.181/32,DIRECT` line:
   ```yaml
   - DOMAIN-SUFFIX,ai-service.com,AI-PINNED
   ```

2. Add a DoH entry to the nameserver-policy section:
   ```yaml
   nameserver-policy:
     'ai-service.com': 'https://1.1.1.1/dns-query#JP-TUIC'
   ```

3. Run council. Arm Ralph. Deploy. Verify.

---

## 12. Quick Reference Card

### Health check sequence (run in order)
```bash
# 1. Tunnel alive?
ssh -p 2226 root@127.0.0.1 "echo OK"

# 2. SHIELD-STABLE on JP1-Reality?
curl -s http://127.0.0.1:9090/proxies/SHIELD-STABLE \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'

# 3. AUTO-FAST on JP-TUIC?
curl -s http://127.0.0.1:9090/proxies/AUTO-FAST \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'

# 4. JP-TUIC latency
curl -s 'http://127.0.0.1:9090/proxies/JP-TUIC' \
  -H 'Authorization: Bearer lBJEqlqp' \
  | grep -o '"delay":[0-9]*' | tail -1

# 5. JP1-Reality latency
curl -s 'http://127.0.0.1:9090/proxies/JP1-Reality' \
  -H 'Authorization: Bearer lBJEqlqp' \
  | grep -o '"delay":[0-9]*' | tail -1
```

### Key constants
| Item | Value |
|------|-------|
| Router LAN | 192.168.111.0/24 |
| VPS IP | 147.79.20.20 |
| SSH tunnel port | 2226 |
| Clash API port | 9090 |
| Clash API token | lBJEqlqp |
| Shield TV IP | 192.168.111.183 |
| Laptop IP | 192.168.111.181 |
| ntfy topic | axiom-jp1-celso |
| JP-TUIC baseline | ~87ms |
| JP1-Reality baseline | ~350ms |
| Config path | `/etc/openclash/config/config.yaml` |

### Expected healthy state
- Tunnel: `OK`
- SHIELD-STABLE: `"now":"JP1-Reality"`
- AUTO-FAST: `"now":"JP-TUIC"`
- JP-TUIC delay: < 150ms
- JP1-Reality delay: < 500ms

Any deviation from the above is a potential incident. Investigate before making changes.

---

*SOP version: 2026-02-24. Update this document whenever a new phase is completed or a new procedure is established.*
