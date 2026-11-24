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
| wave      | 6 | 6  |
| angry     | 6 | 10 |
| love      | 8 | 6  |
| dance     | 8 | 8  |
| dizzy     | 8 | 8  |
| error     | 6 | 8  |
| success   | 6 | 6  |
| dance_v2  | 12 | 10 |
| coding_v2 | 12 | 10 |
| claiming  | 12 | 8  |
| clauding  | 12 | 8  |

- `sheets/<anim>.png` – horizontal strip, 1×, transparent (use with nearest-neighbour scaling)
- `sheets/<anim>@10x.png` – same strip at 10×
- `gif_transparent/<anim>.gif` – animated GIF, 10×, transparent background (1-bit alpha, so the soft ground shadow is dropped)
- `apng/<anim>.png` – animated PNG, 10×, full alpha (keeps the shadow); plays in browsers, Discord, etc.
- `frames/<anim>/<anim>_NN.png` – every frame as its own transparent 10× PNG
- `gif/<anim>.gif` – animated previews on a cream background
- `atlas.png` + `atlas.json` – every animation, one row each, with frame size / fps
- `preview.png` – labelled contact sheet

Regenerate with `python3 art/clawd/generate.py` (needs Pillow).
