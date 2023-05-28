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
        find "$dir" -type f -name "*.dem" -mmin +30 -exec 7z a {}.7z {} \;
        
        find "$dir" -type f -name "*.dem.7z" -exec mv {} "$destination" \;

        find "$dir" -type f -name "*.dem" -mmin +30 -exec rm -f {} \;


        echo "已压缩并移动 $dir 中的所有 .dem 文件到 $destination"
    else
        echo "目录 $dir 不存在"
    fi
done