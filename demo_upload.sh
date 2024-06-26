#!/bin/bash

cd /home/steam/L4D2-Competitive-Rework/;

# Replace with your WebDAV URL
url="http://124.223.61.164:22102/dav/"

# Replace with your WebDAV username
username="versus"

# Replace with your WebDAV password
password="0578"

# Replace with your directories
directories=("/home/steam/Steam/steamapps/common/l4d2versus/left4dead2" "/home/steam/Steam/steamapps/common/l4d2/left4dead2")
destination="/mnt/webdav"

mkdir /mnt/webdav
# Mount the WebDAV share
sudo mount -t davfs -o uid=0,gid=0 $url /mnt/webdav

# Enter the username and password when prompted
echo "$url $username $password" > /etc/davfs2/secrets
chmod 600 /etc/davfs2/secrets

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


# Unmount the WebDAV share when finished
sudo umount /mnt/webdav