#!/bin/bash

echo "==================自定义配置执行=================="

# 定义游戏目录
directories=("/home/steam/Steam/steamapps/common/l4d2versus/left4dead2" "/home/steam/Steam/steamapps/common/l4d2/left4dead2")

# 定义数据文件夹
data_dir="$HOME/l4d2_custom_config"

echo "数据文件夹: $data_dir"

# 创建数据文件夹和游戏对应的文件夹结构（如果不存在）
mkdir -p "$data_dir"

# 初始化游戏对应的文件夹结构
game_subdirs=("addons" "cfg" "scripts" "sound" "models" "logs")

for subdir in "${game_subdirs[@]}"; do
    subdir_path="$data_dir/$subdir"
    if [ ! -d "$subdir_path" ]; then
        mkdir -p "$subdir_path"
        echo "创建文件夹: $subdir_path"
    fi
done

echo ""
echo "==================复制自定义配置到游戏目录=================="

# 将自定义配置复制到游戏目录中（使用 -n 参数不覆盖已有文件）
for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then
        echo "正在处理游戏目录: $dir"

        # 递归复制文件，覆盖已存在的文件
        # -r: 递归  -p: 保留属性  -f: 覆盖已存在文件
        if cp -rpf "$data_dir/"* "$dir/" 2>/dev/null; then
            echo "✓ 复制完成: $dir"
        else
            echo "⚠ 复制时出现警告: $dir"
        fi
    else
        echo "✗ 游戏目录不存在: $dir"
    fi
done

echo ""
echo "==================自定义配置执行完成=================="
echo "提示: 在 $data_dir 中添加游戏配置文件，下次运行时会自动复制到游戏目录"
