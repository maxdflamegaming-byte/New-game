"""Makes the YouTube thumbnail for the gameplay video (1280 x 720), in the store banner's style.

    python3 store/make_thumbnail.py CLASSIC_SHOT BOSS_SHOT

CLASSIC_SHOT and BOSS_SHOT are raw 1080 x 1920 screenshots from tests/store_shots.gd.
Writes store/youtube-thumbnail.png. Needs Pillow.
"""
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = "godot/assets/fonts/Fredoka-Bold.ttf"
NAVY = (29, 35, 66)
W, H = 1280, 720
COLS = [(79, 140, 255), (255, 93, 115), (255, 184, 77), (46, 196, 182), (176, 107, 255),
        (255, 122, 198), (139, 211, 70), (255, 140, 66)]


def gradient(w, h, c1, c2):
    g = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(g)
    for k in range(w):
        t = k / (w - 1)
        d.line([(k, 0), (k, h)], fill=tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)))
    return g.convert("RGBA")


def phone(path, crop, pw, angle):
    shot = Image.open(path).convert("RGBA").crop(crop)
    ph = int(pw * shot.size[1] / shot.size[0])
    shot = shot.resize((pw, ph), Image.LANCZOS)
    m = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, pw - 1, ph - 1), radius=34, fill=255)
    shot.putalpha(m)
    p = Image.new("RGBA", (pw + 28, ph + 28), (0, 0, 0, 0))
    ImageDraw.Draw(p).rounded_rectangle((0, 0, pw + 27, ph + 27), radius=46, fill=NAVY + (255,))
    p.alpha_composite(shot, (14, 14))
    return p.rotate(angle, expand=True, resample=Image.BICUBIC)


def place(bg, p, x, y):
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", p.size, (10, 15, 40, 140)), (x + 16, y + 22), p.split()[3])
    bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(16)))
    bg.alpha_composite(p, (x, y))


def pill(d, x, y, text, size, fill, ink):
    f = ImageFont.truetype(FONT, size)
    tw = d.textlength(text, font=f)
    pad = size * 0.55
    d.rounded_rectangle((x, y + 8, x + tw + pad * 2, y + size * 1.5 + 8), radius=size, fill=tuple(max(0, c - 70) for c in fill))
    d.rounded_rectangle((x, y, x + tw + pad * 2, y + size * 1.5), radius=size, fill=fill)
    d.text((x + pad, y + size * 0.2), text, font=f, fill=ink)


def main(classic, boss):
    bg = gradient(W, H, (79, 140, 255), (140, 92, 255))
    chk = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(chk)
    for y in range(0, H, 60):
        for x in range(0, W, 60):
            if (x // 60 + y // 60) % 2 == 0:
                cd.rectangle((x, y, x + 59, y + 59), fill=(255, 255, 255, 16))
    bg.alpha_composite(chk)
    d = ImageDraw.Draw(bg)
    # Blocks of land in the corners, like the menu
    for (x, y, w, h, col) in [(-10, 560, 250, 180, (255, 184, 77)), (1130, -30, 170, 140, (46, 196, 182)), (-20, -40, 150, 120, (255, 93, 115))]:
        dark = tuple(max(0, c - 60) for c in col)
        d.rectangle((x, y + 16, x + w, y + h + 16), fill=dark)
        d.rectangle((x, y, x + w, y + h), fill=col)
        d.rectangle((x, y, x + w, y + 7), fill=tuple(min(255, c + 70) for c in col))

    # Two phones: the boss fight behind, a Classic game in front
    place(bg, phone(boss, (0, 0, 1080, 1700), 300, 9), 930, 70)
    place(bg, phone(classic, (0, 0, 1080, 1700), 330, -6), 690, 40)

    # The title, a colour per letter
    d = ImageDraw.Draw(bg)
    font = ImageFont.truetype(FONT, 132)
    x, y = 50, 120
    for i, ch in enumerate("COLOR"):
        d.text((x, y), ch, font=font, fill=COLS[i], stroke_width=14, stroke_fill=NAVY)
        x += d.textlength(ch, font=font) - 2
    x, y = 50, 262
    for i, ch in enumerate("CLAIM"):
        d.text((x, y), ch, font=font, fill=COLS[i + 5 if i < 3 else i - 3], stroke_width=14, stroke_fill=NAVY)
        x += d.textlength(ch, font=font) - 2
    d.text((56, 430), "Paint the map!", font=ImageFont.truetype(FONT, 64), fill="white", stroke_width=9, stroke_fill=NAVY)
    pill(d, 58, 540, "GAMEPLAY", 44, (255, 201, 60), (74, 43, 0))
    icon = Image.open("godot/assets/icon_fg.png").convert("RGBA").resize((200, 200), Image.LANCZOS)
    bg.alpha_composite(icon, (430, 470))
    bg.convert("RGB").save("store/youtube-thumbnail.png", optimize=True)
    print("saved store/youtube-thumbnail.png")


main(sys.argv[1], sys.argv[2])
