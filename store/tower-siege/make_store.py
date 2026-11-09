# Makes Tower Siege's store screenshots (1080x1920, a caption over each) and its feature
# graphic (1024x500) from screenshots the game takes of itself:
#   for w in home level:22 level:15 preview:9 win looks event levels; do
#     GFX=high xvfb-run -a -s "-screen 0 1280x2000x24" godot --path tower-siege-godot \
#       --rendering-driver opengl3 -s tests/look.gd -- SHOTS_DIR $w 1080 1920; done
#   python3 store/tower-siege/make_store.py SHOTS_DIR store/tower-siege tower-siege-godot/assets/fonts/Fredoka-Bold.ttf
import sys
from PIL import Image, ImageDraw, ImageFont
src, out, font_path = sys.argv[1], sys.argv[2], sys.argv[3]
shots = [
    ("godot-level-22.png", "Drag roads. Send your army.", "#2d7be0"),
    ("godot-level-15.png", "11 hand-made boss battles", "#d9443a"),
    ("godot-preview-9.png", "See what it takes to win", "#2fa84f"),
    ("godot-home.png", "60 levels + endless mode", "#2d7be0"),
    ("godot-event.png", "Weekend events, unique prizes", "#e08a1e"),
    ("godot-win.png", "Win stars, coins and rewards", "#7a4fd8"),
    ("godot-looks.png", "Dress up your army", "#2fa84f"),
    ("godot-levels.png", "Fight across 12 chapters", "#d9443a"),
]
W, H, band = 1080, 1920, 250
for i, (f, text, color) in enumerate(shots, 1):
    canvas = Image.new("RGB", (W, H), color)
    d = ImageDraw.Draw(canvas)
    size = 92
    font = ImageFont.truetype(font_path, size)
    while d.textlength(text, font=font) > W - 100:
        size -= 4
        font = ImageFont.truetype(font_path, size)
    tw = d.textlength(text, font=font)
    y = (band - size) // 2 - 6
    d.text(((W - tw) / 2 + 4, y + 6), text, font=font, fill=(0, 0, 0, 90))
    d.text(((W - tw) / 2, y), text, font=font, fill="white")
    shot = Image.open(f"{src}/{f}").convert("RGB")
    sh = H - band - 50
    sw = round(shot.width * sh / shot.height)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw, sh), radius=44, fill=255)
    x = (W - sw) // 2
    ImageDraw.Draw(canvas).rounded_rectangle((x - 8, band - 8, x + sw + 8, band + sh + 8), radius=50, fill="white")
    canvas.paste(shot, (x, band), mask)
    canvas.save(f"{out}/screenshots/{i}-{f.replace('godot-', '').replace('.png', '')}.png", optimize=True)
# Feature graphic 1024x500: a battle on the right, the name on the left
fg = Image.new("RGB", (1024, 500), "#2d7be0")
battle = Image.open(f"{src}/godot-level-15.png").convert("RGB").crop((0, 260, 1080, 1460)).resize((520, 578), Image.LANCZOS)
fg.paste(battle.crop((0, 39, 520, 539)), (504, 0))
d = ImageDraw.Draw(fg)
fade = Image.new("L", (90, 500))
for x in range(90):
    ImageDraw.Draw(fade).line((x, 0, x, 500), fill=int(255 * (1 - x / 90)))
fg.paste(Image.new("RGB", (90, 500), "#2d7be0"), (504, 0), fade)
big = ImageFont.truetype(font_path, 96)
small = ImageFont.truetype(font_path, 40)
d.text((48, 120), "Tower", font=big, fill="white")
d.text((48, 222), "Siege", font=big, fill="#ffd23f")
d.text((52, 350), "Drag. March. Conquer.", font=small, fill="white")
fg.save(f"{out}/feature-graphic.png", optimize=True)
print("ok")
