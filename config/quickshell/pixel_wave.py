#!/usr/bin/env python3
"""
Pixel Wave Video Generator
═══════════════════════════════════════════════════════════════

Génère une vidéo MP4 reproduisant la phase d'apparition (reveal)
de la vague de pixels du lockscreen NieR.

Pixels sépia qui apparaissent en vague depuis le centre, avec
soulèvement par ressort au passage du front.

Usage :
    python pixel_wave.py                        # défaut : 1920x1080 @60fps
    python pixel_wave.py -w 2560 -H 1440        # résolution custom
    python pixel_wave.py --fps 60 -o wave.mp4   # fps + fichier

Dépendances (Arch Linux) :
    sudo pacman -S python-pillow python-numpy ffmpeg

═══════════════════════════════════════════════════════════════
"""

import argparse
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import numpy as np
except ImportError:
    sys.exit("❌ numpy manquant : sudo pacman -S python-numpy")

try:
    from PIL import Image
except ImportError:
    sys.exit("❌ Pillow manquant : sudo pacman -S python-pillow")

if not shutil.which("ffmpeg"):
    sys.exit("❌ ffmpeg manquant : sudo pacman -S ffmpeg")


# ═══════════════════════════════════════════════════════════════
# PARAMÈTRES (reproduits fidèlement du HTML original)
# ═══════════════════════════════════════════════════════════════
CELL = 7            # taille du pixel visible
STEP = 8            # pas de la grille (CELL + GAP 1px)
FRONT_W = 1.2       # largeur du front de vague
LIFT_MAX = 7.0      # soulèvement max au passage du front
SPRING_K = 0.28     # constante du ressort
SPRING_D = 0.62     # amortissement
WAVE_SPEED = 7.2    # vitesse de propagation (cellules/frame à 60fps de réf)

# Couleur de fond (bg sombre du lockscreen)
BG_R, BG_G, BG_B = 11, 9, 6  # #0b0906

# Palette sépia : le pixel atteint (R, G, B) × (luminosité × progress)
SEPIA_R, SEPIA_G, SEPIA_B = 230, 215, 180


# ═══════════════════════════════════════════════════════════════
# DOSSIER DE SORTIE PAR DÉFAUT
# ═══════════════════════════════════════════════════════════════
def default_output() -> Path:
    """~/.config/quickshell/videos/wave.mp4 (respecte XDG_CONFIG_HOME)."""
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg) if xdg else Path.home() / ".config"
    return base / "quickshell" / "videos" / "wave.mp4"


# ═══════════════════════════════════════════════════════════════
# SIMULATION
# ═══════════════════════════════════════════════════════════════
def build_grid(width: int, height: int):
    """Construit la grille et les buffers de simulation."""
    cols = width // STEP
    rows = height // STEP
    off_x = (width - cols * STEP) // 2
    off_y = (height - rows * STEP) // 2
    n = cols * rows

    rng = random.Random(42)  # seed fixe pour reproductibilité

    # Luminosité de base par cellule (78% → 92%)
    target_color = np.array(
        [0.78 + rng.random() * 0.14 for _ in range(n)], dtype=np.float32
    )
    # Jitter radial (rend le front plus organique)
    jitter = np.array(
        [(rng.random() - 0.5) * 4.0 for _ in range(n)], dtype=np.float32
    )

    # État
    progress = np.zeros(n, dtype=np.float32)
    lift = np.zeros(n, dtype=np.float32)
    lift_vel = np.zeros(n, dtype=np.float32)

    return {
        "cols": cols,
        "rows": rows,
        "off_x": off_x,
        "off_y": off_y,
        "n": n,
        "target_color": target_color,
        "jitter": jitter,
        "progress": progress,
        "lift": lift,
        "lift_vel": lift_vel,
    }


def max_dist(cx: float, cy: float, cols: int, rows: int) -> float:
    """Distance maximale d'un point à un coin de la grille."""
    return max(
        math.hypot(cx - c, cy - r)
        for c, r in [(0, 0), (cols - 1, 0), (0, rows - 1), (cols - 1, rows - 1)]
    )


