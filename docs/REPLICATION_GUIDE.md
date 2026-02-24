# Replication Guide — Complete From-Scratch Setup

This guide covers everything needed to rebuild this network from zero. Follow the steps in order.

---

## Prerequisites

- Intel N100 Mini PC with 4× GbE ports and NVMe SSD
- MikroTik RB750Gr3 (hEX)
- Ruijie RG-ES25GC 25-port switch
- Ruijie EG110G-P AP controller / PoE switch
- 4× Ruijie EAP102E ceiling-mount APs
- Hetzner VPS (or any Linux VPS with public IP)
- Windows laptop for management

---

## Step 1: Flash N100

1. Download iStoreOS x86_64 image from https://fw.koolcenter.com/iStoreOS/x86_64/
2. Write to USB with Ventoy or Rufus
3. Boot N100 from USB, install to NVMe (`/dev/nvme0n1`)
4. Connect laptop to N100 eth3 (rightmost port)
5. Set laptop IP manually: `192.168.100.10/24`, gateway `192.168.100.1`
6. SSH: `ssh root@192.168.100.1` (default password: `password`)

**Full disk image backup** (faster than reinstalling):
- File: `BASELINE-01-BRIDGE-STABLE.img.gz`
- SHA256: `15d44acca59936032c213b095f53670d12fd580a969fabe320596a145602a4f0`
- Location: Google Drive `LD:N100 Super Device - Saves and Images/`
- Restore: `gunzip -c BASELINE-01-BRIDGE-STABLE.img.gz | dd of=/dev/nvme0n1 bs=4M status=progress`

---

## Step 2: Configure N100 Bridges

**The most critical part.** br-wan is a transparent L2 bridge with NO IP address. This is what makes N100 invisible to MikroTik and the CT modem.

```bash
# Create transparent WAN bridge (eth0 = CT modem side, eth1 = MikroTik side)
uci set network.br_wan=device
uci set network.br_wan.type='bridge'
uci set network.br_wan.name='br-wan'
uci set network.br_wan.ports='eth0 eth1'

uci set network.wan=interface
uci set network.wan.device='br-wan'
uci set network.wan.proto='none'     # CRITICAL — never change this to anything else

# Management (eth3 only — NEVER add eth0/eth1/eth2 to this)
uci set network.lan.device='eth3'
uci set network.lan.ipaddr='192.168.100.1'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.proto='static'

# Rescue alias IPs (survive every reboot — multiple fallback paths)
for n in 1 2 3 4; do
  addr="192.168.100.$((255 - n + 1))"
  uci set network.lan_rescue${n}=interface
  uci set network.lan_rescue${n}.proto='static'
  uci set network.lan_rescue${n}.device='br-lan'
  uci set network.lan_rescue${n}.ipaddr="${addr}"
  uci set network.lan_rescue${n}.netmask='255.255.255.0'
done

# eth2 = N100's own internet access (gets DHCP from house switch)
uci set network.egress=interface
uci set network.egress.proto='dhcp'
uci set network.egress.device='eth2'

uci commit && /etc/init.d/network restart
```

**Verify bridge is transparent:**
```bash
ip addr show br-wan    # Must show NO inet address — only link/ether
brctl show br-wan      # Must list eth0 and eth1 as members
```

---

## Step 3: Physical Cabling

```
CT Modem ──────► N100 eth0     (WAN IN)
                 N100 eth1 ──► MikroTik ether1   (WAN OUT)
                 N100 eth2 ──► Ruijie RG-ES25GC  (management internet)
                 N100 eth3 ──► Laptop             (rescue/management — dedicated cable)

MikroTik ether2 ──► Ruijie RG-ES25GC port P1
Ruijie RG-ES25GC port P3 ──► Ruijie EG110G-P
Ruijie EG110G-P ──► 4× EAP102E APs (PoE)
```

Power-on order: CT Modem → N100 → MikroTik → switches → APs

---

## Step 4: Configure MikroTik RB750Gr3

Connect to MikroTik via WinBox (download from mikrotik.com) or SSH to `192.168.111.1`.

