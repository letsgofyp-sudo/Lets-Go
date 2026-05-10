import os

new_screens_path = r"c:\Users\hp\Downloads\FYP_Latex1_Templete\new_screens.tex"
tex_path = r"c:\Users\hp\Downloads\FYP_Latex1_Templete\ch_5_implementation.tex"

with open(new_screens_path, "r", encoding='utf-8') as f:
    new_content = f.read()

with open(tex_path, "r", encoding='utf-8') as f:
    lines = f.readlines()

output_lines = []
inserted = False

for line in lines:
    if r"\subsection{Navigation Flow Diagram}" in line and not inserted:
        output_lines.append(new_content + "\n")
        inserted = True
    output_lines.append(line)

if inserted:
    with open(tex_path, "w", encoding='utf-8') as f:
        f.writelines(output_lines)
    print("Successfully inserted new screens into ch_5_implementation.tex")
else:
    print("Could not find insertion marker in ch_5_implementation.tex")
