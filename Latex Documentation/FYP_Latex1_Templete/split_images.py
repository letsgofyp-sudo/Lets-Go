from PIL import Image
import os

image_dir = r"c:\Users\hp\Downloads\FYP_Latex1_Templete\assets\app screenshot"

def split_image(filename):
    filepath = os.path.join(image_dir, filename)
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        return
    
    img = Image.open(filepath)
    width, height = img.size
    
    # Split horizontally (top and bottom half)
    top_half = img.crop((0, 0, width, height // 2))
    bottom_half = img.crop((0, height // 2, width, height))
    
    base, ext = os.path.splitext(filename)
    part1_path = os.path.join(image_dir, f"{base}_part1{ext}")
    part2_path = os.path.join(image_dir, f"{base}_part2{ext}")
    
    # Convert RGBA to RGB for JPEG saving if necessary
    if top_half.mode in ("RGBA", "P"):
        top_half = top_half.convert("RGB")
    if bottom_half.mode in ("RGBA", "P"):
        bottom_half = bottom_half.convert("RGB")
        
    top_half.save(part1_path)
    bottom_half.save(part2_path)
    print(f"Successfully split {filename} into {base}_part1{ext} and {base}_part2{ext}")

split_image("ride_details.jpeg")
split_image("my_profile_verified_driver.jpeg")
split_image("registration_pending_full_details.jpeg")
