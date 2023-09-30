import json
data = []

data.append(("dx1.nekoyun.cn",34105))
data.append(("dx1.nekoyun.cn",34106))
data.append(("dx1.nekoyun.cn",34107))
data.append(("dx1.nekoyun.cn",34108))
data.append(("dx1.nekoyun.cn",34109))
data.append(("dx1.nekoyun.cn",34110))
data.append(("sq.xubw.cn",28013))
data.append(("sq.xubw.cn",28014))


with open('nb_servers.json', 'w', encoding = 'utf-8') as files:
    files.write(json.dumps(data))