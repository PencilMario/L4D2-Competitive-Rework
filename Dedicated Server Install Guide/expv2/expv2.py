import re, csv

def parse_log_line(line):
    # 解析日志中的玩家数据并返回一个字典
    regex = r"Total: (\d+), gametime: (\d+), rankpoint: (\d+), shotgunkills: (\d+), smgkills:(\d+), tankrocks: (\d+), versuswin: (\d+), versustotal: (\d+)"
    match = re.search(regex, line)
    if match:
        return {
            "total": int(match.group(1)),
            "gametime": int(match.group(2)),
            "rankpoint": int(match.group(3)),
            "shotgunkills": int(match.group(4)),
            "smgkills": int(match.group(5)),
            "tankrocks": int(match.group(6)),
            "versuswin": int(match.group(7)),
            "versustotal": int(match.group(8))
        }

def read_player_info(file_path):
    players = []
    with open(file_path, 'r') as file:
        for line in file:
            player_data = parse_log_line(line)
            if player_data:
                players.append(player_data)
    return players
file_path = 'E:\GithubKu\L4D2-Competitive-Rework\Dedicated Server Install Guide\expv2\exp_interface.log'

players = read_player_info(file_path)
for player in players:
    print(player)
# 制定文件路径
with open("data.csv", 'w', newline="") as file:
    writer = csv.DictWriter(file, fieldnames=['total', 'gametime', 'rankpoint', 'shotgunkills', 'smgkills', 'tankrocks', 'versuswin', 'versustotal'])
    writer.writeheader()
    for i in players:
        writer.writerow(i)
    
    

    
