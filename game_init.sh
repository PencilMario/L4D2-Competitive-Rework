wget http://media.steampowered.com/installer/steamcmd_linux.tar.gz
tar -xvzf steamcmd_linux.tar.gz

mkdir -r "/home/steam/Steam/steamapps/common/l4d2/left4dead2"

gitrep=L4D2-Competitive-Rework

echo "Install Game";
cd /home/steam/$gitrep/;

bash update_full.sh