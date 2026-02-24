# AXIOM Network Audit — 2026-02-24

**Audit scope:** Full household proxy network — hardware, proxy topology, routing rules, DNS architecture, known issues, monitoring.
**Status:** Production stable. All critical paths verified.

---

## 1. Hardware Inventory

| Component | Details |
|-----------|---------|
| Router | iStoreOS/OpenWrt, N100 mini-PC |
| Proxy engine | Mihomo Meta v1.19.19, TUN + fake-ip mode |
| LAN subnet | 192.168.111.0/24 |
| ISP modem | CT Modem (China Telecom) |
| JP VPS | 147.79.20.20 — Henry's shared VPS, 50 RMB/month, ~900 GB/month bandwidth limit |
| SSH reverse tunnel | VPS → Laptop, port 2226 (`ssh -p 2226 root@127.0.0.1`) |
| Clash REST API | Port 9090, Bearer token: `lBJEqlqp` |

---

## 2. Proxy Nodes

### JP VPS (147.79.20.20)

| Name | Protocol | Transport | Avg Latency | Status |
|------|----------|-----------|-------------|--------|
| JP1-Reality | VLESS / XTLS-Vision / Reality | TCP | ~350ms (variable) | LIVE |
| JP-TUIC | TUIC v5 | QUIC / UDP | ~87ms | LIVE (FASTEST) |
| JP-Hysteria2 | Hysteria2 | QUIC / UDP | 3000ms+ | DEAD |

**JP-Hysteria2 failure root cause:** 33% timeout rate caused by server-side QUIC connection limit on the shared VPS. Cannot be resolved without root access to the VPS host. Node kept in PHONE-FAST as passive last-resort fallback only. Removed from AUTO-FAST.

**Current latencies (Feb 24, 2026):**
- JP-TUIC: ~87ms — selected by AUTO-FAST
- JP1-Reality: ~350ms variable — used by all pinned stable groups
- JP-Hysteria2: DEAD — 3000ms+ on most checks

---

## 3. Proxy Groups

| Group | Type | Members | Effective Node | Purpose |
|-------|------|---------|----------------|---------|
| AUTO-FAST | url-test (interval 180s) | JP-TUIC, JP1-Reality | JP-TUIC | General auto-select; fastest wins |
| PHONE-FAST | fallback | JP-TUIC, JP1-Reality, JP-Hysteria2 | JP-TUIC | All phones — falls back in order |
| SHIELD-STABLE | select | JP1-Reality | JP1-Reality | Shield TV 4K — HOLY, never changed |
| LOGIN_STABLE | select | JP1-Reality | JP1-Reality | YouTube / Google OAuth stability |
| AI-PINNED | select | JP1-Reality | JP1-Reality | AI services (OpenAI, Anthropic, etc.) |
| JP_PIN_STABLE | select | JP1-Reality | JP1-Reality | Core Google services |
| META-PINNED | select | JP1-Reality | JP1-Reality | Facebook / Instagram |
| PROXY | select | AUTO-FAST | AUTO-FAST → JP-TUIC | General proxy catch-all |

**SHIELD-STABLE is HOLY.** Its group type (select) and its proxy (JP1-Reality) must never be changed. Any config touching SHIELD-STABLE must pass council 4/4 before deploy.

---

## 4. Network Devices and Routing

