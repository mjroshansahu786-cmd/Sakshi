from PIL import Image

img = Image.open("/Users/roshan/.gemini/antigravity-ide/brain/4546fa8f-1225-4251-87db-1f322f3f8e5b/sakshi_menubar_icon_1790922124774.jpg").convert("RGBA")
data = img.getdata()

new_data = []
for item in data:
    if item[0] > 200 and item[1] > 200 and item[2] > 200:
        new_data.append((0, 0, 0, 0))
    else:
        new_data.append((0, 0, 0, 255))

img.putdata(new_data)
img = img.resize((44, 44), Image.LANCZOS)
img.save("MenuBarIconTemplate.png")
