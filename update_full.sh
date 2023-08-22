#!/bin/bash

# github存储库名称
gitrep=L4D2-Competitive-Rework

echo "Get Plugin updates";
cd /home/steam/$gitrep/;
git reset --hard;
git pull --rebase;
git status;

directories=("/home/steam/Steam/steamapps/common/l4d2versus/left4dead2" "/home/steam/Steam/steamapps/common/l4d2/left4dead2")

for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then

        ../steamcmd.sh +force_install_dir $dir +login anonymous +app_update 222860 validate +quit


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

        \cp -rp /home/steam/$gitrep/* "$dir/";
        chmod 777 "$dir/"

        echo "Updated | $dir"
    else
        echo "Unexist | $dir "
    fi
done
echo "File Copy Success";

echo "==================当前commit=================="
git log -1
echo "================== 运行结束 =================="

