#!/bin/bash
cd ~

#sudo apt-get install -y ipset tcpdump

# 设定阈值，10秒内数据包超过这个数量的IP将被封禁
THRESHOLD=300

# 封禁的时间（秒）
TIMEOUT=3600

# 准备一个文件来保存被封禁的IP
BLOCKED_IP_FILE="/home/steam/blocked_ip.txt"

gitrep=L4D2-Competitive-Rework

# 指定要监控的端口
PORTS=()
port_list=()
cd /home/steam/$gitrep/cfg/spcontrol_server/;
for file in serverport_*.cfg; do
    # Extract the digits from the filename
    digits=$(echo "$file" | grep -o '[0-9]\{4,5\}')
    # Check if the digits are a valid port number
    if [[ $digits -ge 1024 && $digits -le 65535 ]]; then
        if sudo lsof -i :$digits; then
            port_list+=( $((digits)) )
        fi
    fi
done
echo "Valid port numbers found: ${port_list[@]}"
PORTS=$port_list
cd ~
# 创建一个ipset集合来存储被封禁的IP
ipset -exist create blocked_ip hash:ip timeout $TIMEOUT

# 将ipset集合添加到iptables规则中
iptables -I INPUT -m set --match-set blocked_ip src -j DROP
iptables -I OUTPUT -m set --match-set blocked_ip dst -j DROP

echo "===================================" >> $BLOCKED_IP_FILE
while true; do
    # 对每个端口执行tcpdump命令
    for PORT in "${PORTS[@]}"; do
        if [ ! -f /tmp/lockfile ]; then
            exit 1
        fi
        # 使用tcpdump捕获1秒内的流量，通过awk命令分析并找出数据包数量超过阈值的IP
        IP_LIST=$(timeout 1 tcpdump -i eth0 -n 'port '$PORT' and less 90'| awk '{print $3}' | cut -d. -f1-4 | sort | uniq -c | sort -nr | awk -v threshold=$THRESHOLD '$1 > threshold {print $2}')
        
        # 将超过阈值的IP添加到ipset集合进行封禁，同时保存到文本文件和日志文件中
        for IP in $IP_LIST; do
            # 检查IP是否合法
            if [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                # 检查IP是否已经在ipset中
                if ! ipset -test blocked_ip $IP > /dev/null 2>&1; then
                    ipset add blocked_ip $IP timeout $TIMEOUT
                    echo "Blocked IP: $IP"
                    echo $IP >> $BLOCKED_IP_FILE
                    # 记录封禁事件
                    echo "$(date) [BLOCKED] IP: $IP exceeded the threshold with more than $THRESHOLD packets per second" | tee -a $BLOCKED_IP_LOG
                fi
            else
                # 记录无效IP的日志
                echo "Invalid IP: $IP"
                echo "$(date) [INVALID] IP: $IP is not a valid IP address format" | tee -a $BLOCKED_IP_LOG
            fi
        done
    done
done

fi