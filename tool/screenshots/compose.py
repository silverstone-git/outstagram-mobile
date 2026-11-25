"""Frames the raw screenshots (test/screenshots/out/*.png) for the README.

    flutter test test/screenshots --update-goldens --dart-define=SCREENSHOTS=true
    python tool/screenshots/compose.py

Writes docs/screenshots/<name>.png (phone frame + status bar, 600 px wide) and docs/screenshots/banner.png.
Needs Pillow. Fonts: Segoe UI (Windows); change FONT on other systems.
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW = os.path.join('test', 'screenshots', 'out')
OUT = os.path.join('docs', 'screenshots')
FONT = 'C:/Windows/Fonts/segoeui.ttf'
FONT_B = 'C:/Windows/Fonts/segoeuib.ttf'
NAVY = (16, 16, 32)
LIME, TEAL = (183, 255, 57), (0, 201, 139)

SCREENS = ['feed', 'exam', 'tutor', 'streak', 'profile', 'exams']


def font(size, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, size)


def status_bar(shot):
    """Adds an Android-style status bar (time, signal, battery) in the app bar's colour."""
    w, h = shot.size
    bar = 84
    bg = shot.getpixel((w // 2, 4))
    im = Image.new('RGB', (w, h + bar), bg)
    im.paste(shot, (0, bar))
    d = ImageDraw.Draw(im)
    fg = (240, 240, 250) if sum(bg[:3]) < 384 else (20, 20, 30)
    d.text((60, bar // 2), '9:41', font=font(38, True), fill=fg, anchor='lm')
    # signal bars
    x = w - 230
    for i in range(4):
        d.rounded_rectangle([x + i * 16, bar // 2 + 12 - (i + 1) * 7, x + i * 16 + 10, bar // 2 + 12], radius=2, fill=fg)
    # battery
    bx = w - 140
    d.rounded_rectangle([bx, bar // 2 - 14, bx + 58, bar // 2 + 14], radius=7, outline=fg, width=3)
    d.rounded_rectangle([bx + 6, bar // 2 - 8, bx + 44, bar // 2 + 8], radius=3, fill=fg)
    d.rectangle([bx + 60, bar // 2 - 6, bx + 65, bar // 2 + 6], fill=fg)
    return im


def rounded(im, r):
    mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.size[0] - 1, im.size[1] - 1], radius=r, fill=255)
    out = im.convert('RGBA')
    out.putalpha(mask)
    return out


def phone(shot):
    """Screenshot in a slim black phone body with a soft shadow; returns RGBA."""
    screen = rounded(status_bar(shot.convert('RGB')), 70)
    bezel = 22
    w, h = screen.size[0] + 2 * bezel, screen.size[1] + 2 * bezel
    body = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle([0, 0, w - 1, h - 1], radius=92, fill=(8, 8, 12, 255),
                                           outline=(70, 70, 90, 255), width=3)
    body.alpha_composite(screen, (bezel, bezel))
    # punch-hole camera
    ImageDraw.Draw(body).ellipse([w // 2 - 14, bezel + 28, w // 2 + 14, bezel + 56], fill=(5, 5, 8, 255))
    pad = 80
    canvas = Image.new('RGBA', (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([pad, pad + 30, pad + w, pad + h + 30], radius=92, fill=(0, 0, 0, 150))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(36)))
    canvas.alpha_composite(body, (pad, pad))
    return canvas


def fit(im, width):
    return im.resize((width, round(im.size[1] * width / im.size[0])), Image.LANCZOS)


def banner(phones):
    W, H = 2400, 1260
    bg = Image.new('RGB', (W, H), NAVY)
    glow = Image.new('RGB', (W, H), (0, 0, 0))
    g = ImageDraw.Draw(glow)
    g.ellipse([1300, -500, 2700, 700], fill=(90, 50, 190))
    g.ellipse([-400, 700, 900, 1800], fill=(0, 140, 100))
    g.ellipse([900, 800, 1700, 1500], fill=(200, 90, 30))
    bg = Image.blend(bg, glow.filter(ImageFilter.GaussianBlur(260)), 0.55).convert('RGBA')
    d = ImageDraw.Draw(bg)

    # logo: the mark (cropped from the feed screenshot) + wordmark
    feed = Image.open(os.path.join(RAW, 'feed.png')).convert('RGBA')
    mark = feed.crop((40, 28, 128, 116))
    key = mark.getpixel((1, 1))[:3]  # the app bar colour around the mark -> transparent
    px = mark.load()
    for yy in range(mark.size[1]):
        for xx in range(mark.size[0]):
            r, g, b, _ = px[xx, yy]
            if abs(r - key[0]) + abs(g - key[1]) + abs(b - key[2]) < 40:
                px[xx, yy] = (r, g, b, 0)
    mark = mark.resize((132, 132), Image.LANCZOS)
    bg.alpha_composite(mark, (120, 170))
    f = font(132, True)
    d.text((280, 236), 'Outsta', font=f, fill=(255, 255, 255), anchor='lm')
    d.text((280 + d.textlength('Outsta', font=f), 236), 'gram', font=f, fill=TEAL, anchor='lm')

    lines = ['Study together.', 'Practise smarter.']
    y = 420
    for line in lines:
        d.text((126, y), line, font=font(92, True), fill=(255, 255, 255))
        y += 112
    sub = ['A social network for students, with Pariksha', 'mock exams, daily streaks and an AI tutor that',
           'explains every answer, with real maths.']
    y += 40
    for line in sub:
        d.text((130, y), line, font=font(44), fill=(196, 198, 225))
        y += 62
    # chips
    x, y = 130, y + 44
    for label, c in (('Android', LIME), ('Flutter', TEAL), ('Free to try', (255, 170, 80))):
        tw = d.textlength(label, font=font(38, True))
        d.rounded_rectangle([x, y, x + tw + 56, y + 70], radius=35, outline=c, width=3)
        d.text((x + 28, y + 35), label, font=font(38, True), fill=c, anchor='lm')
        x += tw + 80

    # three phones, the middle one in front
    left, mid, right = (fit(p, 560) for p in phones)
    bg.alpha_composite(left, (1080, 150))
    bg.alpha_composite(right, (1820, 150))
    bg.alpha_composite(fit(phones[1], 640), (1410, 40))
    return bg.convert('RGB')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    framed = {}
    for name in SCREENS:
        p = phone(Image.open(os.path.join(RAW, f'{name}.png')))
        framed[name] = p
        fit(p, 600).save(os.path.join(OUT, f'{name}.png'), optimize=True)
        print('wrote', name)
    banner([framed['exam'], framed['feed'], framed['tutor']]).save(os.path.join(OUT, 'banner.png'), optimize=True)
    print('wrote banner')
