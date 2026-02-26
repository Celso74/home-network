# Network Troubleshooting Session — 2026-02-26

**Symptoms:** WiFi devices (laptop, phones) slow/broken. Shield TV (wired) working fine.
- Chrome/Edge: `ERR_PROXY_CONNECTION_FAILED` on all sites
- `curl.exe` (Schannel): `CRYPT_E_REVOCATION_OFFLINE (0x80092013)` on HTTPS sites
- LinkedIn: "proxy fail", YouTube: "no internet", Gmail: "proxy error"

**Resolution method:** 5-model AXIOM council (Claude + Codex + Gemini + Qwen + DeepSeek), 3 rounds.

---

## Root Causes Found (3 issues, layered)

### Issue 1: DoH DNS Tag Drift (N100 config)

**What happened:** All `nameserver-policy` DoH entries had been changed from `#JP1-Reality` to `#JP-TUIC` during a previous config session. This meant DNS resolution for proxied domains was forced through JP-TUIC (UDP/QUIC), which is vulnerable to GFW UDP throttling after ~10 days.

**Fix:** Reverted all DoH tags back to `#JP1-Reality` (TCP-based, GFW-resistant).

```bash
# On N100:
sed -i 's|#JP-TUIC"|#JP1-Reality"|g' /etc/openclash/config/config.yaml
```

**Council verdict:** Unanimous (5/5) — revert to JP1-Reality.

---

### Issue 2: CRL/OCSP Revocation Servers Unreachable (GFW DNS poisoning)

**What happened:** Windows Schannel performs live OCSP/CRL revocation checks during TLS handshakes. The CRL/OCSP domains (`c.pki.goog`, `crl3.digicert.com`, `ocsp.digicert.com`, `x1.c.lencr.org`, etc.) were not matched by any domain rule in OpenClash. They fell through to the `GeoIP` rule, which resolved them via local DNS. The GFW poisoned these DNS responses, returning Chinese IPs. Mihomo then routed them `DIRECT` — straight into the GFW block.

**Key insight (Gemini):** `c.pki.goog` resolved to a Chinese IP due to GFW DNS poisoning, matched `GeoIP(CN)`, went `DIRECT`, and was blocked.

**Fix:** Added 14 CRL/OCSP domain rules at the **top** of the rules section, routing through `PROXY`:

```yaml
rules:
  # === CRL/OCSP REVOCATION FIX ===
  - DOMAIN-SUFFIX,pki.goog,PROXY
  - DOMAIN-SUFFIX,digicert.com,PROXY
  - DOMAIN-SUFFIX,lencr.org,PROXY
  - DOMAIN-SUFFIX,identrust.com,PROXY
  - DOMAIN-SUFFIX,amazontrust.com,PROXY
  - DOMAIN-SUFFIX,comodoca.com,PROXY
  - DOMAIN-SUFFIX,globalsign.com,PROXY
  - DOMAIN-SUFFIX,entrust.net,PROXY
  - DOMAIN-SUFFIX,verisign.com,PROXY
  - DOMAIN-SUFFIX,thawte.com,PROXY
  - DOMAIN-SUFFIX,symcb.com,PROXY
  - DOMAIN-SUFFIX,usertrust.com,PROXY
  - DOMAIN-KEYWORD,ocsp,PROXY
  - DOMAIN-KEYWORD,crl,PROXY
  # === END CRL/OCSP FIX ===
```

**Council verdict:** Majority (3/5 — Codex + Gemini + Claude) said route via PROXY. Qwen + DeepSeek suggested DIRECT + fake-ip-filter, but that would expose traffic to GFW DNS poisoning. PROXY is correct.

**Why NOT `fake-ip-filter`:** Adding CRL domains to fake-ip-filter forces real DNS resolution, which gets GFW-poisoned Chinese IPs. Keeping them on fake-IP lets Mihomo intercept by domain name and route through the proxy where the Japan VPS resolves the real IP.

**Why NOT DIRECT:** The GFW blocks or poisons DNS for foreign PKI infrastructure. DIRECT sends traffic into the GFW firewall.

---

### Issue 3: Hiddify Orphaned System Proxy (Laptop)

**What happened:** Hiddify (a proxy client) was installed on the laptop at `C:\Program Files\Hiddify\`. It had set the Windows system proxy to `127.0.0.1:12334`, but the Hiddify process was NOT running. Chrome, Edge, and OneDrive were all stuck in `SYN_SENT` trying to connect to this dead local proxy.

**Evidence:**
```
HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
  ProxyEnable: 1
  ProxyServer: http://127.0.0.1:12334
