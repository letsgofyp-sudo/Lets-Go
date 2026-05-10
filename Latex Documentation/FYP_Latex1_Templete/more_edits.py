from PIL import Image
import os
import re

image_dir = r"c:\Users\hp\Downloads\FYP_Latex1_Templete\assets\app screenshot"

def split_image(filename):
    filepath = os.path.join(image_dir, filename)
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        return
    
    img = Image.open(filepath)
    width, height = img.size
    
    top_half = img.crop((0, 0, width, height // 2))
    bottom_half = img.crop((0, height // 2, width, height))
    
    base, ext = os.path.splitext(filename)
    part1_path = os.path.join(image_dir, f"{base}_part1{ext}")
    part2_path = os.path.join(image_dir, f"{base}_part2{ext}")
    
    if top_half.mode in ("RGBA", "P"):
        top_half = top_half.convert("RGB")
    if bottom_half.mode in ("RGBA", "P"):
        bottom_half = bottom_half.convert("RGB")
        
    top_half.save(part1_path)
    bottom_half.save(part2_path)
    print(f"Successfully split {filename}")

# Split the required images
split_image("driver_ride_details_pending.jpeg")
split_image("profile_general_info.jpeg")

tex_path = r"c:\Users\hp\Downloads\FYP_Latex1_Templete\ch_5_implementation.tex"

with open(tex_path, "r", encoding='utf-8') as f:
    content = f.read()

# 1. Remove line 4 and 5 from Ride Details Screen
content = content.replace(r'4. On "Request Ride", a booking request is created (POST to /api/bookings).\n', "")
content = content.replace(r'5. User sees confirmation and waits for driver acceptance\n', "")
# In case the newlines are slightly different
content = re.sub(r'\\item On "Request Ride".*?\n', '', content)
content = re.sub(r'\\item User sees confirmation.*?\n', '', content)

# 2. Split Driver Ride Details Pending
def replace_img_with_split(content, old_img, new_img1, new_img2):
    old_line = r"\\includegraphics[width=0.3\\textwidth,keepaspectratio,height=0.8\\textheight]{assets/app screenshot/" + old_img + r"}"
    new_lines = f"""\\begin{{minipage}}{{0.45\\textwidth}}
\\centering
\\includegraphics[width=\\textwidth,keepaspectratio]{{assets/app screenshot/{new_img1}}}
\\end{{minipage}}\\hfill
\\begin{{minipage}}{{0.45\\textwidth}}
\\centering
\\includegraphics[width=\\textwidth,keepaspectratio]{{assets/app screenshot/{new_img2}}}
\\end{{minipage}}"""
    return content.replace(old_line.replace('\\', ''), new_lines)

content = replace_img_with_split(content, "driver_ride_details_pending.jpeg", "driver_ride_details_pending_part1.jpeg", "driver_ride_details_pending_part2.jpeg")

# 3. Remove Login Screen Alt complete section
# Find the subsubsection that contains login_screen_alt.jpeg. Its label is likely Screen ~8-15
pattern_login_alt = r"\\subsubsection\{Screen \d+: Login Screen Alt\}(.*?)(?=\\subsubsection|\\subsection|\\section|\Z)"
content = re.sub(pattern_login_alt, "", content, flags=re.DOTALL)

# 4. Reduce size of My Profile Verified Driver
# Since it was already split, its current latex looks like:
# \includegraphics[width=\textwidth,keepaspectratio]{assets/app screenshot/my_profile_verified_driver_part1.jpeg} inside a minipage of 0.48\textwidth
my_profile_pattern = r"(\\begin\{minipage\})\{0.48\\textwidth\}(\s*\\centering\s*\\includegraphics\[width=\\textwidth,keepaspectratio\]\{assets/app screenshot/my_profile_verified_driver_part1\.jpeg\}\s*\\end\{minipage\}\\hfill\s*\\begin\{minipage\})\{0.48\\textwidth\}(\s*\\centering\s*\\includegraphics\[width=\\textwidth,keepaspectratio\]\{assets/app screenshot/my_profile_verified_driver_part2\.jpeg\}\s*\\end\{minipage\})"
content = re.sub(my_profile_pattern, r"\1{0.35\\textwidth}\2{0.35\\textwidth}\3", content)

# 5. Split Profile General Info horizontally
content = replace_img_with_split(content, "profile_general_info.jpeg", "profile_general_info_part1.jpeg", "profile_general_info_part2.jpeg")

# 6. Remove "2. User interacts with the components to complete the task." near Profile General Info
profile_info_section = re.search(r"\\subsubsection\{Screen \d+: Profile General Info\}(.*?)(?=\\begin\{figure\})", content, re.DOTALL)
if profile_info_section:
    new_sec = profile_info_section.group(0).replace(r"\item User interacts with the components to complete the task.", "")
    content = content.replace(profile_info_section.group(0), new_sec)

with open(tex_path, "w", encoding='utf-8') as f:
    f.write(content)

print("Modifications applied successfully.")
