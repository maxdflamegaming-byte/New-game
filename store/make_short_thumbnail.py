"""Makes the YouTube Shorts thumbnail (1080 x 1920), in the store banner's style.

    python3 store/make_short_thumbnail.py CLASSIC_SHOT BOSS_SHOT

CLASSIC_SHOT and BOSS_SHOT are raw 1080 x 1920 screenshots from tests/store_shots.gd.
Writes store/youtube-short-thumbnail.png. Needs Pillow. The important parts sit in the middle,
since some places show a Short cropped to a square.
"""
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = "godot/assets/fonts/Fredoka-Bold.ttf"
NAVY = (29, 35, 66)
W, H = 1080, 1920
COLS = [(79, 140, 255), (255, 93, 115), (255, 184, 77), (46, 196, 182), (176, 107, 255),
        (255, 122, 198), (139, 211, 70), (255, 140, 66)]


def gradient(w, h, c1, c2):
    g = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(g)
    for k in range(h):
        t = k / (h - 1)
        d.line([(0, k), (w, k)], fill=tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)))
    return g.convert("RGBA")


def phone(path, crop, pw, angle):
    shot = Image.open(path).convert("RGBA").crop(crop)
    ph = int(pw * shot.size[1] / shot.size[0])
    shot = shot.resize((pw, ph), Image.LANCZOS)
    m = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, pw - 1, ph - 1), radius=40, fill=255)
    shot.putalpha(m)
    p = Image.new("RGBA", (pw + 32, ph + 32), (0, 0, 0, 0))
    ImageDraw.Draw(p).rounded_rectangle((0, 0, pw + 31, ph + 31), radius=54, fill=NAVY + (255,))
    p.alpha_composite(shot, (16, 16))
    return p.rotate(angle, expand=True, resample=Image.BICUBIC)


def place(bg, p, x, y):
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", p.size, (10, 15, 40, 140)), (x + 18, y + 26), p.split()[3])
    bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    bg.alpha_composite(p, (x, y))


def centered(d, text, y, size, fill, sw):
    f = ImageFont.truetype(FONT, size)
    d.text(((W - d.textlength(text, font=f)) / 2, y), text, font=f, fill=fill, stroke_width=sw, stroke_fill=NAVY)


def main(classic, boss):
    bg = gradient(W, H, (79, 140, 255), (140, 92, 255))
    chk = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(chk)
    for y in range(0, H, 90):
        for x in range(0, W, 90):
            if (x // 90 + y // 90) % 2 == 0:
                cd.rectangle((x, y, x + 89, y + 89), fill=(255, 255, 255, 16))
    bg.alpha_composite(chk)
    d = ImageDraw.Draw(bg)
    for (x, y, w, h, col) in [(-10, 1720, 330, 220, (255, 184, 77)), (820, -30, 270, 200, (46, 196, 182)),
                              (-20, -40, 200, 170, (255, 93, 115)), (860, 1660, 240, 280, (255, 93, 158))]:
        dark = tuple(max(0, c - 60) for c in col)
        d.rectangle((x, y + 18, x + w, y + h + 18), fill=dark)
        d.rectangle((x, y, x + w, y + h), fill=col)
        d.rectangle((x, y, x + w, y + 8), fill=tuple(min(255, c + 70) for c in col))

    # The title at the top
    font = ImageFont.truetype(FONT, 190)
    for word, y, off in [("COLOR", 150, 0), ("CLAIM", 350, 5)]:
        x = (W - sum(d.textlength(ch, font=font) - 2 for ch in word)) / 2
        for i, ch in enumerate(word):
            d.text((x, y), ch, font=font, fill=COLS[(i + off) % 8], stroke_width=18, stroke_fill=NAVY)
            x += d.textlength(ch, font=font) - 2

    # Two phones of real play in the middle: the Queen behind, a Classic game in front
    place(bg, phone(boss, (0, 0, 1080, 1560), 420, 10), 560, 640)
    place(bg, phone(classic, (0, 0, 1080, 1560), 470, -7), 90, 600)
    d = ImageDraw.Draw(bg)

    # The question, on a band across the bottom of the phones
    d.rounded_rectangle((40, 1330, W - 40, 1640), radius=60, fill=NAVY + (235,))
    centered(d, "Can you paint", 1350, 112, "white", 0)
    centered(d, "the WHOLE map?", 1480, 112, (255, 201, 60), 0)
    icon = Image.open("godot/assets/icon_fg.png").convert("RGBA").resize((300, 300), Image.LANCZOS)
    bg.alpha_composite(icon, (W - 330, 1180))
    centered(d, "Free on Android", 1700, 72, "white", 9)
    bg.convert("RGB").save("store/youtube-short-thumbnail.png", optimize=True)
    print("saved store/youtube-short-thumbnail.png")


main(sys.argv[1], sys.argv[2])
