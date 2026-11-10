"""Génère les textures de la penderie (bois, parquet, mur, tissu, environnement)."""
import numpy as np
from PIL import Image, ImageFilter
from scipy.ndimage import gaussian_filter, map_coordinates
import sys, os
out = sys.argv[1]
rng = np.random.default_rng(7)

def fbm(h, w, octaves=5, base=4, seed=0):
    r = np.random.default_rng(seed)
    acc = np.zeros((h, w)); amp = 1.0; tot = 0
    for o in range(octaves):
        f = base * 2 ** o
        small = r.random((f + 1, f + 1))
        yy = np.linspace(0, f, h, endpoint=False); xx = np.linspace(0, f, w, endpoint=False)
        Y, X = np.meshgrid(yy, xx, indexing="ij")
        layer = map_coordinates(small, [Y, X], order=3, mode="wrap")
        acc += layer * amp; tot += amp; amp *= 0.5
    acc /= tot
    return (acc - acc.min()) / (acc.max() - acc.min())

def normal_from_height(hgt, strength=4.0):
    gy, gx = np.gradient(hgt)
    nx, ny, nz = -gx * strength, -gy * strength, np.ones_like(hgt)
    l = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    n = np.stack([nx / l, ny / l, nz / l], -1)
    return Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))

def save(img, name, q=90):
    p = os.path.join(out, name)
    if name.endswith(".jpg"): img.convert("RGB").save(p, quality=q)
    else: img.save(p)

# --- Noyer (caisson de la penderie), grain vertical ---
S = 1024
n = fbm(S, S, 6, 3, 1)
Y, X = np.mgrid[0:S, 0:S] / S
warp = gaussian_filter(rng.standard_normal((S, S)), 40) * 18
rings = np.sin((X * 70 + n * 2.0 + warp * 0.08) * np.pi)
grain = 0.5 + 0.5 * rings
fine = fbm(S, S, 3, 64, 2)
streak = gaussian_filter(rng.random((S, S)), (30, 0.6))
t = np.clip(grain * 0.22 + fine * 0.25 + (streak - streak.mean()) * 9 + n * 0.45, 0, 1)
dark = np.array([46, 32, 24]); light = np.array([92, 64, 46])
wood = dark + (light - dark) * t[..., None] ** 1.3
save(Image.fromarray(wood.astype(np.uint8)), "wood_albedo.jpg")
save(normal_from_height(gaussian_filter(t, 1.2), 3.0), "wood_normal.png")

# --- Parquet chêne clair ---
pw = 128  # largeur d'une lame en pixels
floor = np.zeros((S, S, 3))
hgt = np.zeros((S, S))
for i in range(S // pw):
    off = rng.integers(0, S)
    tone = rng.uniform(0.85, 1.12)
    nn = np.roll(fbm(S, pw, 5, 2, 10 + i), off, axis=0)
    yy = np.arange(S)[:, None] / S
    r2 = 0.5 + 0.5 * np.sin((yy * 9 + nn * 3 + np.arange(pw)[None, :] / pw * 0.4) * np.pi * 2)
    tt = np.clip(r2 * 0.35 + nn * 0.5 + 0.15, 0, 1)
    base = np.array([196, 160, 118]) * tone; dk = np.array([150, 112, 76]) * tone
    floor[:, i * pw:(i + 1) * pw] = dk + (base - dk) * tt[..., None]
    hgt[:, i * pw:(i + 1) * pw] = tt * 0.3
    # joints
    floor[:, i * pw:i * pw + 2] *= 0.55; hgt[:, i * pw:i * pw + 2] = -1
    cut = rng.integers(0, S); floor[cut:cut + 2, i * pw:(i + 1) * pw] *= 0.6; hgt[cut:cut + 2, i * pw:(i + 1) * pw] = -1
save(Image.fromarray(np.clip(floor, 0, 255).astype(np.uint8)), "floor_albedo.jpg")
save(normal_from_height(gaussian_filter(hgt, 1.0), 2.5), "floor_normal.png")

# --- Mur en enduit ---
pl = fbm(512, 512, 6, 6, 20)
wall = np.array([226, 220, 210]) * (0.94 + pl[..., None] * 0.08)
save(Image.fromarray(np.clip(wall, 0, 255).astype(np.uint8)), "wall_albedo.jpg")
save(normal_from_height(gaussian_filter(pl, 0.8), 6.0), "wall_normal.png")

# --- Tissu (maille) : normale qui se répète ---
T = 256
yy, xx = np.mgrid[0:T, 0:T]
knit = (np.sin(xx / T * np.pi * 2 * 48) * 0.5 + 0.5) * (np.sin(yy / T * np.pi * 2 * 64 + np.sin(xx / T * np.pi * 2 * 48) * 1.2) * 0.5 + 0.5)
knit = gaussian_filter(knit + fbm(T, T, 3, 16, 30) * 0.4, 0.6)
save(normal_from_height(knit, 2.2), "fabric_normal.png")

# --- Environnement studio (équirectangulaire) ---
W, H = 1024, 512
v = np.linspace(0, 1, H)[:, None]; u = np.linspace(0, 1, W)[None, :]
sky = np.zeros((H, W, 3))
warm = np.array([255, 236, 210]); cool = np.array([70, 64, 60]); floorc = np.array([120, 96, 72])
top = np.clip(1 - v * 2.2, 0, 1)
sky += (warm * 0.55)[None, None, :] * top[..., None] ** 1.5
sky += cool[None, None, :] * (1 - np.abs(v - 0.5) * 2)[..., None] * 0.9
sky += floorc[None, None, :] * np.clip((v - 0.55) * 2, 0, 1)[..., None] * 0.7
# fenêtres / softbox
for cu, cw in [(0.25, 0.08), (0.62, 0.12)]:
    box = np.exp(-((u - cu) / cw) ** 8) * np.exp(-((v - 0.32) / 0.12) ** 8)
    sky += np.array([255, 250, 240])[None, None, :] * box[..., None] * 0.9
sky = np.clip(sky, 0, 255)
save(Image.fromarray(sky.astype(np.uint8)), "studio_env.jpg")
print("ok", os.listdir(out))