def step_simulation(state, waves, speed_scale: float):
    """Avance la simulation d'une frame."""
    cols = state["cols"]
    rows = state["rows"]
    n = state["n"]
    progress = state["progress"]
    lift = state["lift"]
    lift_vel = state["lift_vel"]
    jitter = state["jitter"]

    # 1. Spring lift (intégration)
    lift_vel *= SPRING_D
    lift_vel -= SPRING_K * lift * SPRING_D
    lift += lift_vel
    mask = (np.abs(lift) < 0.001) & (np.abs(lift_vel) < 0.001)
    lift[mask] = 0
    lift_vel[mask] = 0

    # Pré-calcul des coordonnées cellulaires
    # (optimisation vectorielle)
    c_idx = np.arange(n) % cols
    r_idx = np.arange(n) // cols

    # 2. Propagation des vagues
    for w in waves:
        if w["done"]:
            continue
        w["r"] += WAVE_SPEED * speed_scale
        if w["r"] >= w["max_r"] + FRONT_W * 4:
            w["done"] = True
            continue

        # Distance de chaque cellule au centre de la vague
        d = np.sqrt((c_idx - w["cx"]) ** 2 + (r_idx - w["cy"]) ** 2)
        df = w["r"] - (d + jitter)

        active = df >= -FRONT_W

        if not np.any(active):
            continue

        # Courbe d'ease smoothstep sur le front
        t = np.clip((df + FRONT_W) / (FRONT_W * 2), 0.0, 1.0)
        ease = t * t * (3.0 - 2.0 * t)

        if w["dir"] == 1:
            # Reveal : le pixel prend la valeur max atteinte
            np.maximum(progress, ease * active, out=progress)
        else:
            inv = 1.0 - ease
            np.minimum(progress, np.where(active, inv, progress), out=progress)

        # Soulèvement au passage précis du front
        in_front = (df >= -FRONT_W) & (df < FRONT_W)
        can_lift = lift < 0.1
        if w["dir"] == 1:
            ok = progress < 0.6
        else:
            ok = progress > 0.35
        lift_mask = in_front & can_lift & ok
        lift_vel[lift_mask] = LIFT_MAX * 0.55

    # Retire les vagues terminées
    return [w for w in waves if not w["done"]]


# ═══════════════════════════════════════════════════════════════
# RENDU
# ═══════════════════════════════════════════════════════════════
def render_frame(state, width: int, height: int) -> np.ndarray:
    """Render la frame courante en numpy array (H, W, 3) uint8."""
    # Fond uniforme
    img = np.full((height, width, 3), (BG_R, BG_G, BG_B), dtype=np.uint8)

    cols = state["cols"]
    rows = state["rows"]
    off_x = state["off_x"]
    off_y = state["off_y"]
    progress = state["progress"]
    lift = state["lift"]
    target_color = state["target_color"]

    # Couleur de chaque cellule : v = min(1, p * target)
    v = np.minimum(1.0, progress * target_color)

    # Deux passes : pixels posés (lift ≤ 0.3) puis soulevés (lift > 0.3)
    # comme dans le JS original (les soulevés passent au-dessus)
    for pass_idx in range(2):
        for r in range(rows):
            for c in range(cols):
                i = r * cols + c
                p = progress[i]
                lv = max(0.0, lift[i])

                if pass_idx == 0 and lv > 0.3:
                    continue
                if pass_idx == 1 and lv <= 0.3:
                    continue
                if p < 0.004 and lv < 0.01:
                    continue

                vi = v[i]
                rr = int(min(255, vi * SEPIA_R))
                gg = int(min(255, vi * SEPIA_G))
                bb = int(min(255, vi * SEPIA_B))

                # Taille effective (grossit avec le lift)
                size = int(CELL + lv + 0.5)
                half = lv / 2.0
                px = off_x + c * STEP - int(half)
                py = off_y + r * STEP - int(half)

                # Clamp aux bornes de l'image
                x1 = max(0, px)
                y1 = max(0, py)
                x2 = min(width, px + size)
                y2 = min(height, py + size)
                if x2 > x1 and y2 > y1:
                    img[y1:y2, x1:x2] = (rr, gg, bb)

    return img


