#!/bin/bash

# IP列表
IP=("120.225.14.155" "113.12.72.251" "39.144.191.147" "223.159.77.18" "36.143.130.5" "112.26.31.37" "120.225.14.53" "183.227.88.81" "222.217.59.50")

sudo iptables -F
sudo iptables -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# 全ip限速
sudo iptables -A INPUT -p tcp --syn -m connlimit --connlimit-above 10 -j REJECT --reject-with tcp-reset
sudo iptables -A INPUT -p tcp -m hashlimit --hashlimit-above 250kb/s --hashlimit-mode srcip --hashlimit-name in -j DROP
sudo iptables -A INPUT -p udp -m hashlimit --hashlimit-above 250kb/s --hashlimit-mode srcip --hashlimit-name in -j DROP
 
# 封禁IP
for i in "${IP[@]}"
do
    sudo iptables -A INPUT -s $i -j DROP
done