```

Port 12334: Nothing listening. `TcpTestSucceeded: False`.

**Why this was missed initially:** `curl.exe` on Windows does NOT use the WinINET system proxy — it connects directly. So curl tests appeared to work (with `--ssl-revoke-best-effort`), but browsers use the system proxy and were completely blocked.

**Fix:** Disabled system proxy via registry:

```cmd
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "" /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v AutoDetect /t REG_DWORD /d 0 /f
```

**Council verdict:** Unanimous (5/5) — disable proxy and uninstall Hiddify.

---

## Diagnostic Commands Used

### From VPS (accessing N100 via SSH tunnel)
```bash
# Check Mihomo process
ssh -p 2226 root@127.0.0.1 'ps w | grep clash'

# Check proxy health
curl -s http://127.0.0.1:9090/proxies/JP1-Reality -H "Authorization: Bearer TOKEN"
curl -s http://127.0.0.1:9090/proxies/JP-TUIC -H "Authorization: Bearer TOKEN"

# Test TUN path from N100
ssh -p 2226 root@127.0.0.1 'curl -s -o /dev/null -w "%{http_code} %{time_total}s" https://www.youtube.com'

# Check Mihomo logs for specific device
ssh -p 2226 root@127.0.0.1 'cat /tmp/openclash.log | grep "192.168.111.181" | tail -30'

# Check MikroTik route
curl -s -u admin:PASSWORD http://192.168.111.1/rest/ip/route | grep 198.18
```

### From VPS (accessing laptop via SSH tunnel)
```bash
# Check Windows proxy settings
ssh -p 2228 celso@127.0.0.1 'reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable'

# Check what's listening on a port
ssh -p 2228 celso@127.0.0.1 'netstat -ano | findstr PORT'

# Check which process owns a PID
ssh -p 2228 celso@127.0.0.1 'powershell.exe -NoProfile -Command "Get-Process -Id PID | Select-Object ProcessName, Path"'

# Test DNS from laptop
ssh -p 2228 celso@127.0.0.1 'nslookup youtube.com'

# Test HTTPS from laptop (Schannel)
ssh -p 2228 celso@127.0.0.1 'curl.exe --connect-timeout 30 --ssl-revoke-best-effort https://www.youtube.com'
```

---

## Key Lessons

1. **Windows `curl.exe` does NOT use the system proxy.** It connects directly. This means curl tests can succeed while browsers fail completely. Always check the system proxy setting when debugging browser-only failures.

2. **GFW poisons DNS for foreign PKI infrastructure.** CRL/OCSP domains like `c.pki.goog` and `crl3.digicert.com` get poisoned Chinese IPs. These domains MUST be routed through the proxy, not DIRECT.

3. **DoH tag drift is dangerous.** Changing `#JP1-Reality` to `#JP-TUIC` seems harmless but moves all DNS resolution to UDP (QUIC), which the GFW throttles after ~10 days. Always use TCP-based proxies for DNS.

4. **Proxy clients leave orphaned settings.** Hiddify, Clash for Windows, v2rayN, and similar tools set `ProxyEnable=1` in the Windows registry. If the tool is uninstalled or not running, all browser traffic breaks. Always check the system proxy when debugging Windows connectivity.

5. **Rule placement matters.** CRL/OCSP rules must be ABOVE `GeoIP`, `GEOSITE`, and `SrcIPCIDR` catch-alls. If they fall through to GeoIP, the GFW-poisoned DNS response causes them to match `GeoIP(CN)` and go DIRECT.

---

## Files Changed

### N100 (`/etc/openclash/config/config.yaml`)
- All DoH tags: `#JP-TUIC` → `#JP1-Reality`
- PROXY group: JP1-Reality as default
- Added `+.rj.link` to fake-ip-filter (Ruijie AP log spam)
- Added `DOMAIN-SUFFIX,rj.link,DIRECT` rule
- Added 14 CRL/OCSP rules at top of rules section

### Laptop (Windows 11)
- `ProxyEnable`: 1 → 0
- `ProxyServer`: `http://127.0.0.1:12334` → cleared
- `AutoDetect`: set to 0 (WPAD disabled)

### Backups
- Pre-fix backup: `/root/ralph_backups/PRE-COUNCIL-FIX-20260226T183417Z.yaml`
- Registry backup: `C:\Users\Celso\Desktop\internet-settings-backup-20260226.reg` (if created)

---

## Post-Fix Status

| Test | Result |
|------|--------|
| N100 → YouTube (TUN) | 200 in 1.9s |
| Laptop → YouTube (curl, --ssl-revoke-best-effort) | 200 in 12.1s |
| Laptop → gstatic.com (HTTP) | 204 in 7s |
| Laptop → baidu.com (DIRECT) | 200 in <1s |
| Shield TV → Netflix | Working continuously throughout |
| JP-TUIC latency | 218ms, alive |
| JP1-Reality latency | 308ms, alive |

**Remaining:** Hiddify should be fully uninstalled to prevent reoccurrence. Windows Schannel OCSP checking adds ~10s overhead to HTTPS connections via curl.exe; browsers (Chrome/Edge) use BoringSSL+CRLSets and are not affected by this.
