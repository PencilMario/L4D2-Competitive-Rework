import json
data = []

data.append(("42.192.4.35",42300))
data.append(("114.132.67.124",26210))
data.append(("sp.0721play.icu",20721))
data.append(("sp.0721play.icu",40721))


with open('nb_servers.json', 'w', encoding = 'utf-8') as files:
    files.write(json.dumps(data))