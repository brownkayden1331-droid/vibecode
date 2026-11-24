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
    "angry": (222, 98, 72, 255),
    "steam": (190, 190, 200, 255),
    "heart": (240, 80, 110, 255),
    "heart2": (255, 150, 170, 255),
    "note": (110, 130, 230, 255),
    "note2": (200, 120, 220, 255),
    "star": (255, 214, 90, 255),
    "err": (230, 60, 60, 255),
    "err_d": (150, 30, 30, 255),
    "ok": (70, 190, 100, 255),
    "ok_d": (40, 130, 65, 255),
    "back": (192, 114, 86, 255),
    "desk": (140, 95, 62, 255),
    "desk_d": (105, 70, 45, 255),
    "mug": (235, 235, 240, 255),
    "coffee": (110, 70, 45, 255),
    "gold": (255, 200, 60, 255),
    "gold_d": (215, 150, 30, 255),
    "gold_l": (255, 245, 190, 255),
    "chest": (150, 95, 50, 255),
    "chest_d": (105, 62, 32, 255),
    "ball": (210, 215, 225, 255),
    "ball_d": (140, 145, 160, 255),
}
DISCO = [(255, 90, 120, 255), (255, 200, 70, 255), (90, 200, 255, 255), (150, 230, 110, 255), (200, 120, 255, 255)]
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


def clawd(cv, dy=0, dx=0, squash=0, eyes="open", arms=(0, 0), legs=(0, 0, 0, 0),
          airborne=False, blush=False, shadow=True, shade=False, color=None, look=(0, 0)):
    """Draw Clawd.  dy/dx move the whole body (negative dy = up), squash lowers only the
    top edge, arms are a row offset for each 2x2 nub, 'raised' or 'wave', legs lift each
    foot, look nudges the eyes."""
    body = color or C["body"]
    x0, x1 = X0 + dx, X1 + dx
    top = BODY_TOP + dy + squash
    bottom = BODY_TOP + BODY_H - 1 + dy

    if shadow:
        shrink = max(0, -dy) // 2
        cv.rect(X0 + shrink, GROUND, X1 - shrink, GROUND, C["shadow"])

    for i, lx in enumerate((x0, x0 + 2, x1 - 2, x1)):
        end = bottom + 2 - legs[i] if airborne else GROUND - 1 - legs[i]
        cv.rect(lx, bottom + 1, lx, end, body)

    cv.rect(x0, top, x1, bottom, body)
    if shade:
        cv.rect(x0, bottom, x1, bottom, C["shade"])

    ar = top + 2
    for side, a in ((-1, arms[0]), (1, arms[1])):
        edge = x0 if side < 0 else x1
        if a == "raised":   # arm thrown straight up
            cv.px(edge + side, ar + 1, body)
            cv.px(edge + side, ar, body)
            cv.rect(edge + 2 * side, ar - 2, edge + 2 * side, ar, body)
        elif a == "wave":   # raised arm tipped outward
            cv.px(edge + side, ar + 1, body)
            cv.px(edge + side, ar, body)
            cv.px(edge + 2 * side, ar - 1, body)
            cv.rect(edge + 3 * side, ar - 3, edge + 3 * side, ar - 1, body)
        else:
            xa, xb = sorted((edge + side, edge + 2 * side))
            cv.rect(xa, ar + a, xb, ar + a + 1, body)

    ey = top + 1
    for side, ex in ((-1, x0 + 1), (1, x1 - 1)):
        inward = -side
        ex += look[0]
        e = ey + look[1]
        if eyes == "open":
            cv.px(ex, e, C["eye"])
        elif eyes == "wide":
            cv.rect(ex, e, ex, e + 1, C["eye"])
        elif eyes == "down":
            cv.px(ex, e + 1, C["eye"])
        elif eyes == "right":
            cv.px(ex + 1, e, C["eye"])
        elif eyes == "closed":
            cv.pts([(ex, e + 1), (ex + inward, e + 1)], C["eye"])
        elif eyes == "happy":
            cv.pts([(ex - 1, e + 1), (ex, e), (ex + 1, e + 1)], C["eye"])
        elif eyes == "sad":
            cv.pts([(ex, e), (ex + side, e + 1)], C["eye"])
        elif eyes == "angry":
            cv.pts([(ex + side, e), (ex, e + 1)], C["eye"])
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