| Device | IP | Rule mechanism | Proxy group | Effective node | Notes |
|--------|----|---------------|-------------|----------------|-------|
| Shield TV 4K | 192.168.111.183 | SRC-IP FIRST rule (rule #1, absolute) | SHIELD-STABLE | JP1-Reality | HOLY |
| S8+ | 192.168.111.155 | SRC-IP catch-all | PHONE-FAST | JP-TUIC | |
| S8 | 192.168.111.156 | SRC-IP catch-all | PHONE-FAST | JP-TUIC | |
| iPhone | 192.168.111.157 | SRC-IP catch-all | PHONE-FAST | JP-TUIC | |
| S22 Ultra | 192.168.111.194 | SRC-IP catch-all | PHONE-FAST | JP-TUIC | |
| Laptop | 192.168.111.181 | Explicit rules → GEOSITE,GFW → DIRECT | Mixed | Varies | Torrent → DIRECT |
| Everything else | * | MATCH | PROXY | AUTO-FAST → JP-TUIC | |

---

## 5. DNS Architecture

**Mode:** fake-ip — returns 198.18.x.x immediately; real resolution happens in the background. Eliminates DNS latency from connection initiation.

| Role | Server |
|------|--------|
| Primary nameserver | 223.5.5.5 (Alibaba, CN) |
| Fallback nameserver | 8.8.8.8 (Google) |
| GFW-sensitive domains | DoH via `https://1.1.1.1/dns-query#JP-TUIC` |

### DoH nameserver-policy (all → `https://1.1.1.1/dns-query#JP-TUIC`)

The following domains receive DNS-over-HTTPS via JP-TUIC, providing GFW poisoning protection:

```
google.com, youtube.com, openai.com, gemini.google.com, perplexity.ai, deepseek.com,
linkedin.com, github.com, twitter.com, x.com, telegram.org, discord.com, reddit.com,
anthropic.com, claude.ai, chatgpt.com, huggingface.co
```

**Note:** The DoH nameserver previously referenced `#AUTO-FAST`, which caused a circular dependency (AUTO-FAST needed DNS to select a proxy, but DNS needed AUTO-FAST to resolve). Fixed in Phase 8 to use `#JP-TUIC` directly.

### fake-ip-filter

fake-ip is suppressed for: NTP servers, local/LAN services, CN domains. This prevents fake-IPs from leaking into CN-direct or LAN traffic.

---

## 6. Rule Architecture (top to bottom)

| Order | Rule | Target | Notes |
|-------|------|--------|-------|
| 1 | `SRC-IP-CIDR,192.168.111.183/32` | SHIELD-STABLE | FIRST rule — absolute, never reorder |
| 2–N | Phone AND rules | Per-device per-domain | Per-device exceptions for specific domains |
| N+1 | Phone SRC-IP catch-alls (.155, .156, .157, .194) | PHONE-FAST | All phone traffic not matched above |
| — | Google connectivity check | AUTO-FAST | |
| — | YouTube / Google login | LOGIN_STABLE | OAuth stability |
| — | AI services (openai.com, chatgpt.com, claude.ai, perplexity.ai, deepseek.com, huggingface.co, etc.) | AI-PINNED | |
| — | Meta: facebook.com, instagram.com | META-PINNED | CDN → DIRECT |
| — | CN apps (taobao, jd, wechat, alipay, etc.) | DIRECT | |
| — | Apple services | DIRECT | |
| — | YouTube / Google suite | PROXY | |
| — | GitHub, Twitter, Telegram, LinkedIn, Discord, Reddit, Spotify, Anthropic | PROXY | |
| — | `GEOIP,LAN` | DIRECT | |
| — | `GEOIP,CN` / `GEOSITE,CN` | DIRECT | |
| — | Phase 9D explicit: claude.ai, huggingface.co | AI-PINNED | Council-approved |
| — | Phase 9D CDN: githubassets.com, discordapp.net, discord.gg, redditstatic.com, redditmedia.com | PROXY | |
| — | `GEOSITE,GFW` | PROXY | Systemic — ~5000 GFW-blocked domains; geosite.dat updated Feb 2026 |
| — | `SRC-IP-CIDR,192.168.111.181/32` | DIRECT | Laptop torrent direct — saves VPS bandwidth |
| LAST | `MATCH` | PROXY | Catch-all |

**Rule ordering is critical.** The SHIELD-STABLE SRC-IP rule must remain rule #1. The laptop DIRECT rule must come after domain-specific rules so that GFW-blocked domains for the laptop are caught by explicit rules before the DIRECT fallback.

---

## 7. Optimization Phases Completed

### Phase 6Y
- Added QUIC reject rule in nftables (`openclash_mangle` table)
- Blocks Hysteria2 QUIC noise from reaching the router's upstream

### Phase 7J
- Established Shield TV HOLY rule (SRC-IP first, absolute)
- Added phone AND rules for per-device per-domain routing
- Full per-device routing topology finalized

### Phase 8
- Removed dead proxies SG1-Reality, TW1-Reality, JP-Hysteria2 from AUTO-FAST
- Fixed DNS circular dependency: `#AUTO-FAST` → `#JP-TUIC` in nameserver-policy
- Verified all 4 phones online and routing correctly

### Phase 9
- LOGIN_STABLE: fixed group type from fallback → select
- DoH additions: github, twitter, telegram, discord, reddit, anthropic, claude.ai
- Added discord, reddit, spotify rules before laptop DIRECT line

### Phase 9b
- chatgpt.com → AI-PINNED (was missing; traffic went DIRECT → GFW blocked)

### Phase 9d
- Council-approved: claude.ai + huggingface.co → AI-PINNED
- 5 CDN domains (githubassets.com, discordapp.net, discord.gg, redditstatic.com, redditmedia.com) → PROXY
- GEOSITE,GFW,PROXY systemic fix applied

### Phase 10
- Removed SG1-Reality and TW1-Reality proxy definitions entirely from config
- GeoSite.dat updated: Sep 2022 → Feb 2026 (downloaded directly on router at 3.8 MB/s)
- JP1 degradation monitor installed (cron + ntfy)

---

## 8. Known Issues and Deferred Items

### JP-Hysteria2 — DEAD (deferred, no fix path)
- **Symptom:** 33% timeout rate, 3000ms+ on most latency checks
- **Root cause:** Server-side QUIC connection limit on Henry's shared VPS
- **Fix:** Requires root VPS access to raise the limit — not available
- **Mitigation:** Kept in PHONE-FAST as last-resort passive fallback; removed from AUTO-FAST
- **Cost to fix properly:** Migrate to a dedicated VPS (DMIT CN2 GIA starts at $21.90/month — too expensive vs current 50 RMB/month)

### Phone GEOSITE,CN shadow gap (deferred, low impact)
- **Symptom:** Phones visiting CN-registered domains hosted on foreign CDN IPs may route via PHONE-FAST (proxy) instead of DIRECT
- **Impact:** Minor — slightly higher VPS bandwidth usage for affected CN domains on phones
- **Fix:** Complex — requires per-phone domain override rules; deferred

### JP1-Reality high latency (~350ms) — structural, no fix
- **Root cause:** No CN2 GIA routing optimization on current VPS
- **Fix:** DMIT CN2 GIA starts at $21.90/month — too expensive vs current 50 RMB/month shared VPS
- **Mitigation:** JP1-Reality is only used for stability-critical groups (SHIELD-STABLE, AI-PINNED, LOGIN_STABLE). Fast groups (AUTO-FAST, PHONE-FAST) prefer JP-TUIC at ~87ms

---

## 9. Monitoring

### JP1 Degradation Monitor
- **Script:** `/home/celso/axiom/bin/jp1_monitor.sh`
- **Schedule:** `*/5 * * * *` (every 5 minutes, via cron on router)
- **Logic:** Alerts if JP1-Reality latency exceeds 800ms for 3 consecutive checks (15 minutes sustained degradation)
- **Alert channel:** ntfy.sh topic `axiom-jp1-celso`
- **Action on alert:** Install ntfy app → subscribe to `axiom-jp1-celso` → receive push notification

### Ralph Watchdog
- **Trigger:** Armed before every config change
- **Logic:** 8 checks × 10s intervals (80 seconds total)
- **Monitors:** SSH tunnel liveness + SHIELD-STABLE → JP1-Reality
- **Action on failure:** Auto-reverts to last known-good backup config, restarts OpenClash
- **Requirement:** BACKUP variable must always be set to last known-good config before arming

### Clash REST API Health Check
```bash
# Check proxy group status
curl -s http://127.0.0.1:9090/proxies/SHIELD-STABLE \
  -H 'Authorization: Bearer lBJEqlqp'

# Check specific node latency
curl -s 'http://127.0.0.1:9090/proxies/JP1-Reality' \
  -H 'Authorization: Bearer lBJEqlqp' \
  | grep -o '"delay":[0-9]*' | tail -1

# Check SSH tunnel
ssh -p 2226 root@127.0.0.1 "echo OK"
```

---

## 10. Bandwidth Budget

- VPS monthly limit: ~900 GB
- Primary consumers: phones via PHONE-FAST (JP-TUIC), AI services via AI-PINNED (JP1-Reality)
- Laptop torrent traffic: routed DIRECT — does not consume VPS bandwidth
- Dead proxy JP-Hysteria2: removed from AUTO-FAST — no wasted retries on that path
- GeoSite.dat update (9.8 MB): must be downloaded directly on router, NOT transferred via SCP tunnel (kills the connection)

---

*Audit generated: 2026-02-24. Next review recommended after any VPS change or Phase 11 work.*