```routeros
# WAN — DHCP from CT modem (via N100 transparent bridge)
/ip dhcp-client add interface=ether1 disabled=no add-default-route=yes

# LAN bridge (ether2–5)
/interface bridge add name=bridge
/interface bridge port add bridge=bridge interface=ether2
/interface bridge port add bridge=bridge interface=ether3
/interface bridge port add bridge=bridge interface=ether4
/interface bridge port add bridge=bridge interface=ether5

# LAN IP
/ip address add address=192.168.111.1/24 interface=bridge

# DHCP server
/ip pool add name=lan-pool-111 ranges=192.168.111.5-192.168.111.250
/ip dhcp-server add address-pool=lan-pool-111 interface=bridge name=server1 disabled=no
/ip dhcp-server network add address=192.168.111.0/24 gateway=192.168.111.1 \
    dns-server=223.5.5.5,223.6.6.6

# NAT masquerade on WAN
/ip firewall nat add chain=srcnat out-interface=ether1 action=masquerade

# DNS (clients will query this but N100 intercepts before reaching the internet)
/ip dns set servers=223.5.5.5,223.6.6.6 allow-remote-requests=yes

# Static DHCP leases
/ip dhcp-server lease add address=192.168.111.194 mac-address=CE:50:7F:01:1B:AA \
    comment="S22 Ultra - Phone static"
/ip dhcp-server lease add address=192.168.111.183 mac-address=00:04:4B:83:98:AF \
    comment="Shield TV - SACRED"
/ip dhcp-server lease add address=192.168.111.181 mac-address=30:05:05:93:1B:47 \
    comment="Laptop"

# CRITICAL: Fake-IP static route (push to clients via DHCP option 121)
# Routes 198.18.0.0/15 to N100's LAN IP so OpenClash fake-IP works
# N100 LAN IP on 192.168.111.x subnet — check after N100 gets DHCP on eth2
/ip route add dst-address=198.18.0.0/15 gateway=<N100_eth2_IP>

# DHCP Option 121 — classless static routes for fake-IP
# Encodes: 198.18.0.0/15 via <N100_eth2_IP>
# Generate with: https://www.medo64.com/2014/03/classless-static-dhcp-route/
/ip dhcp-server option add code=121 name=fake-ip-route value=<encoded_value>
/ip dhcp-server network set 0 dhcp-option=fake-ip-route
```

**Verify MikroTik is getting WAN IP:**
```routeros
/ip dhcp-client print    # Should show 192.168.71.15 bound on ether1
/ip route print          # Should show default route via 192.168.71.1
```

**MikroTik SSH key setup:**
```bash
# From laptop, copy key to MikroTik
ssh-copy-id -i ~/.ssh/id_rsa_mikrotik admin@192.168.111.1
```

---

## Step 5: Configure Ruijie RG-ES25GC Switch

Factory default IP: `10.44.77.254`

1. Connect laptop to switch with static IP `10.44.77.10/24`
2. Browse to `http://10.44.77.254`
3. Login: admin/admin (factory default)
4. Change management IP to `192.168.13.1/24`
5. Set default gateway: `192.168.111.1`

> **If switch is cloud-managed (Ruijie app):** Factory reset required to get local web access back. Hold reset button 10 seconds. Default IP will be `10.44.77.254` again.

---

## Step 6: Configure Ruijie EG110G-P and APs

The EG110G-P and EAP102E APs are managed via the Ruijie Cloud app (Chinese app: "锐捷睿易").

**EG110G-P settings:**
- IP: 192.168.110.1/24
- DHCP range: 192.168.110.2–254
- DHCP DNS: 223.5.5.5 (N100 will intercept this transparently)

**AP setup (EAP102E × 4):**
1. Connect each AP to EG110G-P PoE port
2. APs auto-discover and register with Ruijie Cloud
3. Configure in Ruijie Cloud app:
   - SSID: set desired network name(s)
   - AP names: Ayi, Living Room, Master Bedroom, HB
   - Mesh mode: enabled
   - VLAN: none (pure L2 bridge)

**APs do NOT route, NAT, or serve DHCP.** They are pure L2 bridge devices.

