@echo off
echo Adding VPS key to N100...
ssh root@192.168.111.2 "echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE0YYDeuzOW53w8gaPwZCh8bPofddZejzHnRzKwwxgLi celso@core-vps-1' > /etc/dropbear/authorized_keys"
echo Done.
pause
