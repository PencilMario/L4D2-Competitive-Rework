import vdf, os, sys, time
import find_steamloc
import requests
import socket
SV = "https://releases.0721play.top/https://raw.githubusercontent.com/PencilMario/L4D2-Competitive-Rework/master/nb_servers.json"
servers = []

data = []


def convert_to_ip(address):
    try:
        ip = socket.gethostbyname(address)
        return ip
    except socket.gaierror:
        try:
            socket.inet_aton(address)
            return address
        except socket.error:
            raise ValueError("Invalid input: {}".format(address))
def exit():
    print("按下回车键退出")
    input()
    sys.exit(0)

def insert_to_fav(addres,data):
    for i in data["Filters"]["favorites"]:
        if data["Filters"]["favorites"][i]["address"] == addres:
            return
    for i in range(1, 512):
        i = str(i)
        if i not in data["Filters"]["favorites"]:
            data["Filters"]["favorites"][i] = {}
            data["Filters"]["favorites"][i]["name"] = addres
            data["Filters"]["favorites"][i]["address"] = addres
            data["Filters"]["favorites"][i]["LastPlayed"] = int(time.time())
            data["Filters"]["favorites"][i]["appid"] = 0
            data["Filters"]["favorites"][i]["accountid"] = 0
            return
            
print("本程序将自动将NB组服务器添加到服务器收藏列表中")
print("这将影响所有在本机登录过的steam账号")
print("部分服不定期更换ip, 届时需要重新执行本程序")
print("你可以在 https://github.com/PencilMario/L4D2-Competitive-Rework/actions 下载最新构建")
print("按下回车键继续...")
input()

PATH = find_steamloc.get_steam_root_directory()["Possible Locations"]
if PATH == "None":
    print("无法找到steam根目录, sorry, 程序无法继续执行")
    exit()
PATH = os.path.join(PATH, "userdata")

try:
    response = requests.get(SV)
except Exception:
    print("获取服务器列表失败，请不要开启梯子")
    exit()


data = response.json()
files = os.listdir(PATH)
for vdfp in files:
    vdff = os.path.join(PATH, vdfp, "7", "remote", "serverbrowser_hist.vdf")
    print(vdff)
    if os.path.exists(vdff):
        vdfdata = vdf.load(open(vdff))
    else:
        print("文件不存在!")
        continue
    for i in data:
        try:
            i[0] = convert_to_ip(i[0])
            insert_to_fav("{}:{}".format(i[0], i[1]), vdfdata)
            print(i)
        except Exception as e:
            print("处理失败: {} {}",format(i, str(e)))
    
    vdf.dump(vdfdata, open(vdff, "w"), pretty=True)


print("处理完成!")
exit()