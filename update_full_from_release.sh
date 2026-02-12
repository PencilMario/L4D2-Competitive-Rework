#!/bin/bash
echo "==================本次执行时间=================="
TZ=UTC-8 date
echo "==================开始执行=================="

# github存储库信息
gitrep=L4D2-Competitive-Rework
repo_owner="PencilMario"
release_dir="/tmp/l4d2_release"

sudo iptables -F
sudo iptables -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

echo "Downloading latest release...";
cd /tmp;

# 清理旧的release目录
rm -rf "$release_dir"
mkdir -p "$release_dir"

# 获取最新的release下载链接
# 尝试用jq，如果不存在就用python或grep
if command -v jq &> /dev/null; then
    latest_release=$(curl -s https://releases.0721play.top/https://api.github.com/repos/$repo_owner/$gitrep/releases/latest | jq -r '.assets[0].browser_download_url')
elif command -v python3 &> /dev/null; then
    latest_release=$(curl -s https://releases.0721play.top/https://api.github.com/repos/$repo_owner/$gitrep/releases/latest | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['assets'][0]['browser_download_url'] if data.get('assets') else '')")
else
    # 使用grep提取（最后的fallback）
    latest_release=$(curl -s https://releases.0721play.top/https://api.github.com/repos/$repo_owner/$gitrep/releases/latest | grep -o '"browser_download_url": "[^"]*"' | head -1 | cut -d '"' -f 4)
fi

if [ -z "$latest_release" ] || [ "$latest_release" == "null" ]; then
    echo "Failed to get latest release URL"
    exit 1
fi

echo "Downloading from: $latest_release"
wget -q -O "$release_dir/release.zip" "$latest_release"

if [ ! -f "$release_dir/release.zip" ]; then
    echo "Failed to download release"
    exit 1
fi

echo "Extracting release...";

# 尝试使用unzip或python来解压
if command -v unzip &> /dev/null; then
    unzip -q "$release_dir/release.zip" -d "$release_dir/"
elif command -v python3 &> /dev/null; then
    python3 << 'EOF'
import zipfile
import sys
try:
    with zipfile.ZipFile("/tmp/l4d2_release/release.zip", 'r') as zip_ref:
        zip_ref.extractall("/tmp/l4d2_release/")
    print("Extraction completed")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
else
    echo "Error: Neither unzip nor python3 found. Cannot extract release."
    exit 1
fi

# 找到解压后的项目目录
project_path=$(find "$release_dir" -maxdepth 1 -type d -name "$gitrep" | head -1)

if [ -z "$project_path" ]; then
    echo "Failed to find project directory in release"
    exit 1
fi

directories=("/home/steam/Steam/steamapps/common/l4d2versus/left4dead2" "/home/steam/Steam/steamapps/common/l4d2/left4dead2")

for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then

        sudo timedatectl set-timezone Asia/Shanghai
        ../steamcmd.sh +force_install_dir ${dir%/left4dead2} +login anonymous +app_update 222860 validate +quit

        echo ""
        find "$dir/addons/sourcemod/" \
            ! -path "$dir/addons/sourcemod/logs*" \
            ! -path "$dir/addons/sourcemod/configs/admins_simple.ini" \
            ! -path "$dir/addons/sourcemod/configs/sourcebans*" \
            ! -path "$dir/addons/sourcemod/configs/databases.cfg" \
            ! -path "$dir/addons/sourcemod/data/music_mapstart.txt" \
            -type f -delete
        find $dir/addons/sourcemod/logs* -type f -mtime +14 -delete
        find $dir/logs* -type f -mtime +14 -delete
        rm -rf "$dir/addons/metamod/"*
        rm -rf "$dir/addons/l4dtoolz/"*
        rm -rf "$dir/addons/stripper/"*
        rm -rf "$dir/scripts/vscripts/"*
        rm -rf "$dir/models/player/custom_player/"*
        rm -rf "$dir/sound/kodua/fortnite_emotes/"*
        # 剩下三个cfg应该不会被删除
        find "$dir/cfg/cfgogl/" \
            ! -path "$dir/cfg/cfgogl/promod" \
            -type f -delete
        rm -rf "$dir/cfg/mixmap/"*
        rm -rf "$dir/cfg/sourcemod/"*
        rm -rf "$dir/cfg/stripper/"*

        rm -f "$dir/l4dtoolz.dll"
        rm -f "$dir/l4dtoolz.so"
        rm -f "$dir/l4dtoolz.vdf"
        rm -f "$dir/metamod.vdf"

        # 从release版本复制所有文件
        \cp -rp "$project_path/"* "$dir/";
        chmod 777 "$dir/"

        echo "Updated | $dir"
    else
        echo "Unexist | $dir "
    fi
done

echo "File Copy Success";

echo "==================清理临时文件=================="
rm -rf "$release_dir"

echo "==================Release 信息=================="
echo "Latest Release: $latest_release"

echo "================== 运行结束 =================="
