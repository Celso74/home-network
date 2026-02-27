@echo off
echo Starting all VPS tunnels...
ssh -R 2226:192.168.111.2:22 -R 2227:192.168.111.1:22 -R 2228:127.0.0.1:22 -R 2230:192.168.111.2:9090 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 celso@5.75.182.153
pause
