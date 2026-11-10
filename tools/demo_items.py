"""Images de démonstration (habits détourés) pour les captures d'écran."""
import numpy as np, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
from scipy.ndimage import gaussian_filter, distance_transform_edt
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
W, H = 900, 1000

def shade(img, mask, folds=0.12, seed=0):
    a = np.asarray(img).astype(float)
    m = np.asarray(mask).astype(float) / 255
    r = np.random.default_rng(seed)
    n = gaussian_filter(r.standard_normal((H, W)), (60, 18))
    n = (n - n.min()) / (n.max() - n.min())
    dist = distance_transform_edt(m > 0.5)
    edge = np.clip(dist / 60, 0, 1) ** 0.5
    light = (0.78 + 0.22 * edge) * (1 - folds + folds * 2 * n)
    light *= np.linspace(1.04, 0.9, H)[:, None]
    a[..., :3] *= light[..., None]
    a[..., 3] = m * 255
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))

def jersey(name, base, pattern=None, second=None, trim=(255, 255, 255), seed=0, long=False):
    mask = Image.new("L", (W, H), 0); d = ImageDraw.Draw(mask)
    sl = 330 if long else 150
    body = [(300, 90), (380, 70), (520, 70), (600, 90), (760, 170), (800 if not long else 860, 170 + sl), (690, 170 + sl + 40),
            (670, 330), (670, 940), (230, 940), (230, 330), (210, 170 + sl + 40), (100 if not long else 40, 170 + sl), (140, 170)]
    d.polygon(body, fill=255)
    d.ellipse((380, 40, 520, 140), fill=0)
    mask = mask.filter(ImageFilter.GaussianBlur(1.5))
    img = Image.new("RGBA", (W, H), base + (255,)); dd = ImageDraw.Draw(img)
    if pattern == "stripes":
        for x in range(0, W, 110): dd.rectangle((x, 0, x + 50, H), fill=second)
    elif pattern == "hoops":
        for y in range(150, H, 140): dd.rectangle((0, y, W, y + 65), fill=second)
    elif pattern == "sash":
        dd.polygon([(170, 120), (300, 90), (760, 900), (630, 940)], fill=second)
    elif pattern == "half":
        dd.rectangle((450, 0, W, H), fill=second)
    elif pattern == "chest":
        dd.rectangle((0, 330, W, 470), fill=second)
    # col et poignets
    dd.ellipse((370, 30, 530, 150), outline=trim, width=18)
    if not long:
        dd.line([(800, 320), (690, 360)], fill=trim, width=22); dd.line([(100, 320), (210, 360)], fill=trim, width=22)
    # écusson générique + logo équipementier générique
    dd.ellipse((540, 220, 610, 290), fill=trim); dd.ellipse((555, 235, 595, 275), fill=base)
    dd.polygon([(300, 250), (350, 230), (330, 270)], fill=trim)
    res = shade(img, mask, seed=seed)
    res.save(os.path.join(out, name + ".png"))

def hoodie(name, color, seed=3):
    mask = Image.new("L", (W, H), 0); d = ImageDraw.Draw(mask)
    d.polygon([(290, 120), (610, 120), (770, 200), (860, 860), (760, 880), (690, 420), (690, 960), (210, 960), (210, 420), (140, 880), (40, 860), (130, 200)], fill=255)
    d.ellipse((330, 0, 570, 230), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.5))
    img = Image.new("RGBA", (W, H), color + (255,)); dd = ImageDraw.Draw(img)
    dd.ellipse((370, 40, 530, 200), fill=tuple(int(c * 0.55) for c in color))
    dd.rounded_rectangle((300, 620, 600, 820), 30, outline=tuple(int(c * 0.8) for c in color), width=8)
    dd.line([(430, 200), (420, 380)], fill=(235, 235, 235), width=8); dd.line([(470, 200), (480, 380)], fill=(235, 235, 235), width=8)
    dd.rectangle((210, 900, 690, 960), fill=tuple(int(c * 0.85) for c in color))
    shade(img, mask, 0.18, seed).save(os.path.join(out, name + ".png"))

def jeans(name, seed=5):
    Wj = W
    mask = Image.new("L", (Wj, H), 0); d = ImageDraw.Draw(mask)
    d.polygon([(250, 40), (650, 40), (700, 960), (480, 960), (450, 330), (420, 960), (200, 960)], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(1.5))
    r = np.random.default_rng(seed)
    base = np.zeros((H, Wj, 4)); base[..., 0] = 52; base[..., 1] = 78; base[..., 2] = 120; base[..., 3] = 255
    tw = gaussian_filter(r.random((H, Wj)), (0.6, 3)); base[..., :3] *= (0.85 + tw[..., None] * 0.3)
    img = Image.fromarray(base.astype(np.uint8)); dd = ImageDraw.Draw(img)
    dd.rectangle((250, 40, 650, 100), fill=(44, 66, 104, 255))
    for x in (280, 610): dd.line([(x, 100), (x + 20, 260)], fill=(200, 150, 80), width=4)
    dd.ellipse((440, 55, 460, 75), fill=(190, 160, 100))
    shade(img, mask, 0.16, seed).save(os.path.join(out, name + ".png"))

