"""Clawd pixel-art sprite generator.

Draws every frame procedurally on a small pixel grid, then exports:
  sheets/<anim>.png    horizontal strip, 1x, transparent (game-ready)
  sheets/<anim>@10x.png same strip scaled 10x (nearest neighbour)
  gif/<anim>.gif       animated preview, 10x
  atlas.png/.json      all animations, one row each, 1x, with frame metadata
  preview.png          labelled contact sheet

Run:  python3 art/clawd/generate.py
"""
import json
import os

from PIL import Image, ImageDraw, ImageFont

OUT = os.path.dirname(os.path.abspath(__file__))

# Clawd at native resolution: one pixel = one block of the reference art.
#   body 8x6, eyes 1x1 (col 1 & 6, row 1), arms 2x2 (rows 2-3), legs 1x2 at cols 0,2,5,7
W, H = 24, 16          # frame size; spare room above/right for effects
X0, X1 = 8, 15         # body columns
BODY_TOP, BODY_H = 7, 6
GROUND = 15            # shadow row; legs fill the two rows above it
SCALE = 10

C = {
    "body": (205, 125, 95, 255),
    "shade": (176, 100, 74, 255),
    "eye": (20, 20, 20, 255),
    "shadow": (0, 0, 0, 55),
    "blush": (240, 150, 160, 255),
    "tear": (120, 190, 245, 255),
    "spark": (255, 214, 90, 255),
    "spark2": (255, 245, 200, 255),
    "cloud": (150, 156, 172, 255),
    "cloud_d": (118, 124, 140, 255),
    "rain": (120, 170, 230, 255),
    "lid": (72, 74, 84, 255),
    "lid_hi": (110, 112, 124, 255),
    "panel": (36, 38, 48, 255),
    "panel_b": (88, 92, 108, 255),
    "bubble": (250, 250, 252, 255),
    "bubble_o": (70, 70, 80, 255),
    "zzz": (190, 205, 245, 255),
}
CODE_COLS = [(230, 140, 105, 255), (120, 180, 255, 255), (140, 210, 130, 255), (200, 150, 240, 255)]


