import re

tex_path = r"c:\Users\hp\Downloads\FYP_Latex1_Templete\ch_5_implementation.tex"

with open(tex_path, "r", encoding='utf-8') as f:
    content = f.read()

# Remove the section for Screen 66
# It has subsubsection Screen 66: Registration Pending Full Details
pattern = r"\\subsubsection\{Screen \d+: Registration Pending Full Details\}(.*?)(?=\\subsubsection|\\subsection|\\section|\Z)"

new_content, count = re.subn(pattern, "", content, flags=re.DOTALL)

with open(tex_path, "w", encoding='utf-8') as f:
    f.write(new_content)

print(f"Removed {count} sections successfully.")