HEART = [(0, 0), (1, 0), (3, 0), (4, 0), (0, 1), (1, 1), (2, 1), (3, 1), (4, 1), (1, 2), (2, 2), (3, 2), (2, 3)]
NOTE = [(1, 0), (2, 0), (3, 1), (1, 1), (1, 2), (0, 2), (0, 3), (1, 3)]
CHECK = [(4, 0), (3, 1), (0, 2), (2, 2), (1, 3)]
CROSS = [(0, 0), (4, 0), (1, 1), (3, 1), (2, 2), (1, 3), (3, 3), (0, 4), (4, 4)]


def anim_wave():
    frames = []
    for i in range(6):
        cv = Canvas()
        right = "wave" if i % 2 else "raised"
        clawd(cv, eyes="happy" if i in (2, 3) else "open", blush=i in (2, 3), arms=(0, right))
        frames.append(cv.img)
    return frames, 6


def anim_angry():
    frames = []
    for i in range(6):
        cv = Canvas()
        dx = (0, 1, 0, -1, 0, 1)[i]
        fists = (0, 1) if i % 2 == 0 else (1, 0)
        top, _, _ = clawd(cv, dx=dx, eyes="angry", arms=fists, color=C["angry"])
        for k, sx in enumerate((X0 + 1, X1 - 1)):   # steam puffs
            p = (i + k * 3) % 6
            if p < 4:
                y = top - 1 - p
                x = sx + (-1 if k == 0 else 1) * (p // 2)
                col = C["steam"][:3] + (int(255 * (1 - p / 8)),)
                w = 1 if p >= 1 else 0
                cv.rect(min(x, x + w * (-1 if k == 0 else 1)), y - (1 if p >= 2 else 0),
                        max(x, x + w * (-1 if k == 0 else 1)), y, col)
        frames.append(cv.img)
    return frames, 10


def anim_love():
    frames = []
    for i in range(8):
        cv = Canvas()
        sway = (0, 0, 1, 1, 0, 0, -1, -1)[i]
        clawd(cv, dx=sway, eyes="happy", blush=True, arms=(1, 1))
        for k, hx in enumerate((2, 18)):
            p = (i + k * 4) % 8
            if p < 7:
                col = C["heart"] if k == 0 else C["heart2"]
                cv.pts(HEART, col, hx + (p // 2) % 2 - (k), 6 - p)
        frames.append(cv.img)
    return frames, 6


def anim_dance():
    plan = [
        dict(dx=-1, arms=("raised", 1), legs=(1, 0, 0, 0)),
        dict(dy=1, arms=(0, 0)),
        dict(dx=1, arms=(1, "raised"), legs=(0, 0, 0, 1)),
        dict(dy=1, arms=(0, 0)),
        dict(dy=-2, airborne=True, arms=("raised", "raised")),
        dict(dy=1, squash=1, arms=(1, 1)),
        dict(dx=-1, arms=("wave", 0)),
        dict(dx=1, arms=(0, "wave")),
    ]
    frames = []
    for i, f in enumerate(plan):
        cv = Canvas()
        clawd(cv, eyes="happy", **f)
        for k, (nx, col) in enumerate(((2, C["note"]), (19, C["note2"]))):
            p = (i + k * 4) % 8
            if p < 6:
                cv.pts(NOTE, col, nx + (p % 2), 7 - p)
        frames.append(cv.img)
    return frames, 8


def anim_dizzy():
    looks = [(0, 0), (1, 0), (1, 1), (0, 1)]
    orbit = [(-5, 0), (-3, -1), (0, -2), (3, -1), (5, 0), (3, 1), (0, 1), (-3, 1)]
    frames = []
    for i in range(8):
        cv = Canvas()
        dx = (0, 1, 1, 0, 0, -1, -1, 0)[i]
        top, _, _ = clawd(cv, dx=dx, eyes="open", look=looks[i % 4], arms=(1, -1) if i < 4 else (-1, 1))
        cx, cy = 11 + dx, top - 3
        for k in range(3):                       # stars circling the head
            ox, oy = orbit[(i + k * 3) % 8]
            x, y = cx + ox + (1 if ox >= 0 else 0), cy + oy
            cv.px(x, y, C["star"] if oy <= 0 else C["spark2"])
        frames.append(cv.img)
    return frames, 8


def anim_error():
    frames = []
    for i in range(6):
        cv = Canvas()
        red = i in (1, 3)
        top, _, _ = clawd(cv, eyes="wide" if i < 4 else "sad", color=C["err"] if red else None,
                          arms=(-1, -1) if i in (1, 2, 3) else (1, 1))
        if i in (1, 3):                          # glitch: tear a band of rows sideways
            band = cv.img.crop((0, top + 2, W, top + 4))
            cv.img.paste((0, 0, 0, 0), (0, top + 2, W, top + 4))
            cv.img.paste(band, (2 if i == 1 else -2, top + 2))
        bx, by = 17, 0                           # red "x" badge
        cv.rect(bx, by, bx + 6, by + 6, C["err_d"] if i % 2 else C["err"])
        cv.pts(CROSS, (255, 255, 255, 255), bx + 1, by + 1)
        frames.append(cv.img)
    return frames, 8


def anim_success():
    plan = [
        dict(eyes="open"),
        dict(dy=1, squash=1, eyes="happy", arms=(1, 1)),
        dict(eyes="happy", blush=True, arms=(0, "raised")),
        dict(eyes="happy", blush=True, arms=(0, "wave")),
        dict(eyes="happy", blush=True, arms=(0, "raised")),
        dict(eyes="happy", arms=(0, 0)),
    ]
    frames = []
    for i, f in enumerate(plan):
        cv = Canvas()
        clawd(cv, **f)
        if i >= 1:                               # green check badge pops in
            bx, by = 17, 0 if i > 1 else 1
            size = 7 if i > 1 else 5
            cv.rect(bx, by, bx + size - 1, by + size - 1, C["ok"])
            cv.rect(bx, by + size - 1, bx + size - 1, by + size - 1, C["ok_d"])
            if i > 1:
                cv.pts(CHECK, (255, 255, 255, 255), bx + 1, by + 2)
        if i in (2, 4):
            sparkle(cv, 3, 3, i == 2)
        frames.append(cv.img)
    return frames, 6


def clawd_side(cv, facing=1, dx=0, dy=0, arm=0, legs=(0, 0), shadow=True, color=None):
    """Clawd seen side-on (mid-turn): 4 wide, one eye, one arm sticking out front."""
    body = color or C["body"]
    x0, x1 = 10 + dx, 13 + dx
    top, bottom = BODY_TOP + dy, BODY_TOP + BODY_H - 1 + dy
    if shadow:
        cv.rect(x0 - 1, GROUND, x1 + 1, GROUND, C["shadow"])
    for i, lx in enumerate((x0, x1)):
        cv.rect(lx, bottom + 1, lx, GROUND - 1 - legs[i], body)
    cv.rect(x0, top, x1, bottom, body)
    front = x1 if facing > 0 else x0
    xa, xb = sorted((front + facing, front + 2 * facing))
    cv.rect(xa, top + 2 + arm, xb, top + 3 + arm, body)
    cv.px(front - facing, top + 1, C["eye"])
    return top, bottom


COIN = [(1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (3, 1), (0, 2), (1, 2), (2, 2), (3, 2), (1, 3), (2, 3)]
PLUS1 = [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2), (5, 0), (4, 1), (5, 1), (5, 2), (4, 3), (5, 3), (6, 3)]


def coin(cv, x, y):
    cv.pts(COIN, C["gold"], x, y)
    cv.pts([(1, 3), (2, 3), (3, 2)], C["gold_d"], x, y)
    cv.px(x + 1, y + 1, C["gold_l"])


def anim_dance_v2():
    F = "front"
    plan = [
        (F, dict(dx=-1, arms=("raised", "raised"), legs=(1, 0, 0, 0))),
        (F, dict(dy=1, squash=1, arms=(1, 1))),
        (F, dict(dx=1, arms=("raised", "raised"), legs=(0, 0, 0, 1))),
        (F, dict(dy=1, squash=1, arms=(1, 1))),
        ("side", dict(facing=1, arm=-1)),
        ("back", dict(arms=("raised", "raised"))),
        ("side", dict(facing=-1, arm=-1)),
        (F, dict(dy=-2, airborne=True, arms=("raised", "raised"))),
        (F, dict(dy=1, squash=1, arms=(1, 1))),
        (F, dict(dx=-1, arms=("wave", 1), legs=(0, 0, 1, 0))),
        (F, dict(dx=1, arms=(1, "wave"), legs=(0, 1, 0, 0))),
        (F, dict(arms=(0, 0))),
    ]
    spots = [(1, 2), (21, 3), (4, 8), (19, 9), (2, 12), (22, 12), (6, 1), (17, 1), (3, 5), (20, 6)]
    frames = []
    for i, (view, f) in enumerate(plan):
        cv = Canvas()
        for x in range(W):                      # flashing dance floor
            cv.px(x, GROUND, DISCO[((x // 3) + i) % len(DISCO)][:3] + (170,))
        for k, (sx, sy) in enumerate(spots):    # light flecks thrown by the ball
            if (k + i) % 3 == 0:
                cv.px(sx, sy, DISCO[(k + i) % len(DISCO)])
        cv.rect(11, 0, 12, 0, C["ball_d"])      # disco ball
        cv.rect(10, 1, 13, 3, C["ball"])
        cv.rect(11, 4, 12, 4, C["ball"])
        for x in range(10, 14):
            for y in range(1, 4):
                if (x + y + i) % 2:
                    cv.px(x, y, C["ball_d"])
        cv.px(10 + i % 4, 1 + (i // 4) % 3, (255, 255, 255, 255))
        if view == "front":
            clawd(cv, eyes="happy", shadow=False, **f)
        elif view == "back":
            clawd(cv, eyes="none", shadow=False, color=C["back"], **f)
        else:
            clawd_side(cv, shadow=False, **f)
        frames.append(cv.img)
    return frames, 10


CODE_LINES = [(0, 5, 3), (1, 4, 1), (2, 5, 2), (2, 3, 0), (1, 2, 1), (0, 1, 3), (0, 6, 3), (1, 3, 2),
              (1, 6, 0), (2, 4, 1), (1, 2, 3), (0, 1, 3)]  # (indent, length, colour)


def anim_coding_v2():
    frames = []
    for i in range(12):
        cv = Canvas()
        cv.rect(2, 10, 21, 10, C["desk"])               # desk top
        cv.rect(2, 11, 21, 11, C["desk_d"])
        cv.rect(3, 12, 3, 14, C["desk_d"])
        cv.rect(20, 12, 20, 14, C["desk_d"])
        cv.rect(5, 0, 18, 7, C["panel_b"])              # monitor
        cv.rect(6, 1, 17, 6, C["panel"])
        cv.rect(11, 8, 12, 9, C["panel_b"])             # stand
        for row in range(5):                            # code scrolling up
            ind, ln, col = CODE_LINES[(i + row) % len(CODE_LINES)]
            if row == 4:
                ln = min(ln, 1 + i % 3 * 2)             # newest line is being typed
            for x in range(ln):
                cv.px(7 + ind + x, 2 + row, CODE_COLS[col])
            if row == 4 and i % 2 == 0:
                cv.px(7 + ind + ln, 2 + row, (240, 240, 240, 255))
        cv.rect(18, 8, 19, 9, C["mug"])                 # coffee mug + steam
        cv.px(20, 8, C["mug"])
        cv.px(18, 8, C["coffee"])
        sx = 18 + (i // 2) % 2
        cv.px(sx, 7 - (i % 2), C["steam"][:3] + (160,))
        cv.px(19 - (i // 2) % 2, 5 + (i % 2), C["steam"][:3] + (110,))
        bob = 1 if i % 4 == 3 else 0
        typing = (0, 1) if i % 2 == 0 else (1, 0)
        clawd(cv, dy=bob, eyes="none", color=C["back"], arms=typing)
        frames.append(cv.img)
    return frames, 10


def anim_claiming():
    D = -3                                              # Clawd shifted left, chest on the right
    frames = []
    for i in range(12):
        cv = Canvas()
        cx0 = 17 + ((1, -1)[i % 2] if i in (1, 2) else 0)
        opened = i >= 3
        cv.rect(cx0, 12, cx0 + 5, 14, C["chest"])       # chest
        cv.rect(cx0, 14, cx0 + 5, 14, C["chest_d"])
        if opened:
            cv.rect(cx0, 9, cx0 + 5, 10, C["chest_d"])  # lid flipped up
            cv.rect(cx0 + 1, 11, cx0 + 4, 11, C["gold"])
            if i in (3, 4):
                for k, (rx, ry) in enumerate(((cx0 + 1, 7), (cx0 + 3, 6), (cx0 + 5, 7))):
                    cv.px(rx, ry - (i - 3), C["gold_l"])
        else:
            cv.rect(cx0, 11, cx0 + 5, 11, C["chest_d"])
            cv.rect(cx0 + 2, 12, cx0 + 3, 12, C["gold"])
        shadow_x = (8 + D, 15 + D)
        if i < 5:
            top, _, _ = clawd(cv, dx=D, eyes="right" if i else "open", arms=(0, 0), shadow=False)
            cv.rect(shadow_x[0], GROUND, shadow_x[1], GROUND, C["shadow"])
        if i == 4:
            coin(cv, cx0 + 1, 6)
        elif i == 5:
            clawd(cv, dx=D, eyes="wide", arms=(0, "wave"), shadow=False)
            cv.rect(shadow_x[0], GROUND, shadow_x[1], GROUND, C["shadow"])
            coin(cv, 15, 2)
        elif i == 6:
            top, _, _ = clawd(cv, dx=D, eyes="happy", arms=(0, "raised"), shadow=False)
            cv.rect(shadow_x[0], GROUND, shadow_x[1], GROUND, C["shadow"])
            coin(cv, X1 + D + 1, top - 4)
        elif i >= 7:
            jump = {8: -2, 9: -2, 10: -1}.get(i, 0)
            top, _, _ = clawd(cv, dx=D, dy=jump, airborne=jump < 0, eyes="happy", blush=True,
                              arms=("raised", "raised"), shadow=False)
            cv.rect(shadow_x[0] + (1 if jump else 0), GROUND, shadow_x[1] - (1 if jump else 0), GROUND, C["shadow"])
            coin(cv, 10 + D, top - 5)
            if i in (8, 9, 10):
                cv.pts(PLUS1, C["gold"], 15, max(0, 2 - (i - 8)))
            if i in (7, 9):
                sparkle(cv, 3 + D + 1, 2, True)
                sparkle(cv, 14, 7, False)
            if i in (8, 10):
                sparkle(cv, 14, 4, True)
                sparkle(cv, 1, 6, False)
        frames.append(cv.img)
    return frames, 8


def spinner_glyph(cv, stage, rot, cx=11.5, cy=3.5):
    """Pixel take on Claude Code's spinner: · ✢ ✳ ✶ ✻ ✽ (stage 0-5)."""
    import math
    core, tip = (232, 128, 92, 255), (255, 196, 160, 255)
    cv.rect(11, 3, 12, 4, core)
    if stage == 0:
        return
    rays, length = [(4, 2.2), (8, 2.2), (6, 3.4), (8, 3.4), (8, 3.9)][stage - 1]
    for k in range(rays):
        ang = rot + k * 2 * math.pi / rays
        t = 1.0
        while t <= length:
            x, y = cx + t * math.cos(ang), cy + t * math.sin(ang)
            if math.floor(y) <= 5:  # keep a gap above the head
                cv.px(math.floor(x), math.floor(y), tip if t > length - 0.6 else core)
            t += 0.5


def anim_clauding():
    import math
    stages = [0, 1, 2, 3, 4, 5, 5, 4, 3, 2, 1, 0]
    frames = []
    for i, st in enumerate(stages):
        cv = Canvas()
        spinner_glyph(cv, st, rot=i * math.pi / 12)
        sq = (0, 0, 1, 1)[i % 4]
        arms = (-1, 0) if i % 2 == 0 else (0, -1)
        eyes = "closed" if i == 9 else ("happy" if st == 5 else "open")
        clawd(cv, squash=sq, eyes=eyes, arms=arms)
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
    "wave": anim_wave,
    "angry": anim_angry,
    "love": anim_love,
    "dance": anim_dance,
    "dizzy": anim_dizzy,
    "error": anim_error,
    "success": anim_success,
    "dance_v2": anim_dance_v2,
    "coding_v2": anim_coding_v2,
    "claiming": anim_claiming,
    "clauding": anim_clauding,
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


KEY = (255, 0, 255)


def gif_transparent(frames, path, fps):
    """1-bit transparent GIF: pixels under 50% alpha become transparent."""
    flat = []
    for f in frames:
        rgb = Image.new("RGB", f.size, KEY)
        a = f.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
        rgb.paste(f.convert("RGB"), mask=a)
        flat.append(upscale(rgb))
    pal_src = Image.new("RGB", (flat[0].width, flat[0].height * len(flat)))
    for i, f in enumerate(flat):
        pal_src.paste(f, (0, i * f.height))
    pal = pal_src.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    out = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in flat]
    colours = pal.getpalette()[:768]
    key = min(range(len(colours) // 3), key=lambda i: sum(abs(colours[i * 3 + c] - KEY[c]) for c in range(3)))
    out[0].save(path, save_all=True, append_images=out[1:], duration=round(1000 / fps),
                loop=0, disposal=2, transparency=key, optimize=False)


def main():
    os.makedirs(os.path.join(OUT, "sheets"), exist_ok=True)
    for d in ("gif", "gif_transparent", "apng", "frames"):
        os.makedirs(os.path.join(OUT, d), exist_ok=True)
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
        gif_transparent(frames, os.path.join(OUT, "gif_transparent", f"{name}.gif"), fps)
        big = [upscale(f) for f in frames]
        big[0].save(os.path.join(OUT, "apng", f"{name}.png"), save_all=True, append_images=big[1:],
                    duration=round(1000 / fps), loop=0, disposal=1)
        fdir = os.path.join(OUT, "frames", name)
        os.makedirs(fdir, exist_ok=True)
        for i, f in enumerate(big):
            f.save(os.path.join(fdir, f"{name}_{i:02d}.png"))
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
