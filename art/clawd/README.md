# Clawd sprites

Pixel-art animations of Clawd, drawn at native resolution (1 px = 1 block: 8×6 body,
1×1 eyes, 2×2 arms, four 1×2 legs). Frames are 24×16 with room for effects.

| anim      | frames | fps |
|-----------|-------:|----:|
| idle      | 8 | 6  |
| walk      | 4 | 8  |
| happy     | 8 | 10 |
| sad       | 8 | 5  |
| coding    | 8 | 8  |
| thinking  | 8 | 4  |
| sleep     | 8 | 3  |
| surprised | 6 | 8  |

- `sheets/<anim>.png` – horizontal strip, 1×, transparent (use with nearest-neighbour scaling)
- `sheets/<anim>@10x.png` – same strip at 10×
- `gif/<anim>.gif` – animated previews
- `atlas.png` + `atlas.json` – every animation, one row each, with frame size / fps
- `preview.png` – labelled contact sheet

Regenerate with `python3 art/clawd/generate.py` (needs Pillow).
