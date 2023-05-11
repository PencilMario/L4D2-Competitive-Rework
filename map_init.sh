#!/bin/bash

cd /home/steam/L4D2-Competitive-Rework/;

# Replace with your WebDAV URL
url="http://sp2.0721play.icu/dav/"

# Replace with your WebDAV username
username="versus"

# Replace with your WebDAV password
password="0578"

sudo apt-get install davfs2

# Mount the WebDAV share
sudo mount -t davfs -o uid=$UID,gid=$GROUPS $url /mnt/webdav

# Enter the username and password when prompted
echo "$url $username $password" > ~/.davfs2/secrets
chmod 600 ~/.davfs2/secrets

sh map_sync.sh

# Unmount the WebDAV share when finished
sudo umount /mnt/webdav