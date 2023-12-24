#!/bin/bash

# 配置参数
THRESHOLD=30                          # 设置每秒允许的UDP请求的阈值
PACKET_SIZE=64                        # UDP数据包的最大长度限制
BAN_TIME=7200                         # 封禁IP的时间（秒）
INTERFACE="eth0"                      # 使用的网络接口名称                      # 需要监控的端口列表，使用逗号分隔
LOG_FILE="/home/steam/banned_ips.log"    # 记录封禁IP的日志文件路径
gitrep=L4D2-Competitive-Rework
# 指定要监控的端口
PORTS=()
cd /home/steam/$gitrep/cfg/spcontrol_server/;
for file in serverport_*.cfg; do
    # Extract the digits from the filename
    digits=$(echo "$file" | grep -o '[0-9]\{4,5\}')
    # Check if the digits are a valid port number
    if [[ $digits -ge 1024 && $digits -le 65535 ]]; then
        if sudo lsof -i :$digits; then
            PORTS+=( $((digits)) )
        fi
    fi
done
echo "Valid port numbers found: $PORTS"
port_s=$(printf "%s," "${PORTS[@]}")
PORTS=${port_s::-1}

# 检查ipset集合是否存在，如果不存在则创建
if ! sudo ipset list temp_ban &>/dev/null; then
    sudo ipset create temp_ban hash:ip timeout $BAN_TIME
fi

# 设置iptables规则，如果规则不存在，则添加规则来封禁在ipset集合中的IP地址
sudo iptables -C INPUT -p udp -m multiport --dports $PORTS -m set --match-set temp_ban src -j DROP 2>/dev/null ||
    sudo iptables -A INPUT -p udp -m multiport --dports $PORTS -m set --match-set temp_ban src -j DROP

# 构建tcpdump端口过滤器字符串
IFS=',' read -r -a ports_array <<< "$PORTS"
port_filter=""
for port in "${ports_array[@]}"; do
    port_filter="${port_filter} port ${port} or"
done
port_filter=${port_filter% or} # 移除最后的 "or"

# 使用tcpdump监控指定端口的UDP流量，只捕获长度小于等于64字节的数据包
sudo tcpdump -i "$INTERFACE" -nn -u -l "udp and (len <= $PACKET_SIZE) and ($port_filter)" 2>/dev/null |
sudo awk -v threshold="$THRESHOLD" -v ban_time="$BAN_TIME" -v log_file="$LOG_FILE" -v packet_size="$PACKET_SIZE" '
BEGIN {
    print "开始监控UDP数据包，数据包长度限制为 " packet_size " 字节。每秒请求数超过 " threshold " 的IP将被封禁。"
}
{
    if ($NF ~ /^length$/) {
        next;   # 跳过以 "length" 开头的行
    }

    # 提取源IP地址
    match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/, arr);
    src_ip = arr[0];

    # 获取当前的秒数
    current_sec = systime();

    # 为IP地址初始化计数器和时间戳
    if (!(src_ip in last_sec)) {
        last_sec[src_ip] = current_sec;
        count[src_ip] = 0;
    }
    
    # 如果当前秒数变化，重置对应IP地址的计数器
    if (last_sec[src_ip] != current_sec) {
        last_sec[src_ip] = current_sec;
        count[src_ip] = 0;
    }

    # 增加IP地址的数据包计数，并检查是否超过了阈值
    count[src_ip]++;
    if (count[src_ip] > threshold) {
        # 封禁IP地址
        system("ipset -exist add temp_ban " src_ip " timeout " ban_time);
        print strftime("[%Y-%m-%d %H:%M:%S] 封禁IP: ") src_ip >> log_file;
        count[src_ip] = 0; # 重置计数器
    }
}
'