---

## Step 7: Install DNS Stack on N100

```bash
# dnsmasq — forward all DNS to AdGuard Home, never resolve itself
uci set dhcp.cfg01411c.noresolv='1'
uci set dhcp.cfg01411c.server='127.0.0.1#5353'
uci set dhcp.cfg01411c.localise_queries='1'
uci commit dhcp && /etc/init.d/dnsmasq restart

# Install AdGuard Home
curl -sSfL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
# Configure via web UI at http://192.168.100.1:3000
# Bind: 127.0.0.1:5353
# Upstream DNS: [::1]:15353 (chinadns-ng)
# Bootstrap DNS: 223.5.5.5

# Install chinadns-ng
opkg update && opkg install chinadns-ng
# Configure: port 15353, china-dns 223.5.5.5 119.29.29.29
# trust-dns: PassWall upstream (tcp://1.1.1.1#53 via proxy)

# nftables: intercept all port 53 traffic passing through bridge
# Add to /etc/config/firewall or /etc/nftables.d/:
nft add rule inet fw4 forward ip protocol tcp tcp dport 53 tproxy ip to 127.0.0.1:53 meta mark set 1
nft add rule inet fw4 forward ip protocol udp udp dport 53 tproxy ip to 127.0.0.1:53 meta mark set 1
```

---

## Step 8: Install GFW Bypass (OpenClash)

```bash
# Install OpenClash via opkg (iStoreOS has it in repo)
opkg update && opkg install luci-app-openclash

# Download Mihomo Meta core
mkdir -p /etc/openclash/core
wget -O /etc/openclash/core/clash_meta \
  https://github.com/MetaCubeX/mihomo/releases/latest/download/mihomo-linux-amd64-compatible
chmod +x /etc/openclash/core/clash_meta

# Upload config (see config.yaml.example in this repo)
# Config goes to: /etc/openclash/config/config.yaml

# Download GeoSite.dat and GeoIP.dat directly on router
curl -L -o /etc/openclash/GeoSite.dat \
  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
curl -L -o /etc/openclash/GeoIP.dat \
  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat

# Start OpenClash
/etc/init.d/openclash start
```

> **IMPORTANT:** Download GeoSite.dat directly on the router using `curl`. Do NOT SCP it through the SSH tunnel — the file is 3–10 MB and will kill the SSH connection.

**OpenClash config key settings:**
- Mode: `fake-ip`
- TUN: enabled
- Fake-IP range: `198.18.0.0/15`
- DNS: `nameserver-policy` for GFW-sensitive domains → `https://1.1.1.1/dns-query#JP-TUIC`
- API: port `9090`, secret `lBJEqlqp`

---

## Step 9: Configure Proxy Nodes

Add to OpenClash config.yaml under `proxies:`:

```yaml
proxies:
  - name: JP1-Reality
    type: vless
    server: 147.79.20.20
    port: 30187
    uuid: <get from VPS provider>
    network: tcp
    tls: true
    reality-opts:
      public-key: <get from VPS>
      short-id: <get from VPS>
    client-fingerprint: chrome

  - name: JP-TUIC
    type: tuic
    server: 147.79.20.20
    port: <port>
    uuid: <uuid>
    password: <password>
    alpn: [h3]
    congestion-controller: bbr
```

> Node credentials are held by the VPS provider (Henry). Contact for current credentials.

---

## Step 10: Install Ralph Watchdog

```bash
# Ralph is the safety net. ALWAYS arm it before config changes.
# Full script is in /usr/bin/ralph on the live N100.
# Restore from milestone backup or from ai_handoff.txt

# After install:
chmod +x /usr/bin/ralph /usr/bin/ralph.sh
/etc/init.d/ralph enable
/etc/init.d/ralph start

# Verify
ralph status
```

---

## Step 11: Set Up SSH Tunnels (Windows Laptop)

**Create startup scripts** and add to Windows Task Scheduler to run at login:

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

**VPS sshd_config** must have `GatewayPorts yes` for tunnels to bind on 0.0.0.0.

