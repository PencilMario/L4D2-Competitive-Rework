import re

def extract_ipv4(line):
    ipv4_regex = r"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b"
    return re.findall(ipv4_regex, line)

def save_unique_ipv4_lines(input_file_path, output_file_path):
    unique_ipv4_lines = set()
    with open(input_file_path, "r", encoding='utf-8') as input_file, open(output_file_path, "a", encoding='utf-8') as output_file:
        for line in input_file:
            ipv4_addresses = extract_ipv4(line)
            if ipv4_addresses:
                for ipv4_address in ipv4_addresses:
                    if ipv4_address not in unique_ipv4_lines:
                        unique_ipv4_lines.add(ipv4_address)
                        output_file.write(line)
                        break
    print(f"Unique IPv4 lines saved to {output_file_path}")

input_file_path = r"E:\GithubKu\L4D2-Competitive-Rework\Dedicated Server Install Guide\readplayers\datas.log"
output_file_path = r"E:\GithubKu\L4D2-Competitive-Rework\Dedicated Server Install Guide\readplayers\players.log"
save_unique_ipv4_lines(input_file_path, output_file_path)