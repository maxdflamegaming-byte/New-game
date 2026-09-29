"""Makes the Google Play graphics from raw game screenshots.

    godot --path godot --rendering-driver opengl3 -s tests/store_shots.gd -- RAW_DIR   (under xvfb-run)
    python3 store/make_assets.py RAW_DIR

Writes store/screenshots/*.png (1080 x 1920, captioned), store/feature-graphic.png (1024 x 500)
and store/icon-512.png. Needs Pillow.
"""
import shutil
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW = sys.argv[1] if len(sys.argv) > 1 else "."
FONT = "godot/assets/fonts/Fredoka-Bold.ttf"
FONT_MED = "godot/assets/fonts/Fredoka-Medium.ttf"
NAVY = (29, 35, 66)

SHOTS = [
    ("1-classic", "Loop back to claim the land!", ((79, 140, 255), (140, 92, 255))),
    ("2-boss", "Beat the King, the Queen and the Wizard", ((255, 93, 115), (255, 140, 66))),
    ("3-pinball", "11 maps, from Ice Rink to Pinball", ((255, 93, 158), (176, 107, 255))),
    ("4-shop", "Skins, trail effects and pets", ((176, 107, 255), (255, 122, 198))),
    ("5-menu", "7 modes and a new event every week", ((79, 140, 255), (46, 196, 182))),
    ("6-results", "King of the Hill, levels and coins", ((255, 184, 77), (255, 93, 115))),
    ("7-missions", "New missions every day", ((255, 140, 66), (176, 107, 255))),
    ("8-profile", "Level up for rewards you can't buy", ((140, 92, 255), (79, 140, 255))),
]


def gradient(w, h, c1, c2, vertical=True):
    g = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(g)
    n = h if vertical else w
    for k in range(n):
        t = k / (n - 1)
        c = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
        d.line([(0, k), (w, k)] if vertical else [(k, 0), (k, h)], fill=c)
    return g.convert("RGBA")


def rounded(im, r):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, im.size[0] - 1, im.size[1] - 1), radius=r, fill=255)
    out = im.convert("RGBA")
    out.putalpha(m)
    return out


def screenshots():
    W, H = 1080, 1920
    font = ImageFont.truetype(FONT, 84)
    for name, caption, (c1, c2) in SHOTS:
        bg = gradient(W, H, c1, c2)
        d = ImageDraw.Draw(bg)
        words, lines, cur = caption.split(), [], ""
        for word in words:
            t = (cur + " " + word).strip()
            if d.textlength(t, font=font) > W - 120:
                lines.append(cur)
                cur = word
            else:
                cur = t
        lines.append(cur)
        y = 110 if len(lines) == 1 else 60
        for ln in lines:
            tw = d.textlength(ln, font=font)
            d.text(((W - tw) / 2, y), ln, font=font, fill="white", stroke_width=10, stroke_fill=NAVY)
            y += 104
        shot = Image.open(f"{RAW}/{name}.png").convert("RGB")
        sw = int(W * 0.8)
        sh = int(sw * shot.size[1] / shot.size[0])
        shot = rounded(shot.resize((sw, sh), Image.LANCZOS), 44)
        top = H - sh - 70
        shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(((W - sw) // 2, top + 18, (W + sw) // 2, top + sh + 18), radius=44, fill=(15, 20, 45, 120))
        bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(22)))
        frame = Image.new("RGBA", (sw + 20, sh + 20), (0, 0, 0, 0))
        ImageDraw.Draw(frame).rounded_rectangle((0, 0, sw + 19, sh + 19), radius=52, fill=(255, 255, 255, 255))
        bg.alpha_composite(frame, ((W - sw) // 2 - 10, top - 10))
        bg.alpha_composite(shot, ((W - sw) // 2, top))
        bg.convert("RGB").save(f"store/screenshots/{name}.png", optimize=True)
        print("saved", name)


def feature_graphic():
    W, H = 1024, 500
    bg = gradient(W, H, (79, 140, 255), (140, 92, 255), vertical=False)
    chk = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(chk)
    for y in range(0, H, 50):
        for x in range(0, W, 50):
            if (x // 50 + y // 50) % 2 == 0:
                cd.rectangle((x, y, x + 49, y + 49), fill=(255, 255, 255, 16))
    bg.alpha_composite(chk)
    d = ImageDraw.Draw(bg)

    def block(x, y, w, h, col, dark):
        d.rectangle((x, y + 14, x + w, y + h + 14), fill=dark)
        d.rectangle((x, y, x + w, y + h), fill=col)
        d.rectangle((x, y, x + w, y + 6), fill=tuple(min(255, c + 70) for c in col))

    block(-10, 380, 190, 140, (255, 184, 77), (210, 122, 6))
    block(870, -30, 170, 120, (46, 196, 182), (28, 148, 136))
    block(900, 400, 140, 120, (255, 93, 115), (196, 47, 77))
    # A phone showing real play, tilted, with a shadow
    shot = Image.open(f"{RAW}/1-classic.png").convert("RGBA").crop((0, 0, 1080, 1560))
    pw = 300
    ph = int(pw * shot.size[1] / shot.size[0])
    shot = shot.resize((pw, ph), Image.LANCZOS)
    m = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, pw - 1, ph - 1), radius=30, fill=255)
    shot.putalpha(m)
    phone = Image.new("RGBA", (pw + 24, ph + 24), (0, 0, 0, 0))
    ImageDraw.Draw(phone).rounded_rectangle((0, 0, pw + 23, ph + 23), radius=40, fill=NAVY + (255,))
    phone.alpha_composite(shot, (12, 12))
    phone = phone.rotate(-8, expand=True, resample=Image.BICUBIC)
    px, py = 640, 40
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", phone.size, (10, 15, 40, 120)), (px + 14, py + 18), phone.split()[3])
    bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    bg.alpha_composite(phone, (px, py))
    # The title, a colour per letter like the menu
    cols = [(79, 140, 255), (255, 93, 115), (255, 184, 77), (46, 196, 182), (176, 107, 255), (255, 122, 198), (139, 211, 70), (255, 140, 66)]
    font = ImageFont.truetype(FONT, 104)
    d = ImageDraw.Draw(bg)
    x, y = 56, 120
    for i, ch in enumerate("COLOR CLAIM"):
        if ch == " ":
            x += 30
            continue
        d.text((x, y), ch, font=font, fill=cols[i % len(cols)], stroke_width=12, stroke_fill=NAVY)
        x += d.textlength(ch, font=font) - 2
    d.text((60, 262), "Paint the map. Cut their trails.", font=ImageFont.truetype(FONT, 40), fill="white", stroke_width=6, stroke_fill=NAVY)
    d.text((62, 322), "7 modes  ·  11 maps  ·  bosses & pets", font=ImageFont.truetype(FONT_MED, 30), fill=(255, 255, 255, 235), stroke_width=4, stroke_fill=NAVY)
    icon = Image.open("godot/assets/icon_fg.png").convert("RGBA").resize((210, 210), Image.LANCZOS)
    bg.alpha_composite(icon, (250, 290))
    bg.convert("RGB").save("store/feature-graphic.png", optimize=True)
    print("saved feature graphic")


screenshots()
feature_graphic()
shutil.copy("godot/assets/icon.png", "store/icon-512.png")
