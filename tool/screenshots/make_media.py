"""Generates the post images used by the README screenshots (test/screenshots/media/).

Everything is drawn here, so no real photos ever end up in the repo. Needs Pillow; run from the repo root:
    python tool/screenshots/make_media.py
Fonts come from Windows (Ink Free, Segoe Print, Cambria, Segoe UI); adjust FONTS on other systems.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join('test', 'screenshots', 'media')
F = 'C:/Windows/Fonts/'
FONTS = {'hand': F + 'Inkfree.ttf', 'print': F + 'segoepr.ttf', 'serif': F + 'cambria.ttc',
         'serifi': F + 'cambriai.ttf', 'ui': F + 'segoeui.ttf', 'uib': F + 'segoeuib.ttf'}
S = 1080


def font(kind, size):
    return ImageFont.truetype(FONTS[kind], size)


def notes():
    """Handwritten notes on squared paper: the hydrogen atom."""
    random.seed(4)
    im = Image.new('RGB', (S, S), (250, 247, 238))
    d = ImageDraw.Draw(im)
    for x in range(0, S, 36):
        d.line([(x, 0), (x, S)], fill=(214, 226, 240), width=1)
    for y in range(0, S, 36):
        d.line([(0, y), (S, y)], fill=(214, 226, 240), width=1)
    d.line([(110, 0), (110, S)], fill=(235, 150, 150), width=3)
    ink, blue = (32, 40, 90), (30, 90, 200)
    d.text((150, 70), 'Hydrogen atom', font=font('print', 76), fill=ink)
    d.line([(150, 170), (760, 176)], fill=(250, 170, 40), width=10)
    lines = [
        ('hand', 58, 'Energy levels:', ink),
        ('serifi', 64, 'Eₙ = − 13.6 eV / n²', blue),
        ('hand', 58, 'Bohr radius:', ink),
        ('serifi', 64, 'a₀ = 4πε₀ħ² / mₑe² ≈ 0.529 Å', blue),
        ('hand', 58, 'Ground state:', ink),
        ('serifi', 64, 'ψ₁₀₀ = e^(−r/a₀) / √(π a₀³)', blue),
        ('hand', 54, '* degeneracy of level n is n²', (180, 40, 60)),
    ]
    y = 220
    for kind, size, text, color in lines:
        d.text((150 + random.randint(-6, 6), y), text, font=font(kind, size), fill=color)
        y += 102 if kind == 'hand' else 118
    # a little orbit sketch
    cx, cy = 900, 950
    for r in (40, 85, 130):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(120, 120, 160), width=3)
    d.ellipse([cx - 14, cy - 14, cx + 14, cy + 14], fill=(220, 70, 70))
    d.ellipse([cx + 85 - 9, cy - 9, cx + 85 + 9, cy + 9], fill=blue)
    return im


def chart():
    """Mock-test progress chart on a dark card."""
    im = Image.new('RGB', (S, S), (16, 16, 32))
    d = ImageDraw.Draw(im)
    # soft glow
    glow = Image.new('RGB', (S, S), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([520, -200, 1300, 560], fill=(120, 60, 200))
    gd.ellipse([-260, 620, 420, 1300], fill=(240, 120, 40))
    im = Image.blend(im, glow.filter(ImageFilter.GaussianBlur(180)), 0.35)
    d = ImageDraw.Draw(im)
    d.text((80, 80), 'GATE Physics mocks', font=font('uib', 66), fill=(255, 255, 255))
    d.text((80, 168), 'score out of 100, last 8 tests', font=font('ui', 40), fill=(180, 180, 210))
    scores = [41, 47, 45, 53, 58, 61, 66, 72]
    x0, y0, w, h = 110, 900, 860, 560
    for g in range(0, 101, 25):
        y = y0 - h * g / 100
        d.line([(x0, y), (x0 + w, y)], fill=(60, 60, 90), width=2)
        d.text((x0 - 70, y - 22), str(g), font=font('ui', 34), fill=(130, 130, 170))
    bw = w / len(scores)
    for i, s in enumerate(scores):
        top = y0 - h * s / 100
        left = x0 + i * bw + 18
        c = (255, 140 + i * 12, 60) if i == len(scores) - 1 else (124 + i * 12, 92 + i * 10, 255)
        d.rounded_rectangle([left, top, left + bw - 36, y0], radius=16, fill=c)
        d.text((left + 8, top - 52), str(s), font=font('uib', 38), fill=(255, 255, 255))
    d.text((80, 950), '+31 since September', font=font('uib', 52), fill=(255, 170, 80))
    return im


def badge():
    """'Cleared' card with confetti."""
    random.seed(11)
    im = Image.new('RGB', (S, S))
    d = ImageDraw.Draw(im)
    for y in range(S):  # vertical gradient
        t = y / S
        d.line([(0, y), (S, y)], fill=(int(40 + 60 * t), int(20 + 30 * t), int(90 + 80 * t)))
    for _ in range(140):
        x, y = random.randint(0, S), random.randint(0, S)
        c = random.choice([(255, 196, 0), (255, 99, 132), (54, 214, 160), (110, 180, 255), (255, 255, 255)])
        a = random.random() * math.pi
        r = random.randint(8, 18)
        d.polygon([(x + r * math.cos(a), y + r * math.sin(a)), (x - r * math.cos(a), y - r * math.sin(a)),
                   (x + r / 2 * math.sin(a), y - r / 2 * math.cos(a))], fill=c)
    d.ellipse([340, 220, 740, 620], fill=(255, 196, 0))
    d.ellipse([370, 250, 710, 590], fill=(255, 214, 70))
    star = [(540 + (130 if k % 2 == 0 else 55) * math.sin(k * math.pi / 5),
             420 - (130 if k % 2 == 0 else 55) * math.cos(k * math.pi / 5)) for k in range(10)]
    d.polygon(star, fill=(255, 255, 255))
    d.text((540, 720), 'CSIR NET', font=font('uib', 110), fill=(255, 255, 255), anchor='mm')
    d.text((540, 830), 'Physical Sciences · cleared', font=font('ui', 52), fill=(230, 220, 255), anchor='mm')
    return im


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (('notes', notes), ('chart', chart), ('badge', badge)):
        fn().convert('RGB').resize((720, 720), Image.LANCZOS).save(os.path.join(OUT, f'{name}.jpg'), quality=86)
        print('wrote', name)
