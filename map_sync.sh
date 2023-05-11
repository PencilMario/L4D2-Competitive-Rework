#!/bin/bash
# Replace with your directories
directories=("/home/steam/Steam/steamapps/common/l4d2versus/left4dead2" "/home/steam/Steam/steamapps/common/l4d2/left4dead2")

for i in "${!directories[@]}"; do directories[$i]="${directories[$i]}/addons"; done

# Check if davfs is mounted
if ! mountpoint -q /mnt/webdav; then
    echo "WebDAV share is not mounted"
    exit 1
fi

# Copy all .vpk files from the WebDAV share to the directories
for dir in "${directories[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "$dir does not exist, skipping"
        continue
    fi

    echo "Copying .vpk files to $dir"
    for file in /mnt/webdav/*.vpk; do
        filename=$(basename "$file")
        destination="$dir/$filename"
        
        if [ -f "$destination" ]; then
            # Check if the file sizes are different
            source_size=$(stat -c %s "$file")
            destination_size=$(stat -c %s "$destination")
            if [ "$source_size" != "$destination_size" ]; then
                echo "Overwriting $destination"
                cp "$file" "$destination"
            else
                echo "Skipping $destination (same file size)"
            fi
        else
            cp "$file" "$destination"
        fi
    done
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