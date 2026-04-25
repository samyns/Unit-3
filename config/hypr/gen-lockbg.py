#!/usr/bin/env python3
# gen-lockbg.py — Génère un fond sépia avec texture pixel wave
# Usage: python3 gen-lockbg.py /chemin/output.png

import sys, random, math
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    # Fallback sans PIL : créer un PNG minimal uni
    sys.exit(0)

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/lockbg.png"

W, H   = 1920, 1080
CELL   = 7
GAP    = 1
STEP   = CELL + GAP
cols   = W // STEP
rows   = H // STEP

img  = Image.new("RGB", (W, H), (11, 9, 6))
draw = ImageDraw.Draw(img)

random.seed(42)  # seed fixe pour cohérence visuelle

# Simuler l'état final de la vague (tout révélé)
# depuis le centre, chaque pixel a une luminosité aléatoire uniforme
cx, cy = cols / 2, rows / 2

for r in range(rows):
    for c in range(cols):
        # Luminosité : uniforme 78%..92% avec jitter
        lum = 0.78 + random.random() * 0.14
        # Légère variation selon la distance au centre (pixels centraux légèrement plus clairs)
        dist = math.sqrt((c - cx)**2 + (r - cy)**2) / math.sqrt(cx**2 + cy**2)
        lum = lum * (1 - dist * 0.08)

        rr = min(255, int(lum * 230))
        gg = min(255, int(lum * 215))
        bb = min(255, int(lum * 180))

        x = c * STEP
        y = r * STEP
        draw.rectangle([x, y, x + CELL - 1, y + CELL - 1], fill=(rr, gg, bb))

img.save(out, "PNG", optimize=False, compress_level=1)
print(f"Generated {out}")
