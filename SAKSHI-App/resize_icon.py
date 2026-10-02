from PIL import Image

img = Image.open("/Applications/SAKSHI.app/Contents/Resources/MenuBarIconTemplate.png")

# Create a new blank 44x44 image
new_img = Image.new("RGBA", (44, 44), (0, 0, 0, 0))

# Resize original to 28x28 (much smaller)
smaller_img = img.resize((28, 28), Image.LANCZOS)

# Paste the smaller image into the center of the 44x44 canvas
offset_x = (44 - 28) // 2
offset_y = (44 - 28) // 2
new_img.paste(smaller_img, (offset_x, offset_y), smaller_img)

new_img.save("/Applications/SAKSHI.app/Contents/Resources/MenuBarIconTemplate.png")
