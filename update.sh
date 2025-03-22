#!/bin/bash
echo "==================本次执行时间=================="
TZ=UTC-8 date
echo "==================开始执行=================="

gitrep=L4D2-Competitive-Rework

echo "Get Plugin updates";
cd /home/steam/$gitrep/;
git reset --hard;
git pull --rebase;
git status;

directories=("/home/steam/Steam/steamapps/common/l4d2versus/left4dead2" "/home/steam/Steam/steamapps/common/l4d2/left4dead2")

for dir in "${directories[@]}"; do
    if [ -d "$dir" ]; then

        # 可以热更新的内容
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
        
        \cp -r /home/steam/$gitrep/addons/sourcemod/configs/* "$dir/addons/sourcemod/configs/";
        \cp -r /home/steam/$gitrep/addons/sourcemod/data/* "$dir/addons/sourcemod/data/";
        \cp -r /home/steam/$gitrep/addons/sourcemod/gamedata/* "$dir/addons/sourcemod/gamedata/";
        \cp -r /home/steam/$gitrep/addons/sourcemod/plugins/* "$dir/addons/sourcemod/plugins/";
        \cp -r /home/steam/$gitrep/addons/sourcemod/translations/* "$dir/addons/sourcemod/translations/";
        \cp -r /home/steam/$gitrep/scripts/* "$dir/scripts/";
        \cp -r /home/steam/$gitrep/cfg/* "$dir/cfg/";
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