**Verify tunnels are up from VPS:**
```bash
ssh -p 2223 root@localhost "echo N100 ok"
ssh -p 2226 celso@localhost "echo laptop ok"
ssh -p 2231 admin@localhost "echo mikrotik ok"
```

---

## Step 12: Verify Full Chain

```bash
# 1. N100 bridge is transparent (no IP on br-wan)
ssh -p 2223 root@localhost "ip addr show br-wan"
# Expected: NO inet address

# 2. MikroTik has WAN IP
ssh -p 2231 admin@localhost "/ip dhcp-client print"
# Expected: bound, 192.168.71.x

# 3. DNS chain working
ssh -p 2223 root@localhost "dig @127.0.0.1 -p 5353 youtube.com +short"
# Expected: returns 198.18.x.x (fake-IP) — not real IP

# 4. GFW bypass working
ssh -p 2223 root@localhost "curl --proxy socks5://127.0.0.1:1080 -s https://www.youtube.com -o /dev/null -w '%{http_code}'"
# Expected: 200

# 5. Shield TV on JP1-Reality
curl -s http://127.0.0.1:9090/proxies/SHIELD-STABLE \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"now":"[^"]*"'
# Expected: "now":"JP1-Reality"
```

---

## Firewall Notes (N100)

```bash
# Block QUIC/UDP 443 at WAN (GFW blocks it anyway, prevents connection hangs)
nft add rule inet fw4 forward ip protocol udp udp dport 443 drop

# Bypass proxy for management subnet
# Add to OpenClash config: SRC-IP-CIDR,192.168.100.0/24,DIRECT
```

---

## Config Backup & Restore

### N100 — quick config backup
```bash
# On N100
tar czf /tmp/backup-$(date +%Y%m%d).tar.gz /etc/config/ /etc/openclash/ /opt/AdGuardHome/AdGuardHome.yaml

# Copy to laptop (from laptop)
scp -P 2223 root@localhost:/tmp/backup-$(date +%Y%m%d).tar.gz ~/backups/
```

### N100 — full disk image
```bash
# Run from bootable USB (N100 powered off from OS)
dd if=/dev/nvme0n1 bs=4M status=progress | gzip > BASELINE-01-BRIDGE-STABLE.img.gz

# Restore
gunzip -c BASELINE-01-BRIDGE-STABLE.img.gz | dd of=/dev/nvme0n1 bs=4M status=progress
```

### MikroTik — config export
```routeros
/export file=backup-M5
# Download via WinBox Files menu
```

---

## Troubleshooting

### Tunnels died suddenly
```bash
# Check br-wan for accidental IP
ssh -p 2223 root@localhost "ip addr show br-wan"
# If it has IP: uci delete network.wan.ipaddr && uci commit && /etc/init.d/network restart

# Check dropbear running
ssh -p 2223 root@localhost "netstat -tln | grep :22"
```

### N100 not passing traffic
```bash
# Verify bridge members
brctl show br-wan     # Must list eth0 and eth1
ip link show br-wan   # Must be UP
```

### MikroTik not getting WAN IP
```routeros
/ip dhcp-client print     # Status must be "bound"
/ping 192.168.71.1        # Should reach CT modem through N100 bridge
```

### DNS not working
```bash
dig @127.0.0.1 -p 5353 google.com    # Test AGH
dig @127.0.0.1 -p 15353 google.com   # Test chinadns-ng
# Check AGH UI at http://192.168.100.1:3000
```

### YouTube / GFW sites not working
```bash
# Check OpenClash status
/etc/init.d/openclash status

# Verify JP1-Reality is reachable
curl -s 'http://127.0.0.1:9090/proxies/JP1-Reality' \
  -H 'Authorization: Bearer lBJEqlqp' | grep -o '"delay":[0-9]*'

# Check GeoSite.dat exists and is not stale
ls -lh /etc/openclash/GeoSite.dat
```

### Can't reach N100 (all tunnels down)
```bash
# Connect laptop to N100 eth3 directly
# Set laptop IP: 192.168.100.10/24
ssh root@192.168.100.1     # or .254, .253, .252, .251 (rescue aliases)
```
