import os

image_dir = r"c:\Users\hp\Downloads\FYP_Latex1_Templete\assets\app screenshot"
all_files = [f for f in os.listdir(image_dir) if f.endswith('.jpeg') or f.endswith('.png')]

# Exclude already used or soon-to-be-updated manually
exclude_files = [
    "login_screen.jpeg",
    "passenger_dashboard.jpeg",
    "ride_details.jpeg",
    "live_ride_tracking.jpeg",  # Will use for screen 4
    "chat_screen.jpeg",
    "admin_dashboard_sos.png"
]

files_to_add = [f for f in all_files if f not in exclude_files]

# Sort alphabetically to look nice
files_to_add.sort()

def make_title(filename):
    name = filename.replace('.jpeg', '').replace('.jpg', '').replace('.png', '').replace('_', ' ').title()
    return name

latex_str = ""
screen_num = 7
for f in files_to_add:
    title = make_title(f)
    latex_str += f"\\subsubsection{{Screen {screen_num}: {title}}}\n\n"
    latex_str += f"\\textbf{{Purpose:}} Provides the interface for {title.lower()}.\n\n"
    latex_str += "\\textbf{Components:}\n\\begin{itemize}\n"
    latex_str += f"    \\item Standard UI elements for {title.lower()}.\n"
    latex_str += "    \\item Navigation and action buttons.\n\\end{itemize}\n\n"
    latex_str += "\\textbf{Functional Flow:}\n\\begin{enumerate}\n"
    latex_str += f"    \\item User navigates to the {title} screen.\n"
    latex_str += f"    \\item User interacts with the components to complete the task.\n"
    latex_str += "\\end{enumerate}\n\n"
    latex_str += "\\begin{figure}[H]\n\\centering\n"
    latex_str += f"\\includegraphics[width=0.3\\textwidth,keepaspectratio,height=0.8\\textheight]{{assets/app screenshot/{f}}}\n"
    latex_str += f"\\caption{{{title}}}\n\\end{{figure}}\n\n"
    screen_num += 1

with open(r"c:\Users\hp\Downloads\FYP_Latex1_Templete\new_screens.tex", "w", encoding='utf-8') as outfile:
    outfile.write(latex_str)

print("Generated new_screens.tex successfully.")
