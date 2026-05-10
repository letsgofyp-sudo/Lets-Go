import re

file_path = r'c:\Users\hp\Downloads\FYP_Latex1_Templete\ch_5_implementation.tex'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Split the content into prefix, screens section, and suffix
# Section starts at \subsection{Screen-wise Implementation}
# Ends at \subsection{Navigation Flow Diagram}

start_marker = r'\subsection{Screen-wise Implementation}'
end_marker = r'\subsection{Navigation Flow Diagram}'

start_idx = content.find(start_marker) + len(start_marker)
end_idx = content.find(end_marker)

if start_idx == -1 or end_idx == -1:
    print("Markers not found")
    exit(1)

screens_section = content[start_idx:end_idx]

# Pattern to find each screen block
# A block starts with \subsubsection{Screen X: Title} and ends before the next \subsubsection or at the end of section
blocks = re.split(r'(\\subsubsection\{Screen \d+: [^\}]+\})', screens_section)

# blocks[0] should be empty or just whitespace/intro
# blocks[1] is header, blocks[2] is content, blocks[3] is header...
screen_blocks = {}
for i in range(1, len(blocks), 2):
    header = blocks[i]
    body = blocks[i+1]
    # Extract Screen Number
    match = re.search(r'Screen (\d+):', header)
    if match:
        num = int(match.group(1))
        screen_blocks[num] = (header, body)

# Approved Order (Original Numbers)
new_order = [
    69, 67, 24, 33, 75, 1, 21, 20, 19, 16, 15, 14, 12, 18, 13, 17, 35, 41, 40, 39, 3, 55, 59, 29, 44, 58, 4, 25, 54, 27, 5, 22, 36, 52, 53, 61, 23, 65, 63, 48, 74, 6, 7, 8, 9, 76
]

new_screens_content = blocks[0] # Intro text if any

for idx, old_num in enumerate(new_order, 1):
    if old_num not in screen_blocks:
        print(f"Warning: Screen {old_num} not found in file!")
        continue
    
    header, body = screen_blocks[old_num]
    # Update header number
    new_header = re.sub(r'Screen \d+:', f'Screen {idx}:', header)
    new_screens_content += new_header + body

# Replace the old section with the new one
new_content = content[:start_idx] + new_screens_content + content[end_idx:]

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"Successfully reordered {len(new_order)} screens.")
