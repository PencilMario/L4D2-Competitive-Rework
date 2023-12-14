import datetime

input_file_path = r'E:\GithubKu\L4D2-Competitive-Rework\Dedicated Server Install Guide\readplayers\players.log'
output_file_path = r'E:\GithubKu\L4D2-Competitive-Rework\Dedicated Server Install Guide\readplayers\playersip.log'

with open(input_file_path, 'r', encoding='utf-8') as file:
    with open(output_file_path, 'w', encoding='utf-8') as new_file:
        for line in file:
            if line[1:14] >= '20:00:00':
                new_file.write(line)