# ═══════════════════════════════════════════════════════════════
# PIPELINE VIDÉO
# ═══════════════════════════════════════════════════════════════
def generate_video(
    width: int,
    height: int,
    fps: int,
    duration: float,
    output: Path,
    quality: str = "high",
):
    """Génère la vidéo en pipant les frames vers ffmpeg."""
    # Crée le dossier de sortie s'il n'existe pas
    output.parent.mkdir(parents=True, exist_ok=True)

    print(f"▸ Résolution : {width}×{height} @ {fps}fps")
    print(f"▸ Durée      : {duration:.1f}s")
    print(f"▸ Sortie     : {output}")
    print()

    # Le JS tourne à ~60fps, donc si on rend à 60fps on garde la vitesse.
    # Si on rend à un autre fps, on adapte la vitesse pour que la durée
    # perçue de la vague reste la même.
    speed_scale = 60.0 / fps

    state = build_grid(width, height)
    cols = state["cols"]
    rows = state["rows"]

    # Lance la vague depuis le centre (reveal, dir=1)
    cx = 0.5 * cols
    cy = 0.5 * rows
    waves = [
        {
            "cx": cx,
            "cy": cy,
            "r": 0.0,
            "max_r": max_dist(cx, cy, cols, rows),
            "dir": 1,
            "done": False,
        }
    ]

    total_frames = int(duration * fps)

    # Profils de qualité ffmpeg
    profiles = {
        "high":   ["-crf", "16", "-preset", "slow"],
        "medium": ["-crf", "20", "-preset", "medium"],
        "low":    ["-crf", "26", "-preset", "fast"],
    }

    ffmpeg_cmd = [
        "ffmpeg", "-y",
        "-f", "rawvideo",
        "-vcodec", "rawvideo",
        "-s", f"{width}x{height}",
        "-pix_fmt", "rgb24",
        "-r", str(fps),
        "-i", "-",
        "-an",
        "-vcodec", "libx264",
        "-pix_fmt", "yuv420p",
        *profiles.get(quality, profiles["high"]),
        "-movflags", "+faststart",
        str(output),
    ]

    print("▸ Lancement ffmpeg...")
    proc = subprocess.Popen(
        ffmpeg_cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    try:
        last_pct = -1
        for frame_idx in range(total_frames):
            waves = step_simulation(state, waves, speed_scale)
            frame = render_frame(state, width, height)
            proc.stdin.write(frame.tobytes())

            pct = int(100 * (frame_idx + 1) / total_frames)
            if pct != last_pct:
                bar = "█" * (pct // 2) + "░" * (50 - pct // 2)
                sys.stdout.write(
                    f"\r  [{bar}] {pct:3d}%  ({frame_idx+1}/{total_frames})"
                )
                sys.stdout.flush()
                last_pct = pct

        print()
        proc.stdin.close()
        rc = proc.wait()
        if rc != 0:
            sys.exit(f"\n❌ ffmpeg a échoué (code {rc})")
    except BrokenPipeError:
        sys.exit("\n❌ ffmpeg a fermé le pipe prématurément")
    except KeyboardInterrupt:
        proc.terminate()
        sys.exit("\n⚠ Interrompu par l'utilisateur")

    print()
    print(f"✓ Vidéo générée : {output.resolve()}")
    size_mb = output.stat().st_size / (1024 * 1024)
    print(f"✓ Taille        : {size_mb:.2f} MB")


# ═══════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════
def main():
    p = argparse.ArgumentParser(
        description="Génère une vidéo de la vague de pixels NieR (phase reveal).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemples :
  %(prog)s                            # 1920x1080 60fps 2.5s → ~/.config/quickshell/videos/wave.mp4
  %(prog)s -w 2560 -H 1440            # résolution 1440p
  %(prog)s -d 3.5 --fps 30            # durée 3.5s à 30fps
  %(prog)s -q medium -o boot.mp4      # qualité medium, fichier boot.mp4
        """,
    )
    p.add_argument("-w", "--width", type=int, default=1920, help="largeur (px)")
    p.add_argument("-H", "--height", type=int, default=1080, help="hauteur (px)")
    p.add_argument("--fps", type=int, default=60, help="images par seconde")
    p.add_argument(
        "-d", "--duration", type=float, default=2.5,
        help="durée en secondes (défaut 2.5)",
    )
    p.add_argument(
        "-o", "--output", type=Path, default=default_output(),
        help="fichier de sortie (.mp4) — défaut : ~/.config/quickshell/videos/wave.mp4",
    )
    p.add_argument(
        "-q", "--quality", choices=["low", "medium", "high"], default="high",
        help="qualité d'encodage",
    )
    args = p.parse_args()

    if args.width % STEP != 0 or args.height % STEP != 0:
        print(
            f"⚠ Les dimensions {args.width}×{args.height} ne sont pas multiples "
            f"de {STEP} — la grille sera légèrement décentrée (pas grave)."
        )

    generate_video(
        width=args.width,
        height=args.height,
        fps=args.fps,
        duration=args.duration,
        output=args.output,
        quality=args.quality,
    )


if __name__ == "__main__":
    main()
