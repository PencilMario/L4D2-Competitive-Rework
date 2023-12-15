#!/bin/bash

# IP列表
IP=("120.225.14.155" "113.12.72.251")

sudo iptables -F
sudo iptables -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# 封禁IP
for i in "${IP[@]}"
do
    sudo iptables -A INPUT -s $i -j DROP
done