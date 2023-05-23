#!/bin/bash

cd /home/steam/L4D2-Competitive-Rework/;

# Replace with your WebDAV URL
url="http://124.223.61.164:22102/dav/"

# Replace with your WebDAV username
username="versus"

# Replace with your WebDAV password
password="0578"

sudo apt-get install davfs2 -y

mkdir /mnt/webdav
# Mount the WebDAV share
sudo mount -t davfs -o uid=0,gid=0 $url /mnt/webdav

# Enter the username and password when prompted
echo "$url $username $password" > /etc/davfs2/secrets
chmod 600 /etc/davfs2/secrets

bash demo_upload.sh


# Unmount the WebDAV share when finished
#sudo umount /mnt/webdav