def sneakers(name, upper, sole=(245, 245, 240), seed=6):
    w, h = 1000, 560
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    for dx, sc in [(0, 1.0), (60, 0.92)]:
        o = Image.new("RGBA", (w, h), (0, 0, 0, 0)); od = ImageDraw.Draw(o)
        od.rounded_rectangle((60 + dx, 360, 900 + dx, 460), 50, fill=sole + (255,))
        od.polygon([(80 + dx, 380), (120 + dx, 230), (330 + dx, 150), (520 + dx, 170), (700 + dx, 260), (880 + dx, 330), (900 + dx, 380)], fill=upper + (255,))
        od.polygon([(300 + dx, 300), (560 + dx, 240), (640 + dx, 300), (380 + dx, 360)], fill=(255, 255, 255, 255))
        for i in range(5): od.line([(360 + dx + i * 45, 175 + i * 8), (400 + dx + i * 45, 230 + i * 8)], fill=(240, 240, 240, 255), width=10)
        img = Image.alpha_composite(o, img) if dx else Image.alpha_composite(img, o)
    a = np.asarray(img).astype(float)
    a[..., :3] *= np.linspace(1.05, 0.82, h)[:, None, None]
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(out, name + ".png"))

def cap(name, color, seed=8):
    w, h = 800, 520
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.chord((120, 60, 620, 520), 180, 360, fill=color + (255,))
    d.polygon([(560, 290), (780, 330), (760, 370), (520, 330)], fill=tuple(int(c * 0.8) for c in color) + (255,))
    d.rectangle((120, 285, 620, 300), fill=tuple(int(c * 0.7) for c in color) + (255,))
    d.ellipse((355, 50, 385, 80), fill=tuple(int(c * 0.8) for c in color) + (255,))
    img.save(os.path.join(out, name + ".png"))

jersey("j1", (16, 38, 86), "stripes", (170, 20, 40), (240, 240, 240), 1)
jersey("j2", (245, 245, 245), "sash", (200, 20, 30), (20, 20, 20), 2)
jersey("j3", (250, 200, 20), None, None, (20, 60, 140), 3)
jersey("j4", (20, 120, 60), "hoops", (245, 245, 245), (245, 245, 245), 4)
jersey("j5", (130, 20, 40), "chest", (240, 190, 60), (240, 190, 60), 5)
jersey("j6", (25, 25, 28), "half", (90, 160, 220), (230, 230, 230), 6, long=True)
hoodie("hoodie", (150, 152, 156))
hoodie("hoodie2", (60, 72, 58), 9)
jeans("jeans")
sneakers("sneakers", (235, 235, 230))
sneakers("sneakers2", (30, 30, 34), (240, 240, 240), 7)
cap("cap", (24, 40, 80))
print(sorted(os.listdir(out)))

# ---- v2 : dos des maillots et vues d'une chaussure ----
from PIL import ImageFont
def font(size):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"]:
        if os.path.exists(p): return ImageFont.truetype(p, size)
    return ImageFont.load_default()

def crop_alpha(im):
    bb = im.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox()
    return im.crop(bb) if bb else im

def jersey_back(name, base, pattern, second, trim, num, player, seed):
    jersey("_tmp", base, pattern, second, trim, seed)
    im = Image.open(os.path.join(out, "_tmp.png")); os.remove(os.path.join(out, "_tmp.png"))
    d = ImageDraw.Draw(im)
    # pas d'écusson au dos : on repeint la zone avec la couleur de base
    d.ellipse((530, 210, 620, 300), fill=base + (255,)); d.polygon([(290, 240), (360, 220), (340, 280)], fill=base + (255,))
    d.ellipse((380, 40, 520, 140), fill=(0, 0, 0, 0))
    d.chord((370, 30, 530, 110), 0, 180, fill=None, outline=trim, width=16)
    tc = (255, 255, 255) if sum(base) < 400 else (25, 25, 30)
    f1, f2 = font(70), font(300)
    w1 = d.textlength(player.upper(), font=f1); d.text(((W - w1) / 2, 200), player.upper(), font=f1, fill=tc + (255,))
    w2 = d.textlength(num, font=f2); d.text(((W - w2) / 2, 300), num, font=f2, fill=tc + (255,))
    crop_alpha(im).save(os.path.join(out, name + ".png"))