class Canvas:
    def __init__(self):
        self.img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        self.p = self.img.load()

    def px(self, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            r, g, b, a = self.p[x, y]
            if c[3] < 255 and a:
                t = c[3] / 255
                c = (int(r + (c[0] - r) * t), int(g + (c[1] - g) * t), int(b + (c[2] - b) * t), 255)
            self.p[x, y] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.px(x, y, c)

    def pts(self, pts, c, ox=0, oy=0):
        for x, y in pts:
            self.px(x + ox, y + oy, c)


def clawd(cv, dy=0, squash=0, eyes="open", arms=(0, 0), legs=(0, 0, 0, 0),
          airborne=False, blush=False, shadow=True, shade=False):
    """Draw Clawd.  dy moves the whole body (negative = up), squash lowers only the
    top edge, arms are a row offset for each 2x2 nub or 'raised', legs lift each foot."""
    top = BODY_TOP + dy + squash
    bottom = BODY_TOP + BODY_H - 1 + dy

    if shadow:
        shrink = max(0, -dy) // 2
        cv.rect(X0 + shrink, GROUND, X1 - shrink, GROUND, C["shadow"])

    for i, lx in enumerate((X0, X0 + 2, X1 - 2, X1)):
        end = bottom + 2 - legs[i] if airborne else GROUND - 1 - legs[i]
        cv.rect(lx, bottom + 1, lx, end, C["body"])

    cv.rect(X0, top, X1, bottom, C["body"])
    if shade:
        cv.rect(X0, bottom, X1, bottom, C["shade"])

    ar = top + 2
    for side, a in ((-1, arms[0]), (1, arms[1])):
        edge = X0 if side < 0 else X1
        if a == "raised":   # arm thrown up diagonally
            cv.px(edge + side, ar + 1, C["body"])
            cv.px(edge + side, ar, C["body"])
            cv.rect(edge + 2 * side, ar - 2, edge + 2 * side, ar, C["body"])
        else:
            xa, xb = sorted((edge + side, edge + 2 * side))
            cv.rect(xa, ar + a, xb, ar + a + 1, C["body"])

    ey = top + 1
    for side, ex in ((-1, X0 + 1), (1, X1 - 1)):
        inward = -side
        if eyes == "open":
            cv.px(ex, ey, C["eye"])
        elif eyes == "wide":
            cv.rect(ex, ey, ex, ey + 1, C["eye"])
        elif eyes == "down":
            cv.px(ex, ey + 1, C["eye"])
        elif eyes == "right":
            cv.px(ex + 1, ey, C["eye"])
        elif eyes == "closed":
            cv.pts([(ex, ey + 1), (ex + inward, ey + 1)], C["eye"])
        elif eyes == "happy":
            cv.pts([(ex - 1, ey + 1), (ex, ey), (ex + 1, ey + 1)], C["eye"])
        elif eyes == "sad":
            cv.pts([(ex, ey), (ex + side, ey + 1)], C["eye"])
        if blush:
            cv.px(ex + side, ey + 2, C["blush"])
    return top, bottom, ey


# ---------------------------------------------------------------- effects
def sparkle(cv, x, y, big):
    if big:
        cv.px(x, y, C["spark2"])
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            cv.px(x + dx, y + dy, C["spark"])
    else:
        cv.px(x, y, C["spark"])


Z_GLYPH = [(0, 0), (1, 0), (2, 0), (1, 1), (0, 2), (1, 2), (2, 2)]


# ---------------------------------------------------------------- animations
def anim_idle():
    frames = []
    for i, dy in enumerate([0, 0, 0, 0, 1, 1, 1, 1]):
        cv = Canvas()
        clawd(cv, squash=dy, eyes="closed" if i == 6 else "open")
        frames.append(cv.img)
    return frames, 6


def anim_walk():
    plan = [
        dict(legs=(1, 0, 1, 0), arms=(-1, 1)),
        dict(dy=1, arms=(0, 0)),
        dict(legs=(0, 1, 0, 1), arms=(1, -1)),
        dict(dy=1, arms=(0, 0)),
    ]
    frames = []
    for f in plan:
        cv = Canvas()
        clawd(cv, **f)
        frames.append(cv.img)
    return frames, 8


def anim_happy():
    plan = [
        dict(),
        dict(squash=1, dy=1, arms=(1, 1)),
        dict(dy=-3, airborne=True, arms=("raised", "raised"), legs=(1, 0, 0, 1)),
        dict(dy=-4, airborne=True, arms=("raised", "raised")),
        dict(dy=-4, airborne=True, arms=("raised", "raised")),
        dict(dy=-2, airborne=True, arms=("raised", "raised"), legs=(0, 1, 1, 0)),
        dict(squash=1, dy=1, arms=(-1, -1)),
        dict(),
    ]
    sparks = {3: [(3, 3, True), (20, 1, False), (21, 8, False)],
              4: [(3, 3, False), (20, 2, True), (4, 9, False)],
              5: [(20, 2, False), (2, 6, False)]}
    frames = []
    for i, f in enumerate(plan):
        cv = Canvas()
        clawd(cv, eyes="happy", blush=True, **f)
        for s in sparks.get(i, []):
            sparkle(cv, *s)
        frames.append(cv.img)
    return frames, 10


def anim_sad():
    frames = []
    for i, sq in enumerate([1, 1, 1, 1, 2, 2, 1, 1]):
        cv = Canvas()
        _, _, ey = clawd(cv, squash=sq, eyes="sad", arms=(1, 1))
        ty = ey + 1 + i
        if 0 < i and ty <= GROUND - 1:          # tear rolling down
            cv.px(X0 + 1, ty, C["tear"])
        cv.rect(X0 + 2, 0, X1 - 2, 0, C["cloud"])   # tiny rain cloud
        cv.rect(X0, 1, X1, 1, C["cloud"])
        cv.rect(X0 + 1, 2, X1 - 1, 2, C["cloud_d"])
        for k, rx in enumerate((X0 + 1, X0 + 4, X1 - 1)):
            cv.px(rx, 3 + (i + k * 2) % 3, C["rain"])
        frames.append(cv.img)
    return frames, 5


def anim_coding():
    lines = [(0, 4, 0), (1, 3, 1), (2, 4, 2)]  # (row, length, colour)
    total = sum(l for _, l, _ in lines)
    frames = []
    for i in range(8):
        cv = Canvas()
        _, bottom, _ = clawd(cv, eyes="down", arms=(1, 2) if i % 2 == 0 else (2, 1))
        cv.rect(X0 + 1, bottom - 1, X1 - 1, GROUND - 1, C["lid"])     # laptop lid (back)
        cv.rect(X0 + 1, bottom - 1, X1 - 1, bottom - 1, C["lid_hi"])
        cv.rect(X0 + 3, bottom + 1, X0 + 4, bottom + 1, C["lid_hi"])
        px0, py0 = 17, 0                                              # floating editor
        cv.rect(px0, py0, px0 + 6, py0 + 5, C["panel_b"])
        cv.rect(px0 + 1, py0 + 1, px0 + 5, py0 + 4, C["panel"])
        shown = (total * (i + 1)) // 8
        cursor = None
        for row, length, colour in lines:
            n = max(0, min(length, shown))
            indent = 1 if colour == 1 else 0
            for x in range(n):
                cv.px(px0 + 1 + indent + x, py0 + 2 + row, CODE_COLS[colour])
            if n and (cursor is None or n < length or shown >= 0):
                cursor = (px0 + 1 + indent + n, py0 + 2 + row)
            shown -= length
        if cursor and i % 2 == 0 and cursor[0] <= px0 + 5:
            cv.px(*cursor, (240, 240, 240, 255))
        frames.append(cv.img)
    return frames, 8


def anim_thinking():
    frames = []
    for i in range(8):
        cv = Canvas()
        clawd(cv, eyes="right", arms=(0, -1 if i % 2 == 0 else 0))
        if i >= 1:
            cv.px(17, 6, C["bubble_o"])
        if i >= 2:
            cv.px(18, 5, C["bubble_o"])
        if i >= 3:
            bx0, by0, bx1, by1 = 17, 0, 23, 4
            cv.rect(bx0 + 1, by0, bx1 - 1, by1, C["bubble_o"])
            cv.rect(bx0, by0 + 1, bx1, by1 - 1, C["bubble_o"])
            cv.rect(bx0 + 1, by0 + 1, bx1 - 1, by1 - 1, C["bubble"])
            for d in range((i - 3) % 4):
                cv.px(bx0 + 1 + d * 2, by0 + 2, C["bubble_o"])
        frames.append(cv.img)
    return frames, 4


def anim_sleep():
    frames = []
    for i, sq in enumerate([0, 0, 1, 1, 1, 1, 0, 0]):
        cv = Canvas()
        clawd(cv, dy=1, squash=sq, eyes="closed", arms=(1, 1))
        for k in range(2):
            p = (i + k * 4) % 8
            zx, zy = 17 + p // 2, 5 - (p * 3) // 4
            a = int(255 * (1 - p / 14))
            cv.pts(Z_GLYPH, C["zzz"][:3] + (a,), zx, zy)
        frames.append(cv.img)
    return frames, 3


def anim_surprised():
    plan = [
        dict(),
        dict(dy=-2, airborne=True, eyes="wide", arms=("raised", "raised")),
        dict(dy=-2, airborne=True, eyes="wide", arms=("raised", "raised")),
        dict(squash=1, dy=1, eyes="wide", arms=(-1, -1)),
        dict(eyes="wide"),
        dict(eyes="closed"),
    ]
    frames = []
    for i, f in enumerate(plan):
        cv = Canvas()
        f.setdefault("eyes", "open")
        top, _, _ = clawd(cv, **f)
        if i in (1, 2, 3):                       # "!" over the head
            cv.rect(11, top - 5, 12, top - 3, C["spark"])
            cv.rect(11, top - 1, 12, top - 1, C["spark"])
        frames.append(cv.img)
    return frames, 8


ANIMS = {
    "idle": anim_idle,
    "walk": anim_walk,
    "happy": anim_happy,
    "sad": anim_sad,
    "coding": anim_coding,
    "thinking": anim_thinking,
    "sleep": anim_sleep,
    "surprised": anim_surprised,
}


# ---------------------------------------------------------------- export
def upscale(img, s=SCALE):
    return img.resize((img.width * s, img.height * s), Image.NEAREST)


def strip(frames):
    out = Image.new("RGBA", (W * len(frames), H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.paste(f, (i * W, 0))
    return out


def on_bg(img, bg=(245, 240, 232, 255)):
    base = Image.new("RGBA", img.size, bg)
    base.alpha_composite(img)
    return base


def main():
    os.makedirs(os.path.join(OUT, "sheets"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "gif"), exist_ok=True)
    data = {name: fn() for name, fn in ANIMS.items()}

    meta = {"frameWidth": W, "frameHeight": H, "animations": {}}
    max_frames = max(len(f) for f, _ in data.values())
    atlas = Image.new("RGBA", (W * max_frames, H * len(data)), (0, 0, 0, 0))
    for row, (name, (frames, fps)) in enumerate(data.items()):
        s = strip(frames)
        s.save(os.path.join(OUT, "sheets", f"{name}.png"))
        upscale(s).save(os.path.join(OUT, "sheets", f"{name}@{SCALE}x.png"))
        gif = [upscale(on_bg(f)).convert("RGB").quantize(64) for f in frames]
        gif[0].save(os.path.join(OUT, "gif", f"{name}.gif"), save_all=True, append_images=gif[1:],
                    duration=round(1000 / fps), loop=0, disposal=2)
        atlas.paste(s, (0, row * H))
        meta["animations"][name] = {"row": row, "y": row * H, "frames": len(frames), "fps": fps, "loop": True}
    atlas.save(os.path.join(OUT, "atlas.png"))
    with open(os.path.join(OUT, "atlas.json"), "w") as fh:
        json.dump(meta, fh, indent=2)

    # labelled contact sheet
    ps, label_w, pad = 8, 130, 8
    font = ImageFont.load_default(size=16)
    sheet = Image.new("RGBA", (label_w + max_frames * (W * ps + pad), len(data) * (H * ps + pad) + pad),
                      (250, 249, 245, 255))
    d = ImageDraw.Draw(sheet)
    for row, (name, (frames, fps)) in enumerate(data.items()):
        y = pad + row * (H * ps + pad)
        d.text((10, y + H * ps // 2 - 18), name, fill=(40, 40, 40), font=font)
        d.text((10, y + H * ps // 2 + 2), f"{len(frames)}f @ {fps}fps", fill=(120, 120, 120), font=font)
        for i, f in enumerate(frames):
            x = label_w + i * (W * ps + pad)
            d.rectangle([x, y, x + W * ps - 1, y + H * ps - 1], fill=(238, 232, 222))
            sheet.alpha_composite(upscale(f, ps), (x, y))
    sheet.convert("RGB").save(os.path.join(OUT, "preview.png"))
    print("wrote", ", ".join(data))


if __name__ == "__main__":
    main()
