#!/bin/bash

# Replace with your directories
directories=("/home/steam/Steam/steamapps/common/l4d2versus/left4dead2" "/home/steam/Steam/steamapps/common/l4d2/left4dead2")

# Check if davfs is mounted
if ! mountpoint -q /mnt/webdav; then
    echo "WebDAV share is not mounted"
    exit 1
fi

# Copy all .vpk files from the WebDAV share to the directories
for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then
        echo "Copying .vpk files to $dir"
        cp /mnt/webdav/*.vpk "$dir"
    else
        echo "$dir does not exist"
    fi
done

# Delete .vpk files in directories that are not found in the WebDAV share
for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then
        echo "Deleting .vpk files not found in WebDAV share in $dir"
        cd "$dir"
        find . -maxdepth 1 -type f -name "*.vpk" | while read file; do
            if [ ! -f "/mnt/webdav/$file" ]; then
                echo "Deleting $file"
                rm "$file"
            fi
        done
    else
        echo "$dir does not exist"
    fi
done

echo "Done!"