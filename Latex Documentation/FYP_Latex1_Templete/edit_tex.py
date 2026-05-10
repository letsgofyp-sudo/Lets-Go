import re

tex_path = r"c:\Users\hp\Downloads\FYP_Latex1_Templete\ch_5_implementation.tex"

with open(tex_path, "r", encoding='utf-8') as f:
    content = f.read()

# 1. Remove specific screens entirely.
screens_to_remove = [10, 11, 26, 37, 43, 51, 56, 68, 70, 71, 72, 73]
pattern_remove = r"\\subsubsection\{Screen (?:%s):.*?\}(.*?)(?=\\subsubsection|\\subsection|\\section|\Z)" % '|'.join(map(str, screens_to_remove))

content = re.sub(pattern_remove, "", content, flags=re.DOTALL)

# 2. Modify Screen 6
content = content.replace(r"\subsubsection{Screen 6: Admin Dashboard (Web)}", r"\subsubsection{Screen 6: SOS Live Tracking Dashboard}")
content = content.replace(r"\caption{Admin Dashboard (Web)}", r"\caption{SOS Live Tracking Dashboard}")

# 3. Modify Screen 53
content = content.replace(r"\subsubsection{Screen 53: Notifications Payment Confirmed}", r"\subsubsection{Screen 53: Ride Completion}")
content = content.replace(r"\caption{Notifications Payment Confirmed}", r"\caption{Ride Completion}")

# 4. Split images replacements
def replace_with_minipage(content, old_img_name, part1_name, part2_name, caption_text):
    # Regex to find the figure block for this image
    block_pattern = r"\\begin\{figure\}\[H\]\s*\\centering\s*\\includegraphics\[.*?\]\{assets/app screenshot/" + old_img_name + r"\}\s*\\caption\{" + caption_text + r"\}\s*\\end\{figure\}"
    
    new_block = f"""\\begin{{figure}}[H]
\\centering
\\begin{{minipage}}{{0.45\\textwidth}}
\\centering
\\includegraphics[width=\\textwidth,keepaspectratio]{{assets/app screenshot/{part1_name}}}
\\end{{minipage}}\\hfill
\\begin{{minipage}}{{0.45\\textwidth}}
\\centering
\\includegraphics[width=\\textwidth,keepaspectratio]{{assets/app screenshot/{part2_name}}}
\\end{{minipage}}
\\caption{{{caption_text}}}
\\end{{figure}}"""
    
    return re.sub(block_pattern, new_block.replace('\\', r'\\'), content)

# But wait, Screen 3 doesn't use the exact same caption format. Let's just do a generic replace.
def replace_img_with_split(content, old_img, new_img1, new_img2):
    old_line = r"\\includegraphics[width=0.3\\textwidth,keepaspectratio,height=0.8\\textheight]{assets/app screenshot/" + old_img + r"}"
    new_lines = f"""\\begin{{minipage}}{{0.48\\textwidth}}
\\centering
\\includegraphics[width=\\textwidth,keepaspectratio]{{assets/app screenshot/{new_img1}}}
\\end{{minipage}}\\hfill
\\begin{{minipage}}{{0.48\\textwidth}}
\\centering
\\includegraphics[width=\\textwidth,keepaspectratio]{{assets/app screenshot/{new_img2}}}
\\end{{minipage}}"""
    return content.replace(old_line.replace('\\', ''), new_lines)

# Manual replaces instead for exact line matching
content = content.replace(
    r"\includegraphics[width=0.3\textwidth,keepaspectratio,height=0.8\textheight]{assets/app screenshot/ride_details.jpeg}",
    r"""\begin{minipage}{0.48\textwidth}
\centering
\includegraphics[width=\textwidth,keepaspectratio]{assets/app screenshot/ride_details_part1.jpeg}
\end{minipage}\hfill
\begin{minipage}{0.48\textwidth}
\centering
\includegraphics[width=\textwidth,keepaspectratio]{assets/app screenshot/ride_details_part2.jpeg}
\end{minipage}"""
)

content = content.replace(
    r"\includegraphics[width=0.3\textwidth,keepaspectratio,height=0.8\textheight]{assets/app screenshot/my_profile_verified_driver.jpeg}",
    r"""\begin{minipage}{0.48\textwidth}
\centering
\includegraphics[width=\textwidth,keepaspectratio]{assets/app screenshot/my_profile_verified_driver_part1.jpeg}
\end{minipage}\hfill
\begin{minipage}{0.48\textwidth}
\centering
\includegraphics[width=\textwidth,keepaspectratio]{assets/app screenshot/my_profile_verified_driver_part2.jpeg}
\end{minipage}"""
)

content = content.replace(
    r"\includegraphics[width=0.3\textwidth,keepaspectratio,height=0.8\textheight]{assets/app screenshot/registration_pending_full_details.jpeg}",
    r"""\begin{minipage}{0.48\textwidth}
\centering
\includegraphics[width=\textwidth,keepaspectratio]{assets/app screenshot/registration_pending_full_details_part1.jpeg}
\end{minipage}\hfill
\begin{minipage}{0.48\textwidth}
\centering
\includegraphics[width=\textwidth,keepaspectratio]{assets/app screenshot/registration_pending_full_details_part2.jpeg}
\end{minipage}"""
)

with open(tex_path, "w", encoding='utf-8') as f:
    f.write(content)

print("Modifications applied successfully.")
