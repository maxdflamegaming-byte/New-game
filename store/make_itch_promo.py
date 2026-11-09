"""Makes the itch.io promo images, in the store banner's style:

    python3 store/make_itch_promo.py CLASSIC_SHOT BOSS_SHOT

- store/itch-social.png      1200 x 630  (link previews on social media)
- store/itch-wide-cover.png  1260 x 540  (21:9, home page featuring)
- store/itch-logo.png        transparent logo, readable on white and black
The favicon is store/icon-512.png. Needs Pillow.
"""
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = "godot/assets/fonts/Fredoka-Bold.ttf"
NAVY = (29, 35, 66)
COLS = [(79, 140, 255), (255, 93, 115), (255, 184, 77), (46, 196, 182), (176, 107, 255),
        (255, 122, 198), (139, 211, 70), (255, 140, 66)]
CLASSIC, BOSS = sys.argv[1], sys.argv[2]


def backdrop(W, H, cell):
    g = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(g)
    for k in range(W):
        t = k / (W - 1)
        d.line([(k, 0), (k, H)], fill=tuple(int(a + (b - a) * t) for a, b in zip((79, 140, 255), (140, 92, 255))))
    bg = g.convert("RGBA")
    chk = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(chk)
    for y in range(0, H, cell):
        for x in range(0, W, cell):
            if (x // cell + y // cell) % 2 == 0:
                cd.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(255, 255, 255, 16))
    bg.alpha_composite(chk)
    return bg


def blocks(bg, items):
    d = ImageDraw.Draw(bg)
    for (x, y, w, h, col) in items:
        d.rectangle((x, y + 12, x + w, y + h + 12), fill=tuple(max(0, c - 60) for c in col))
        d.rectangle((x, y, x + w, y + h), fill=col)
        d.rectangle((x, y, x + w, y + 6), fill=tuple(min(255, c + 70) for c in col))


def phone(path, pw, angle):
    shot = Image.open(path).convert("RGBA").crop((0, 0, 1080, 1700))
    ph = int(pw * shot.size[1] / shot.size[0])
    shot = shot.resize((pw, ph), Image.LANCZOS)
    m = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, pw - 1, ph - 1), radius=pw // 10, fill=255)
    shot.putalpha(m)
    b = max(10, pw // 22)
    p = Image.new("RGBA", (pw + 2 * b, ph + 2 * b), (0, 0, 0, 0))
    ImageDraw.Draw(p).rounded_rectangle((0, 0, pw + 2 * b - 1, ph + 2 * b - 1), radius=pw // 7, fill=NAVY + (255,))
    p.alpha_composite(shot, (b, b))
    return p.rotate(angle, expand=True, resample=Image.BICUBIC)


def place(bg, p, x, y):
    W, H = bg.size
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", p.size, (10, 15, 40, 140)), (x + 14, y + 20), p.split()[3])
    bg.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14)))
    bg.alpha_composite(p, (x, y))


def title(d, x, y, size, two_lines, outer=0):
    f = ImageFont.truetype(FONT, size)
    sw = max(6, size // 11)
    lines = [("COLOR", 0), ("CLAIM", 5)] if two_lines else [("COLOR CLAIM", 0)]
    for row, (word, off) in enumerate(lines):
        cx = x
        for i, ch in enumerate(word):
            if ch == " ":
                cx += size * 0.3
                continue
            yy = y + row * size * 1.05
            if outer:
                d.text((cx, yy), ch, font=f, fill="white", stroke_width=sw + outer, stroke_fill="white")
            d.text((cx, yy), ch, font=f, fill=COLS[(i + off) % 8], stroke_width=sw, stroke_fill=NAVY)
            cx += d.textlength(ch, font=f) - 2


def text_width(size, word):
    f = ImageFont.truetype(FONT, size)
    d = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    return sum(size * 0.3 if ch == " " else d.textlength(ch, font=f) - 2 for ch in word)


# Social media image, 1200 x 630
W, H = 1200, 630
bg = backdrop(W, H, 60)
blocks(bg, [(-10, 520, 220, 140, (255, 184, 77)), (1090, -20, 130, 110, (46, 196, 182)), (1060, 540, 160, 110, (255, 93, 115))])
place(bg, phone(BOSS, 270, 9), 880, 60)
place(bg, phone(CLASSIC, 300, -6), 650, 40)
d = ImageDraw.Draw(bg)
title(d, 50, 90, 128, True)
d.text((56, 380), "Paint the map!", font=ImageFont.truetype(FONT, 60), fill="white", stroke_width=8, stroke_fill=NAVY)
f = ImageFont.truetype(FONT, 34)
t = "8 modes · 11 maps · bosses"
tw = d.textlength(t, font=f)
d.rounded_rectangle((56, 478 + 8, 56 + tw + 44, 478 + 58 + 8), radius=29, fill=(214, 150, 0))
d.rounded_rectangle((56, 478, 56 + tw + 44, 478 + 58), radius=29, fill=(255, 201, 60))
d.text((78, 486), t, font=f, fill=(74, 43, 0))
bg.convert("RGB").save("store/itch-social.png", optimize=True)

# Wide cover, 21:9 (1260 x 540)
W, H = 1260, 540
bg = backdrop(W, H, 54)
blocks(bg, [(-10, 440, 230, 120, (255, 184, 77)), (1150, -20, 130, 100, (46, 196, 182)), (1120, 450, 160, 100, (255, 93, 115)), (-20, -30, 140, 90, (255, 122, 198))])
place(bg, phone(BOSS, 240, 9), 1000, 45)
place(bg, phone(CLASSIC, 265, -6), 790, 30)
d = ImageDraw.Draw(bg)
size = 100
title(d, 60, 120, size, False)
d.text((66, 270), "Paint the map. Cut their trails.", font=ImageFont.truetype(FONT, 46), fill="white", stroke_width=7, stroke_fill=NAVY)
d.text((68, 345), "8 modes  ·  11 maps  ·  3 bosses", font=ImageFont.truetype(FONT, 34), fill="white", stroke_width=5, stroke_fill=NAVY)
icon = Image.open("godot/assets/icon_fg.png").convert("RGBA").resize((150, 150), Image.LANCZOS)
bg.alpha_composite(icon, (500, 385))
bg.convert("RGB").save("store/itch-wide-cover.png", optimize=True)

# Transparent logo, wide: navy outline plus a thin white edge, so it reads on white and on black
size = 150
pad = 30
W = int(text_width(size, "COLOR CLAIM")) + pad * 2 + 20
H = int(size * 1.35) + pad * 2
logo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
title(ImageDraw.Draw(logo), pad, pad - 10, size, False, outer=5)
logo = logo.crop(logo.getbbox())
logo.save("store/itch-logo.png", optimize=True)
print("saved itch-social, itch-wide-cover, itch-logo", logo.size)
