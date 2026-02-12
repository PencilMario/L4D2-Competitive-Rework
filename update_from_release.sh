#!/bin/bash
echo "==================本次执行时间=================="
TZ=UTC-8 date
echo "==================开始执行=================="

gitrep=L4D2-Competitive-Rework
repo_owner="SirPlease"
release_dir="/tmp/l4d2_release"

echo "Downloading latest release...";
cd /tmp;

# 清理旧的release目录
rm -rf "$release_dir"
mkdir -p "$release_dir"

# 获取最新的release下载链接
# 尝试用jq，如果不存在就用python或grep
if command -v jq &> /dev/null; then
    latest_release=$(curl -s https://api.github.com/repos/$repo_owner/$gitrep/releases/latest | jq -r '.assets[0].browser_download_url')
elif command -v python3 &> /dev/null; then
    latest_release=$(curl -s https://api.github.com/repos/$repo_owner/$gitrep/releases/latest | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['assets'][0]['browser_download_url'] if data.get('assets') else '')")
else
    # 使用grep提取（最后的fallback）
    latest_release=$(curl -s https://api.github.com/repos/$repo_owner/$gitrep/releases/latest | grep -o '"browser_download_url": "[^"]*"' | head -1 | cut -d '"' -f 4)
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
unzip -q "$release_dir/release.zip" -d "$release_dir/"

# 找到解压后的项目目录（通常是 L4D2-Competitive-Rework）
project_path=$(find "$release_dir" -maxdepth 1 -type d -name "$gitrep" | head -1)

if [ -z "$project_path" ]; then
    echo "Failed to find project directory in release"
    exit 1
fi

directories=("/home/steam/Steam/steamapps/common/l4d2versus/left4dead2" "/home/steam/Steam/steamapps/common/l4d2/left4dead2")

for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then

        # 清理旧的文件
        # 其他文件残余内容短时间内应该不会影响 直接覆盖即可

        #rm -rf "$dir/addons/sourcemod/configs/"*
        #rm -rf "$dir/addons/sourcemod/data/"*
        #rm -rf "$dir/addons/sourcemod/gamedata/"*
        rm -rf "$dir/addons/sourcemod/plugins/"*
        #rm -rf "$dir/addons/sourcemod/translations/"*
        #rm -rf "$dir/scripts/vscripts/"*

        #rm -rf "$dir/cfg/cfgogl/"*
        #rm -rf "$dir/cfg/mixmap/"*
        #rm -rf "$dir/cfg/sourcemod/"*
        #rm -rf "$dir/cfg/stripper/"*
        rm -rf "$dir/cfg/spcontrol_server/"*

        # 从release版本复制文件
        \cp -r "$project_path/addons/sourcemod/configs/"* "$dir/addons/sourcemod/configs/";
        \cp -r "$project_path/addons/sourcemod/data/"* "$dir/addons/sourcemod/data/";
        \cp -r "$project_path/addons/sourcemod/gamedata/"* "$dir/addons/sourcemod/gamedata/";
        \cp -r "$project_path/addons/sourcemod/plugins/"* "$dir/addons/sourcemod/plugins/";
        \cp -r "$project_path/addons/sourcemod/translations/"* "$dir/addons/sourcemod/translations/";
        \cp -r "$project_path/scripts/"* "$dir/scripts/";
        \cp -r "$project_path/cfg/"* "$dir/cfg/";
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
