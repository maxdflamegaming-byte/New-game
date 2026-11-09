"""Makes the itch.io cover image (630 x 500), in the store banner's style.

    python3 store/make_itch_cover.py CLASSIC_SHOT

CLASSIC_SHOT is a raw 1080 x 1920 screenshot from tests/store_shots.gd.
Writes store/itch-cover.png. Needs Pillow.
"""
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = "godot/assets/fonts/Fredoka-Bold.ttf"
NAVY = (29, 35, 66)
W, H = 630, 500
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
for y in range(0, H, 42):
    for x in range(0, W, 42):
        if (x // 42 + y // 42) % 2 == 0:
            cd.rectangle((x, y, x + 41, y + 41), fill=(255, 255, 255, 16))
bg.alpha_composite(chk)
d = ImageDraw.Draw(bg)
for (x, y, w, h, col) in [(-10, 420, 160, 100, (255, 184, 77)), (540, -20, 110, 90, (46, 196, 182)), (560, 430, 90, 90, (255, 93, 115))]:
    d.rectangle((x, y + 10, x + w, y + h + 10), fill=tuple(max(0, c - 60) for c in col))
    d.rectangle((x, y, x + w, y + h), fill=col)
    d.rectangle((x, y, x + w, y + 5), fill=tuple(min(255, c + 70) for c in col))

# A phone of real play on the right
shot = Image.open(sys.argv[1]).convert("RGBA").crop((0, 0, 1080, 1700))
pw = 210
ph = int(pw * shot.size[1] / shot.size[0])
shot = shot.resize((pw, ph), Image.LANCZOS)
m = Image.new("L", (pw, ph), 0)
ImageDraw.Draw(m).rounded_rectangle((0, 0, pw - 1, ph - 1), radius=22, fill=255)
shot.putalpha(m)
p = Image.new("RGBA", (pw + 18, ph + 18), (0, 0, 0, 0))
ImageDraw.Draw(p).rounded_rectangle((0, 0, pw + 17, ph + 17), radius=30, fill=NAVY + (255,))
p.alpha_composite(shot, (9, 9))
p = p.rotate(-7, expand=True, resample=Image.BICUBIC)
px, py = 375, 50
sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sh.paste(Image.new("RGBA", p.size, (10, 15, 40, 140)), (px + 10, py + 14), p.split()[3])
bg.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10)))
bg.alpha_composite(p, (px, py))

d = ImageDraw.Draw(bg)
font = ImageFont.truetype(FONT, 84)
for word, y, off in [("COLOR", 70, 0), ("CLAIM", 160, 5)]:
    x = 30
    for i, ch in enumerate(word):
        d.text((x, y), ch, font=font, fill=COLS[(i + off) % 8], stroke_width=9, stroke_fill=NAVY)
        x += d.textlength(ch, font=font) - 2
d.text((34, 268), "Paint the map!", font=ImageFont.truetype(FONT, 38), fill="white", stroke_width=6, stroke_fill=NAVY)
f = ImageFont.truetype(FONT, 26)
t = "8 modes · 11 maps · bosses"
tw = d.textlength(t, font=f)
d.rounded_rectangle((32, 334 + 6, 32 + tw + 32, 334 + 44 + 6), radius=22, fill=(214, 150, 0))
d.rounded_rectangle((32, 334, 32 + tw + 32, 334 + 44), radius=22, fill=(255, 201, 60))
d.text((48, 340), t, font=f, fill=(74, 43, 0))
icon = Image.open("godot/assets/icon_fg.png").convert("RGBA").resize((130, 130), Image.LANCZOS)
bg.alpha_composite(icon, (225, 380))
bg.convert("RGB").save("store/itch-cover.png", optimize=True)
print("saved store/itch-cover.png")
