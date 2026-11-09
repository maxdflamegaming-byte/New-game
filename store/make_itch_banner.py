"""Makes the itch.io page header banner (960 x 260), in the store banner's style.

    python3 store/make_itch_banner.py

Writes store/itch-banner.png. Needs Pillow.
"""
from PIL import Image, ImageDraw, ImageFont

FONT = "godot/assets/fonts/Fredoka-Bold.ttf"
NAVY = (29, 35, 66)
W, H = 960, 260
COLS = [(79, 140, 255), (255, 93, 115), (255, 184, 77), (46, 196, 182), (176, 107, 255),
        (255, 122, 198), (139, 211, 70), (255, 140, 66)]

g = Image.new("RGB", (W, H))
d = ImageDraw.Draw(g)
for k in range(W):
    t = k / (W - 1)
    d.line([(k, 0), (k, H)], fill=tuple(int(a + (b - a) * t) for a, b in zip((79, 140, 255), (140, 92, 255))))
bg = g.convert("RGBA")
chk = Image.new("RGBA", (W, H), (0, 0, 0, 0))
cd = ImageDraw.Draw(chk)
for y in range(0, H, 40):
    for x in range(0, W, 40):
        if (x // 40 + y // 40) % 2 == 0:
            cd.rectangle((x, y, x + 39, y + 39), fill=(255, 255, 255, 16))
bg.alpha_composite(chk)
d = ImageDraw.Draw(bg)
for (x, y, w, h, col) in [(-10, 190, 170, 90, (255, 184, 77)), (860, -20, 110, 80, (46, 196, 182)),
                          (820, 200, 150, 80, (255, 93, 115)), (-20, -30, 110, 70, (255, 122, 198))]:
    d.rectangle((x, y + 9, x + w, y + h + 9), fill=tuple(max(0, c - 60) for c in col))
    d.rectangle((x, y, x + w, y + h), fill=col)
    d.rectangle((x, y, x + w, y + 5), fill=tuple(min(255, c + 70) for c in col))
font = ImageFont.truetype(FONT, 110)
text = "COLOR CLAIM"
widths = [0 if ch == " " else d.textlength(ch, font=font) - 2 for ch in text]
total = sum(widths) + 34
x = (W - total) / 2
for i, ch in enumerate(text):
    if ch == " ":
        x += 34
        continue
    d.text((x, 38), ch, font=font, fill=COLS[i % 8], stroke_width=11, stroke_fill=NAVY)
    x += widths[i]
f = ImageFont.truetype(FONT, 40)
t = "Paint the map. Cut their trails."
d.text(((W - d.textlength(t, font=f)) / 2, 178), t, font=f, fill="white", stroke_width=6, stroke_fill=NAVY)
bg.convert("RGB").save("store/itch-banner.png", optimize=True)
print("saved store/itch-banner.png")
