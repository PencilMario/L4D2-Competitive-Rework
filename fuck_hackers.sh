#!/bin/bash

# IP列表
IP=("120.225.14.155")

# 封禁IP
for i in "${IP[@]}"
do
    sudo iptables -A INPUT -s $i -j DROP
done