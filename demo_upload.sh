#!/bin/bash
# Replace with your directories
directories=("/home/steam/Steam/steamapps/common/l4d2versus/left4dead2" "/home/steam/Steam/steamapps/common/l4d2/left4dead2")
destination="/mnt/webdav"
#for i in "${!directories[@]}"; do directories[$i]="${directories[$i]}/addons"; done

# Check if davfs is mounted
if ! mountpoint -q /mnt/webdav; then
    echo "WebDAV share is not mounted"
    exit 1
fi

# 循环遍历directories数组中的每个目录
for dir in "${directories[@]}"
do
    # 检查目录是否存在
    if [ -d "$dir" ]
    then
        # 压缩目录中的所有 .dem 文件为 zip 文件
        find "$dir" -type f -name "*.dem" -mmin +30 -exec zip -j {}.zip {} \;
        
        # 移动压缩后的文件到目标目录，并删除原始的 .dem 文件
        find "$dir" -type f -name "*.dem" -mmin +30 -exec sh -c 'mv "$1.zip" "$destination" && rm "$1"' sh {} \;

        echo "已移动 $dir 中的所有 .dem 文件到 $destination"
    else
        echo "目录 $dir 不存在"
    fi
done