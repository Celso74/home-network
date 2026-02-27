# Network Troubleshooting Session — 2026-02-27

**Symptoms:**
- Telegram Desktop (laptop, Windows) and Telegram Android (S22 Ultra): "no connection" / "connecting..." forever
- Phone YouTube/Google News: stopped working (separate issue, also resolved this session)

**Resolution method:** 5-model AXIOM council (Claude + Codex + Gemini + Qwen + DeepSeek), Council Rounds 9–12.

---

## Issues Resolved This Session

### Issue 1: Phone YouTube/Google News Broken (S22 Ultra)

**Root Causes (2 layered):**

**1a. QUIC block before phone rules** — The `AND,((NETWORK,UDP),(DST-PORT,443)),REJECT` rule was at line 267 in the Mihomo config, BEFORE phone-specific rules. Phone QUIC traffic was being rejected before reaching PHONE-FAST.

**Fix:** Moved QUIC block AFTER all phone catch-all rules (after iPhone rule at line 367).

**1b. Leftover nftables Phase6Y rule** — A stale nftables rule was blocking S22 Ultra (192.168.111.194) QUIC traffic at kernel level: `ip saddr 192.168.111.194 udp dport 443 counter reject with icmp port-unreachable comment "Phase6Y_phone_QUIC_reject"` — had blocked 3612 packets.

**Fix:**
```bash
# On N100 — find and delete the handle:
nft list chain inet fw4 openclash_mangle -a | grep Phase6Y
nft delete rule inet fw4 openclash_mangle handle <NUMBER>
```

**App state cache fix:** After applying, app still shows "no connection". Fix: disable WiFi → enable 5G + Singbox → load app → turn off Singbox → re-enable WiFi.

---

### Issue 2: Telegram Not Working on Laptop and Phone

**Root Cause: MikroTik routing architecture — hardcoded IPs bypass N100 proxy**

**Architecture:**
- MikroTik (192.168.111.1) is the default gateway for ALL LAN clients
- MikroTik only routes `198.18.0.0/15` (Mihomo fake-IP range) to N100 via static route
- All other traffic goes directly to ISP → GFW blocks Telegram DC IPs

**Why domain-based services (Google, YouTube, Twitter) work:**
1. DNS query → N100 (OpenClash) → returns fake-IP (198.18.x.x)
2. Client connects to 198.18.x.x → MikroTik routes to N100 → OpenClash proxies ✅

**Why Telegram fails:**
1. Telegram Desktop/Android hardcodes DC IPs: 149.154.167.92, 91.108.56.132, etc.
2. No DNS involved → no fake-IP → MikroTik routes directly to ISP → GFW blocks ❌
3. Result: SYN_SENT on client, zero traffic in OpenClash logs

**Diagnosis steps that confirmed root cause:**
```bash
# 1. Check Telegram's actual connections on laptop:
ssh -p 2228 celso@127.0.0.1 'netstat -ano | findstr "22240"'
# Showed: SYN_SENT to 149.154.167.92:443, 91.108.56.132:443

# 2. Check OpenClash log — zero Telegram entries:
tail -f /tmp/openclash.log  # No 149.154.x.x or 91.108.x.x entries

# 3. Confirm JP1-Reality CAN reach Telegram DCs (TCP connection succeeds, TLS fails only because curl != MTProto):
ssh -p 2226 root@127.0.0.1 'curl -v --socks5 127.0.0.1:7891 https://149.154.175.50 --connect-timeout 10'
# Result: "SOCKS5 request granted" + TCP connects + TLS handshake starts → JP1-Reality works ✅

# 4. Confirmed laptop's default gateway is MikroTik:
ssh -p 2228 celso@127.0.0.1 'route print 0.0.0.0'
# Gateway: 192.168.111.1 (MikroTik) ← NOT N100!
```

**Fix — Add MikroTik routes for all Telegram DC CIDRs:**

```routeros
# On MikroTik (ssh -p 2227 admin@127.0.0.1):
/ip route add dst-address=149.154.160.0/20 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.108.4.0/22 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.108.8.0/22 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.108.12.0/22 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.108.16.0/22 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.108.20.0/22 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.108.56.0/22 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=91.105.192.0/23 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
/ip route add dst-address=185.76.151.0/24 gateway=192.168.111.2 comment="Telegram DC -> N100 Proxy"
```

**Verification:**
```bash
# Check routes active on MikroTik:
/ip route print where comment~"Telegram"

# After routes applied, OpenClash log shows Telegram connections:
# [TCP] 192.168.111.181:52700 --> 149.154.167.41:80 match IPCIDR(149.154.160.0/20) using PROXY[JP1-Reality]

# Check Telegram connections are now ESTABLISHED on laptop:
ssh -p 2228 celso@127.0.0.1 'netstat -ano | findstr "22240"'
# Shows: ESTABLISHED to 149.154.167.41:443, 91.108.56.132:443 ✅
```

**Council verdict:** 4/4 APPROVE (all members: Gemini, Qwen, Codex, DeepSeek)

---

## Key Lesson: Two-Part Fix for Hardcoded IP Services

For any service that bypasses DNS and uses hardcoded IPs (like Telegram):

1. **N100/Mihomo config**: Add `IP-CIDR,<cidr>,PROXY,no-resolve` rules — handles routing once traffic reaches N100
2. **MikroTik routes**: Add `dst-address=<cidr> gateway=192.168.111.2` — essential to route traffic TO N100 in the first place

Without step 2, traffic never reaches N100 and the Mihomo rules are irrelevant.

**Rollback MikroTik routes:**
```routeros
/ip route remove [find where comment~"Telegram DC -> N100 Proxy"]
```

---

## What Was Already Correct (No Changes Needed)

- N100 nftables: ALL TCP traffic correctly redirected to Mihomo redir port (7892)
- Mihomo PROXY group: correctly set to JP1-Reality
- IP-CIDR rules in config.yaml: correctly placed before laptop DIRECT rule
- JP1-Reality proxy: confirmed reachable and working for Telegram DC IPs

The routing architecture was the only missing piece.

---

## Tunnel Port Corrections

During this session, confirmed correct tunnel ports (updated in NETWORK_SOP.md):
- Port 2226: N100 (192.168.111.2:22) — `ssh -p 2226 root@127.0.0.1`
- Port 2227: MikroTik (192.168.111.1:22) — `ssh -p 2227 admin@127.0.0.1`
- Port 2228: Laptop (127.0.0.1:22) — `ssh -p 2228 celso@127.0.0.1`
- Port 2230: OpenClash API (192.168.111.2:9090)