def shoe_views(prefix, upper, accent, sole=(240, 240, 236)):
    def finish(im, name, fade=True):
        a = np.asarray(im).astype(float)
        if fade:
            h = a.shape[0]; a[..., :3] *= np.linspace(1.04, 0.86, h)[:, None, None]
        crop_alpha(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))).save(os.path.join(out, prefix + "_" + name + ".png"))
    # profil (pointe à gauche)
    im = Image.new("RGBA", (1000, 420), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((40, 300, 960, 380), 40, fill=sole + (255,))
    d.polygon([(50, 320), (80, 220), (300, 150), (520, 120), (760, 60), (900, 70), (950, 180), (955, 320)], fill=upper + (255,))
    d.ellipse((610, 50, 860, 140), fill=(30, 30, 30, 255))
    d.polygon([(330, 260), (600, 170), (700, 240), (420, 310)], fill=accent + (255,))
    for i in range(6): d.line([(430 + i * 45, 150 - i * 6), (470 + i * 45, 200 - i * 6)], fill=(250, 250, 250, 255), width=10)
    d.rectangle((40, 360, 960, 380), fill=(200, 200, 196, 255))
    finish(im, "side")
    # autre profil (pointe à droite)
    im2 = Image.open(os.path.join(out, prefix + "_side.png")).transpose(Image.FLIP_LEFT_RIGHT)
    d2 = ImageDraw.Draw(im2); w, h = im2.size
    d2.ellipse((w * 0.55, h * 0.55, w * 0.62, h * 0.66), fill=accent + (255,))
    im2.save(os.path.join(out, prefix + "_inner.png"))
    # dessus (pointe à gauche)
    im = Image.new("RGBA", (1000, 380), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse((30, 40, 560, 340), fill=sole + (255,)); d.ellipse((380, 30, 970, 350), fill=sole + (255,))
    d.ellipse((50, 60, 545, 320), fill=upper + (255,)); d.ellipse((400, 55, 950, 325), fill=upper + (255,))
    d.ellipse((620, 110, 890, 270), fill=(30, 30, 30, 255))
    for i in range(6): d.line([(330 + i * 45, 140), (330 + i * 45, 240)], fill=(250, 250, 250, 255), width=12)
    d.rounded_rectangle((300, 150, 600, 230), 30, outline=(225, 225, 225, 255), width=6)
    finish(im, "top", False)
    # devant (pointe face à soi)
    im = Image.new("RGBA", (420, 420), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((20, 300, 400, 390), 40, fill=sole + (255,))
    d.ellipse((30, 120, 390, 380), fill=upper + (255,))
    d.rounded_rectangle((90, 40, 330, 250), 60, fill=upper + (255,))
    d.rounded_rectangle((140, 60, 280, 200), 40, fill=(235, 235, 235, 255))
    finish(im, "front")
    # arrière (talon)
    im = Image.new("RGBA", (420, 520), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((30, 400, 390, 500), 40, fill=sole + (255,))
    d.rounded_rectangle((50, 20, 370, 450), 90, fill=upper + (255,))
    d.rounded_rectangle((150, 30, 270, 300), 30, fill=accent + (255,))
    d.ellipse((90, 0, 330, 90), fill=(30, 30, 30, 255))
    finish(im, "rear")

jersey_back("j1_back", (16, 38, 86), "stripes", (170, 20, 40), (240, 240, 240), "10", "Diallo", 1)
jersey_back("j2_back", (245, 245, 245), "sash", (200, 20, 30), (20, 20, 20), "4", "Ruiz", 2)
jersey_back("j3_back", (250, 200, 20), None, None, (20, 60, 140), "9", "Moreno", 3)
jersey_back("j4_back", (20, 120, 60), "hoops", (245, 245, 245), (245, 245, 245), "8", "Byrne", 4)
jersey_back("j5_back", (130, 20, 40), "chest", (240, 190, 60), (240, 190, 60), "10", "Ricci", 5)
jersey_back("j6_back", (25, 25, 28), "half", (90, 160, 220), (230, 230, 230), "7", "Vidal", 6)
shoe_views("shoeA", (236, 236, 232), (120, 130, 140))
shoe_views("shoeB", (36, 36, 40), (230, 230, 230), (245, 245, 245))
for n in ["hoodie", "hoodie2", "jeans", "cap", "j1", "j2", "j3", "j4", "j5", "j6"]:
    p = os.path.join(out, n + ".png"); crop_alpha(Image.open(p)).save(p)
