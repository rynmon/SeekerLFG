"""Seeker LFG's project icon: a bronze-ringed portrait badge with a glowing green slit-pupil eye.
Drawn at 1024px and scaled down, so every edge is smooth. Original art (no game assets).
Run from the repository root (needs numpy and Pillow): python assets/icon/make_icon.py assets/icon"""
import sys
import numpy as np
from PIL import Image, ImageFilter

S = 1024
c = S / 2
y, x = np.mgrid[0:S, 0:S].astype(np.float64)
dx, dy = x - c, y - c
r = np.hypot(dx, dy)

img = np.zeros((S, S, 4), dtype=np.float64)

def over(rgb, alpha):
    """Paint rgb (HxWx3 or 3-tuple) with alpha (HxW, 0..1) over img."""
    a = np.clip(alpha, 0, 1)[..., None]
    col = np.broadcast_to(np.asarray(rgb, dtype=np.float64), (S, S, 3))
    img[..., :3] = img[..., :3] * (1 - a) + col * a
    img[..., 3:] = img[..., 3:] * (1 - a) + a

def disc(radius, soft=1.5):
    return np.clip((radius - r) / soft + 0.5, 0, 1)

R_OUT, R_RING_IN = 500, 420

# Bronze ring: a bevel lit from the top left (brighter where the surface faces the light).
ring = disc(R_OUT) * (1 - disc(R_RING_IN))
t = (r - R_RING_IN) / (R_OUT - R_RING_IN)            # 0 inner edge .. 1 outer edge
bevel = np.sin(np.clip(t, 0, 1) * np.pi)              # raised in the middle
light = (-dx - dy) / (np.sqrt(2) * np.maximum(r, 1))  # +1 facing top-left
shade = 0.18 + 0.55 * bevel + 0.38 * light * bevel
dark_bronze = np.array([58, 34, 12])
gold = np.array([246, 206, 120])
k = np.clip(shade, 0, 1)[..., None]
over(dark_bronze * (1 - k) + gold * k, ring)
# A thin dark groove each side of the ring, as the game's portrait frames have.
for rr, w in ((R_OUT - 6, 5), (R_RING_IN + 5, 5)):
    groove = np.clip(1 - np.abs(r - rr) / w, 0, 1) * 0.55
    over((40, 24, 10), groove)

# The inside: deep teal-black, a little lighter in the middle.
inner = disc(R_RING_IN)
g = np.clip(r / R_RING_IN, 0, 1)[..., None]
over(np.array([24, 40, 38]) * (1 - g) + np.array([6, 10, 12]) * g, inner)

# The eye: an almond, x across [-W, W], half-height H*(1-(x/W)^2).
W, H = 372, 214
u = dx / W
half = H * np.clip(1 - u ** 2, 0, None)
almond = np.clip((half - np.abs(dy)) / 2 + 0.5, 0, 1) * (np.abs(u) < 1)

# A soft green glow around the eye.
glow_r = np.hypot(dx / (W * 1.05), dy / (H * 1.6))
over((70, 200, 60), np.clip(1 - glow_r, 0, 1) ** 2 * 0.55 * inner)

# Dark lids (the almond's outline), then the iris: bright yellow-green in the middle to deep green.
lid = np.clip((half + 18 - np.abs(dy)) / 2 + 0.5, 0, 1) * (np.abs(u) < 1.06)
over((12, 20, 10), lid)
ir = np.clip(np.hypot(dx / 330, dy / 330), 0, 1)[..., None]
iris = np.array([214, 255, 96]) * (1 - ir) ** 1.4 + np.array([22, 110, 30]) * (1 - (1 - ir) ** 1.4)
over(iris, almond)
# Fine streaks radiating from the pupil, as an iris has.
ang = np.arctan2(dy, dx)
streak = (0.5 + 0.5 * np.sin(ang * 46)) * np.clip((np.hypot(dx, dy) - 60) / 200, 0, 1) * 0.18
over((10, 60, 15), streak * almond)

# The slit pupil: a tall, narrow ellipse, with a darker rim.
pr = np.hypot(dx / 38, dy / 190)
over((20, 40, 12), np.clip((1.25 - pr) * 8, 0, 1) * almond * 0.7)
over((4, 6, 4), np.clip((1 - pr) * 10, 0, 1) * almond)

# A highlight on the eye's upper left.
hr = np.hypot((dx + 110) / 50, (dy + 80) / 32)
over((255, 255, 240), np.clip(1 - hr, 0, 1) ** 1.5 * 0.85 * almond)

img[..., 3] *= 255 # coverage was 0..1 while painting
out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGBA")
out = out.filter(ImageFilter.GaussianBlur(0.6))
dest = sys.argv[1]
out.resize((400, 400), Image.LANCZOS).save(dest + "/curseforge-icon.png", optimize=True)
out.save(dest + "/icon-1024.png", optimize=True)
print("saved")
