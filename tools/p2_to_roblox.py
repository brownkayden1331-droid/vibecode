#!/usr/bin/env python3
"""
p2_to_roblox.py - turn a Portal 2 map into a Roblox model (.rbxmx) for this game.

    python p2_to_roblox.py mp_coop_lobby_3.vmf -o CoopHub.rbxmx --name CoopHub
    python p2_to_roblox.py sp_a1_intro1.bsp  -o Intro.rbxmx

Input
    .vmf   Hammer source file (best). Get one from a .bsp with BSPSource (decompiler).
    .bsp   a compiled map (experimental: brushes + entities are read straight from it).

Output (one .rbxmx you drag into Studio, or right-click > Insert from File)
    Model <name>
      Geometry   the map's brushes: Parts (boxes, also rotated ones), WedgeParts (ramps), and thin wedge pairs
                 for every other shape. Each gets the MaterialVariant from p2_materials.json (your MaterialService
                 names), surfaces you can't portal on get the tag P2NoPortal.
      Entities   PlayerSpawn / PlayerSpawnBlue / PlayerSpawnOrange (co-op), placeholders for test elements
                 (buttons, cubes, doors, turrets, lasers, funnels, bridges, fizzlers, faith plates) and lights
      P2MapSetup a Script: when the map is in Workspace it switches every part to its variant's BaseMaterial,
                 adds NoPortal, and swaps the placeholders for the real models from ReplicatedStorage.PortalAssets.
                 (Run its code in the command bar to see it in edit mode too.)

For the co-op hub: convert the lobby, put the model in ServerStorage.PortalMaps and name it CoopHub.
Units: 14.7 Hammer units = 1 stud (the same as the portal gun's U); change with --scale.
Only the Python standard library is used.
"""
import argparse
import base64
import io
import json
import lzma
import math
import os
import re
import struct
import sys
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
EPS = 1e-4

# ---------------------------------------------------------------------------------------------------------------
# small vector maths
# ---------------------------------------------------------------------------------------------------------------
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def mul(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def length(a): return math.sqrt(dot(a, a))
def unit(a):
    l = length(a)
    return (a[0] / l, a[1] / l, a[2] / l) if l > 1e-12 else (0.0, 0.0, 0.0)

# ---------------------------------------------------------------------------------------------------------------
# reading maps
# ---------------------------------------------------------------------------------------------------------------
class Brush:
    """a convex solid: planes (outward normal n, dist d: inside is n.x <= d) with a texture per side"""
    def __init__(self, sides, entity="worldspawn", contents=1):
        self.sides = sides          # [(normal, dist, texture)]
        self.entity = entity        # classname of the entity it belongs to
        self.contents = contents

def parse_keyvalues(text):
    """Valve KeyValues (VMF / entity lump) -> nested [ (key, value or list) ]"""
    tokens = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])|([^\s{}"]+)', text)
    pos = 0
    def block():
        nonlocal pos
        out = []
        while pos < len(tokens):
            q, br, bare = tokens[pos]
            if br == "}":
                pos += 1
                return out
            if br == "{":  # (stray brace)
                pos += 1
                out.append(("", block()))
                continue
            key = q if q or not bare else bare
            pos += 1
            if pos >= len(tokens):
                break
            q2, br2, bare2 = tokens[pos]
            if br2 == "{":
                pos += 1
                out.append((key, block()))
            else:
                out.append((key, q2 if q2 or not bare2 else bare2))
                pos += 1
        return out
    return block()

def kv_get(block, key, default=None):
    for k, v in block:
        if k.lower() == key and isinstance(v, str):
            return v
    return default

PLANE_RE = re.compile(r"\(\s*([-\d.eE+]+)\s+([-\d.eE+]+)\s+([-\d.eE+]+)\s*\)")

def vmf_plane(s):
    pts = [tuple(float(c) for c in m) for m in PLANE_RE.findall(s)]
    if len(pts) != 3:
        return None
    p1, p2, p3 = pts
    n = unit(cross(sub(p1, p2), sub(p3, p2)))
    if n == (0.0, 0.0, 0.0):
        return None
    return n, dot(n, p1)

def read_vmf(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        root = parse_keyvalues(f.read())
    brushes, entities = [], []
    def solids(block, classname):
        for k, v in block:
            if k.lower() == "solid" and isinstance(v, list):
                sides = []
                for k2, v2 in v:
                    if k2.lower() == "side" and isinstance(v2, list):
                        pl = vmf_plane(kv_get(v2, "plane", ""))
                        if kv_get(v2, "material") is not None and pl:
                            if any(k3.lower() == "dispinfo" for k3, _ in v2):
                                pass  # displacement sides are kept as a flat side
                            sides.append((pl[0], pl[1], kv_get(v2, "material", "").lower()))
                if len(sides) >= 4:
                    brushes.append(Brush(sides, classname))
    for k, v in root:
        if not isinstance(v, list):
            continue
        if k.lower() == "world":
            solids(v, "worldspawn")
        elif k.lower() == "entity":
            ent = {kk.lower(): vv for kk, vv in v if isinstance(vv, str)}
            cls = ent.get("classname", "")
            first = len(brushes)
            solids(v, cls)
            ent["_brushes"] = brushes[first:]
            entities.append(ent)
    return brushes, entities

# ----- .bsp (version 19 - 21) -----
def read_bsp(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"VBSP":
        raise SystemExit("not a Source BSP file")
    version = struct.unpack_from("<i", data, 4)[0]
    raw = [struct.unpack_from("<iiii", data, 8 + i * 16) for i in range(64)]

    # lump_t is {fileofs, filelen, version, fourCC} in most games, {version, fileofs, filelen, fourCC} in the
    # Left 4 Dead branch: pick the order whose entity lump is text
    def lumps_for(order):
        out = []
        for r in raw:
            ofs, ln = (r[0], r[1]) if order == 0 else (r[1], r[2])
            out.append((ofs, ln))
        return out
    lumps = None
    for order in (0, 1):
        cand = lumps_for(order)
        ofs, ln = cand[0]
        if 0 < ofs < len(data) and 0 < ln <= len(data) - ofs and data[ofs:ofs + 1] in (b"{", b"L"):
            lumps = cand
            break
    if not lumps:
        raise SystemExit("couldn't read the BSP's lump table")

    def lump(i):
        ofs, ln = lumps[i]
        blob = data[ofs:ofs + ln]
        if blob[:4] == b"LZMA":  # compressed lump: rebuild an .lzma header for Python's lzma
            actual, lz_size = struct.unpack_from("<II", blob, 4)
            props = blob[12:17]
            header = props + struct.pack("<Q", actual)
            blob = lzma.decompress(header + blob[17:17 + lz_size], format=lzma.FORMAT_ALONE)
        return blob

    ent_text = lump(0).rstrip(b"\0").decode("utf-8", "replace")
    entities = []
    for k, v in parse_keyvalues(ent_text):
        if isinstance(v, list):
            entities.append({kk.lower(): vv for kk, vv in v if isinstance(vv, str)})

    planes_b = lump(1)
    planes = [struct.unpack_from("<4f", planes_b, i * 20) for i in range(len(planes_b) // 20)]
    texdata_b = lump(2)
    texdata = [struct.unpack_from("<3fi", texdata_b, i * 32)[3] for i in range(len(texdata_b) // 32)]
    texinfo_b = lump(6)
    texinfo = [struct.unpack_from("<i", texinfo_b, i * 72 + 68)[0] for i in range(len(texinfo_b) // 72)]
    models_b = lump(14)
    models = [struct.unpack_from("<9f", models_b, i * 48) for i in range(len(models_b) // 48)]
    brushes_b = lump(18)
    brush_rows = [struct.unpack_from("<iii", brushes_b, i * 12) for i in range(len(brushes_b) // 12)]
    sides_b = lump(19)
    side_rows = [struct.unpack_from("<Hhh", sides_b, i * 8) for i in range(len(sides_b) // 8)]
    str_data = lump(43)
    str_table_b = lump(44)
    str_table = [struct.unpack_from("<i", str_table_b, i * 4)[0] for i in range(len(str_table_b) // 4)]

    def tex_name(ti):
        if ti < 0 or ti >= len(texinfo):
            return "tools/toolsnodraw"
        td = texinfo[ti]
        if td < 0 or td >= len(texdata):
            return "tools/toolsnodraw"
        si = texdata[td]
        if si < 0 or si >= len(str_table):
            return ""
        start = str_table[si]
        end = str_data.find(b"\0", start)
        return str_data[start:end].decode("utf-8", "replace").lower()

    SOLID_MASK = 0x1 | 0x2 | 0x8 | 0x10000
    brushes = []
    for first, num, contents in brush_rows:
        if not (contents & SOLID_MASK):
            continue
        sides = []
        for j in range(first, first + num):
            if j >= len(side_rows):
                break
            pn, ti, _disp = side_rows[j]
            if pn >= len(planes):
                continue
            nx, ny, nz, d = planes[pn]
            sides.append(((nx, ny, nz), d, tex_name(ti)))
        if len(sides) >= 4:
            b = Brush(sides, "worldspawn", contents)
            if contents & 0x10000 and not contents & 0x1:
                b.entity = "_playerclip"
            brushes.append(b)

    # brush entities (fizzlers, catapults...): their bounds come from the models lump ("model" "*N")
    for ent in entities:
        m = ent.get("model", "")
        if m.startswith("*"):
            try:
                mins = models[int(m[1:])][0:3]
                maxs = models[int(m[1:])][3:6]
                origin = [float(c) for c in ent.get("origin", "0 0 0").split()]
                ent["_bounds"] = (add(mins, tuple(origin)), add(maxs, tuple(origin)))
            except (ValueError, IndexError):
                pass
    print(f"  BSP version {version}: {len(brushes)} solid brushes, {len(entities)} entities")
    return brushes, entities

# ---------------------------------------------------------------------------------------------------------------
# geometry
# ---------------------------------------------------------------------------------------------------------------
def solve3(p1, p2, p3):
    n1, d1 = p1
    n2, d2 = p2
    n3, d3 = p3
    c23, c31, c12 = cross(n2, n3), cross(n3, n1), cross(n1, n2)
    det = dot(n1, c23)
    if abs(det) < 1e-9:
        return None
    return mul(add(add(mul(c23, d1), mul(c31, d2)), mul(c12, d3)), 1.0 / det)

def brush_faces(brush):
    """-> [(normal, texture, [vertices in order])] for every side that has an area"""
    planes = [(n, d) for n, d, _ in brush.sides]
    verts = []
    m = len(planes)
    for i in range(m):
        for j in range(i + 1, m):
            for k in range(j + 1, m):
                p = solve3(planes[i], planes[j], planes[k])
                if p is None:
                    continue
                if all(dot(n, p) <= d + 0.01 for n, d in planes):
                    if not any(length(sub(p, q)) < 0.01 for q in verts):
                        verts.append(p)
    faces = []
    for n, d, tex in brush.sides:
        on = [v for v in verts if abs(dot(n, v) - d) < 0.02]
        if len(on) < 3:
            continue
        c = mul(on[0], 0)
        for v in on:
            c = add(c, v)
        c = mul(c, 1.0 / len(on))
        a = unit(sub(on[0], c))
        b = cross(n, a)
        on.sort(key=lambda v: math.atan2(dot(sub(v, c), b), dot(sub(v, c), a)))
        # area (and drop duplicate / degenerate sides)
        area = 0.0
        for i in range(1, len(on) - 1):
            area += length(cross(sub(on[i], on[0]), sub(on[i + 1], on[0]))) / 2
        if area > 1e-3 and not any(dot(n, f[0]) > 0.9999 for f in faces):
            faces.append((n, tex, on, area))
    return faces

# Source (x, y, z) with z up -> Roblox (x, z, -y) with y up, scaled
class Xform:
    def __init__(self, scale):
        self.s = scale
        self.offset = (0.0, 0.0, 0.0)
    def p(self, v):
        return add((v[0] * self.s, v[2] * self.s, -v[1] * self.s), self.offset)
    def d(self, v):
        return (v[0], v[2], -v[1])

# ---------------------------------------------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------------------------------------------
class Materials:
    def __init__(self, path):
        with open(path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        self.rules = [(re.compile(r["match"]), r) for r in cfg["rules"]]
        self.entities = {k: v for k, v in cfg.get("entities", {}).items() if not k.startswith("_")}
        self.cache = {}
        self.unmatched = {}
    def get(self, tex):
        if tex in self.cache:
            r = self.cache[tex]
            if r.get("_fallback"):
                self.unmatched[tex] = self.unmatched.get(tex, 0) + 1
            return r
        for rx, r in self.rules:
            if rx.search(tex):
                if rx.pattern == ".*":
                    r["_fallback"] = True
                    self.unmatched[tex] = self.unmatched.get(tex, 0) + 1
                self.cache[tex] = r
                return r
        self.cache[tex] = {"variant": "", "base": "SmoothPlastic", "portalable": False}
        return self.cache[tex]

MATERIAL_TOKENS = {"Plastic": 256, "SmoothPlastic": 272, "Neon": 288, "Wood": 512, "WoodPlanks": 528, "Marble": 784,
                   "Slate": 800, "Concrete": 816, "Granite": 832, "Brick": 848, "Pebble": 864, "Cobblestone": 880,
                   "CorrodedMetal": 1040, "DiamondPlate": 1056, "Foil": 1072, "Metal": 1088, "Grass": 1280,
                   "Sand": 1296, "Fabric": 1312, "Ice": 1536, "Glass": 1568, "ForceField": 1584}

# ---------------------------------------------------------------------------------------------------------------
# rbxmx writer
# ---------------------------------------------------------------------------------------------------------------
class Writer:
    def __init__(self):
        self.out = io.StringIO()
        self.ref = 0
    def _r(self):
        self.ref += 1
        return "RBX%d" % self.ref
    def open(self, cls, name, props=""):
        self.out.write('<Item class="%s" referent="%s"><Properties><string name="Name">%s</string>%s</Properties>\n'
                       % (cls, self._r(), escape(name), props))
    def close(self):
        self.out.write("</Item>\n")

def cf_xml(pos, right, up, back):
    return ('<CoordinateFrame name="CFrame"><X>%.4f</X><Y>%.4f</Y><Z>%.4f</Z>'
            '<R00>%.6f</R00><R01>%.6f</R01><R02>%.6f</R02><R10>%.6f</R10><R11>%.6f</R11><R12>%.6f</R12>'
            '<R20>%.6f</R20><R21>%.6f</R21><R22>%.6f</R22></CoordinateFrame>'
            % (pos[0], pos[1], pos[2], right[0], up[0], back[0], right[1], up[1], back[1], right[2], up[2], back[2]))

def tags_xml(tags):
    if not tags:
        return ""
    return '<BinaryString name="Tags">%s</BinaryString>' % base64.b64encode("\0".join(tags).encode()).decode()

def color_xml(rgb):
    r, g, b = (max(0, min(255, int(c))) for c in rgb)
    return '<Color3uint8 name="Color3uint8">%d</Color3uint8>' % (0xFF000000 | (r << 16) | (g << 8) | b)

def part_xml(w, cls, name, pos, axes, size, mat, tags=(), collide=True, transparency=0.0):
    right, up, back = axes
    props = (cf_xml(pos, right, up, back)
             + '<bool name="Anchored">true</bool>'
             + '<Vector3 name="size"><X>%.4f</X><Y>%.4f</Y><Z>%.4f</Z></Vector3>' % size
             + '<token name="Material">%d</token>' % MATERIAL_TOKENS.get(mat.get("base", "SmoothPlastic"), 272)
             + ('<string name="MaterialVariantSerialized">%s</string>' % escape(mat.get("variant", "")) if mat.get("variant") else "")
             + color_xml(mat.get("color", [255, 255, 255]))
             + '<float name="Transparency">%.3f</float>' % max(transparency, float(mat.get("transparency", 0)))
             + '<bool name="CanCollide">%s</bool>' % ("true" if collide and mat.get("collide", True) else "false")
             + '<bool name="CastShadow">true</bool>'
             + tags_xml(list(tags)))
    w.open(cls, name, props)
    w.close()

# ---------------------------------------------------------------------------------------------------------------
# brushes -> parts
# ---------------------------------------------------------------------------------------------------------------
SKIP_BRUSH_ENTITIES = re.compile(r"^(trigger_|func_areaportal|func_occluder|func_viscluster|func_vehicleclip|"
                                 r"env_|info_|point_|logic_|func_portal_|func_instance|func_noportal_volume|"
                                 r"func_placement_clip|func_portal_bumper|func_portal_detector)")
INVISIBLE_ENTITIES = {"func_clip_vphysics", "_playerclip"}
NONSOLID_ENTITIES = {"func_illusionary"}

def mat_tags(mat, tex):
    tags = ["P2Tex:" + tex[:80]]
    if not mat.get("portalable", False):
        tags.append("P2NoPortal")
    return tags

def thin_triangle(w, a, b, c, n, mat, tex, thickness, collide):
    """a triangle as two wedges (the usual Roblox trick), its outer side flush with the face"""
    ab, ac, bc = sub(b, a), sub(c, a), sub(c, b)
    abd, acd, bcd = dot(ab, ab), dot(ac, ac), dot(bc, bc)
    if abd > acd and abd > bcd:
        c, a = a, c
    elif acd > bcd and acd > abd:
        a, b = b, a
    ab, ac, bc = sub(b, a), sub(c, a), sub(c, b)
    right = unit(cross(ac, ab))
    if right == (0.0, 0.0, 0.0):
        return 0
    up = unit(cross(bc, right))
    back = unit(bc)
    height = abs(dot(ab, up))
    inward = mul(n, -thickness / 2)
    n_made = 0
    for (p, q, r_, bk, d) in ((a, b, right, back, abs(dot(ab, back))), (a, c, mul(right, -1), mul(back, -1), abs(dot(ac, back)))):
        if d < 1e-3 or height < 1e-3:
            continue
        pos = add(mul(add(p, q), 0.5), inward)
        part_xml(w, "WedgePart", "Face", pos, (r_, up, bk), (thickness, height, d), mat, mat_tags(mat, tex), collide)
        n_made += 1
    return n_made

def convert_brush(w, brush, xf, mats, opts, stats):
    faces = brush_faces(brush)
    if len(faces) < 4:
        stats["degenerate"] += 1
        return
    rfaces = []  # in Roblox space
    for n, tex, vs, area in faces:
        rfaces.append((unit(xf.d(n)), tex, [xf.p(v) for v in vs], area * xf.s * xf.s, mats.get(tex)))
    visible = [f for f in rfaces if f[4].get("special") not in ("skipface", "skip", "invisible")]
    specials = {f[4].get("special") for f in rfaces}
    if not visible:
        if "skip" in specials and "invisible" not in specials:
            stats["skipped"] += 1
            return
        # all nodraw / clip: an invisible wall (it's solid in Portal 2 too)
        dominant = {"base": "SmoothPlastic", "portalable": False}
        invisible = True
    else:
        dominant = max(visible, key=lambda f: f[3])[4]
        invisible = brush.entity in INVISIBLE_ENTITIES
    dom_tex = max(visible, key=lambda f: f[3])[1] if visible else "tools/toolsnodraw"
    collide = brush.entity not in NONSOLID_ENTITIES
    tr = 1.0 if invisible else 0.0
    verts = [v for f in rfaces for v in f[2]]

    normals = [f[0] for f in rfaces]
    # ----- a box (also rotated): 6 sides in 3 opposite pairs at right angles -----
    if len(rfaces) == 6:
        axes = []
        for nn in normals:
            if not any(abs(dot(nn, a)) > 0.999 for a in axes):
                axes.append(nn)
        if len(axes) == 3 and all(abs(dot(axes[i], axes[j])) < 1e-3 for i in range(3) for j in range(i + 1, 3)) \
                and all(any(dot(nn, a) < -0.999 for nn in normals) for a in axes):
            # right = most X-ish, up = most Y-ish
            up = max(axes, key=lambda a: abs(a[1]))
            if up[1] < 0: up = mul(up, -1)
            rest = [a for a in axes if a is not up]
            right = max(rest, key=lambda a: abs(a[0]))
            if right[0] < 0: right = mul(right, -1)
            back = cross(right, up)
            size, center = [], (0.0, 0.0, 0.0)
            for ax in (right, up, back):
                ps = [dot(v, ax) for v in verts]
                lo, hi = min(ps), max(ps)
                size.append(hi - lo)
                center = add(center, mul(ax, (lo + hi) / 2))
            part_xml(w, "Part", "Brush", center, (right, up, back), tuple(size), dominant,
                     mat_tags(dominant, dom_tex), collide, tr)
            stats["boxes"] += 1
            # sides with a different texture than the main one: a thin plate on top
            if opts.face_plates and not invisible:
                for n, tex, vs, area, m in visible:
                    if m is dominant or m.get("variant") == dominant.get("variant") and m.get("base") == dominant.get("base"):
                        continue
                    others = [a for a in (right, up, back) if abs(dot(a, n)) < 0.5]
                    c = mul(add(vs[0], vs[0]), 0)
                    for v in vs: c = add(c, v)
                    c = mul(c, 1.0 / len(vs))
                    ex = []
                    for a in others:
                        ps = [dot(v, a) for v in vs]
                        ex.append(max(ps) - min(ps))
                    pr = others[0]
                    pu = others[1]
                    pb = cross(pr, pu)
                    sz = [0.0, 0.0, 0.0]
                    sz[0], sz[1] = ex[0], ex[1]
                    sz[2] = 0.05
                    pos = add(c, mul(n, 0.035))
                    part_xml(w, "Part", "Side", pos, (pr, pu, pb), tuple(sz), m, mat_tags(m, tex), False, 0)
                    stats["plates"] += 1
            return

    # ----- a ramp: a right-angled triangle prism -> WedgePart -----
    if len(rfaces) == 5:
        tris = [f for f in rfaces if len(f[2]) == 3]
        quads = [f for f in rfaces if len(f[2]) == 4]
        if len(tris) == 2 and len(quads) == 3 and dot(tris[0][0], tris[1][0]) < -0.999:
            t0 = tris[0][2]
            for i in range(3):
                P, A, B = t0[i], t0[(i + 1) % 3], t0[(i + 2) % 3]
                if abs(dot(unit(sub(A, P)), unit(sub(B, P)))) < 1e-3:
                    L = abs(dot(sub(tris[1][2][0], P), tris[0][0]))
                    prism = mul(tris[0][0], -1)  # from triangle 0 to triangle 1
                    yv, zv = unit(sub(B, P)), mul(unit(sub(A, P)), -1)
                    xv = cross(yv, zv)
                    center = add(add(add(P, mul(sub(A, P), 0.5)), mul(sub(B, P), 0.5)), mul(prism, L / 2))
                    part_xml(w, "WedgePart", "Ramp", center, (xv, yv, zv), (L, length(sub(B, P)), length(sub(A, P))),
                             dominant, mat_tags(dominant, dom_tex), collide, tr)
                    stats["wedges"] += 1
                    return

    # ----- anything else: every drawn side as triangles (two thin wedges each) -----
    for n, tex, vs, area, m in (visible if not invisible else rfaces):
        mm = m if not invisible else {"base": "SmoothPlastic", "portalable": False}
        for i in range(1, len(vs) - 1):
            stats["triangles"] += thin_triangle(w, vs[0], vs[i], vs[i + 1], n, mm, tex, opts.thickness, collide)
    stats["shapes"] += 1

# ---------------------------------------------------------------------------------------------------------------
# entities
# ---------------------------------------------------------------------------------------------------------------
def angles_axes(ent, xf):
    """Source angles "pitch yaw roll" -> Roblox (right, up, back), the model's forward (+X) as LookVector"""
    try:
        p, y, r = (math.radians(float(c)) for c in ent.get("angles", "0 0 0").split())
    except ValueError:
        p = y = r = 0.0
    cp, sp, cy, sy, cr, sr = math.cos(p), math.sin(p), math.cos(y), math.sin(y), math.cos(r), math.sin(r)
    fwd = (cp * cy, cp * sy, -sp)
    upv = (cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp)
    look, up = unit(xf.d(fwd)), unit(xf.d(upv))
    right = cross(look, up)
    return right, up, mul(look, -1)

def origin_of(ent, xf):
    try:
        return xf.p(tuple(float(c) for c in ent.get("origin", "0 0 0").split()))
    except ValueError:
        return xf.p((0.0, 0.0, 0.0))

def entity_bounds(ent, xf):
    b = ent.get("_bounds")
    if b:
        lo, hi = xf.p(b[0]), xf.p(b[1])
    elif ent.get("_brushes"):
        pts = [xf.p(v) for br in ent["_brushes"] for f in brush_faces(br) for v in f[2]]
        if not pts:
            return None
        lo = tuple(min(p[i] for p in pts) for i in range(3))
        hi = tuple(max(p[i] for p in pts) for i in range(3))
    else:
        return None
    lo, hi = tuple(min(lo[i], hi[i]) for i in range(3)), tuple(max(lo[i], hi[i]) for i in range(3))
    return mul(add(lo, hi), 0.5), sub(hi, lo)

CUBE_TYPES = {"0": "Normal", "1": "Companion", "2": "Reflection", "3": "Sphere", "4": "Antique"}
IDENT = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))

def convert_entities(w, entities, xf, mats, opts, stats):
    for ent in entities:
        cls = ent.get("classname", "")
        rule = mats.entities.get(cls)
        name = ent.get("targetname", "")
        if rule and rule.get("skip"):
            continue
        if rule and "spawn" in rule:
            spawn = rule["spawn"]
            if spawn == "coop":
                team = ent.get("startingteam", ent.get("team", "0"))
                spawn = {"3": "PlayerSpawnBlue", "2": "PlayerSpawnOrange"}.get(team, "PlayerSpawn")
            pos = add(origin_of(ent, xf), (0, 0.5, 0))
            right, up, back = angles_axes(ent, xf)
            # spawns stand upright: keep only the yaw
            look = unit((-back[0], 0.0, -back[2])) if abs(back[1]) < 0.99 else (0.0, 0.0, -1.0)
            flat = (cross(look, (0, 1, 0)), (0.0, 1.0, 0.0), mul(look, -1))
            part_xml(w, "Part", spawn, pos, flat, (4.0, 1.0, 4.0), {"base": "SmoothPlastic"}, ["P2Spawn"], False, 1.0)
            stats["spawns"] += 1
        elif rule and ("asset" in rule or "zone" in rule):
            tags = ["P2Placeholder"] if "asset" in rule else [rule["zone"]]
            if "asset" in rule:
                tags.append("P2Asset:" + rule["asset"])
            for k, v in rule.get("attr", {}).items():
                tags.append("P2Attr:%s=%s" % (k, v))
            if rule.get("cube"):
                tags.append("P2Attr:CubeType=" + CUBE_TYPES.get(ent.get("cubetype", "0"), "Normal"))
            if name:
                tags.append("P2Name:" + name[:60])
            if rule.get("brush"):
                bb = entity_bounds(ent, xf)
                if not bb:
                    continue
                pos, size = bb
                axes = IDENT
                size = tuple(max(s, 0.2) for s in size)
            else:
                pos = origin_of(ent, xf)
                axes = angles_axes(ent, xf)
                size = tuple(rule.get("size", [2, 2, 2]))
            label = rule.get("asset") or rule.get("zone")
            part_xml(w, "Part", label, pos, axes, size, {"base": "SmoothPlastic", "color": [255, 170, 40]}, tags, False, 0.6)
            stats["placeholders"] += 1
        elif cls in ("light", "light_spot") and opts.lights:
            try:
                parts = [float(c) for c in ent.get("_light", "255 255 255 200").split()]
            except ValueError:
                parts = [255, 255, 255, 200]
            while len(parts) < 4:
                parts.append(200)
            pos = origin_of(ent, xf)
            w.open("Part", "Light", cf_xml(pos, *IDENT) + '<bool name="Anchored">true</bool>'
                   + '<Vector3 name="size"><X>1</X><Y>1</Y><Z>1</Z></Vector3>'
                   + '<float name="Transparency">1</float><bool name="CanCollide">false</bool><bool name="CanQuery">false</bool>'
                   + '<bool name="CastShadow">false</bool>')
            dist = float(ent.get("_fifty_percent_distance", "0") or 0) * xf.s * 2
            w.open("PointLight", "Glow", '<Color3 name="Color"><R>%.3f</R><G>%.3f</G><B>%.3f</B></Color3>'
                   % (parts[0] / 255, parts[1] / 255, parts[2] / 255)
                   + '<float name="Brightness">%.2f</float>' % max(0.3, min(3.0, parts[3] / 250))
                   + '<float name="Range">%.1f</float>' % max(8.0, min(60.0, dist if dist > 0 else 24.0))
                   + '<bool name="Shadows">false</bool>')
            w.close()
            w.close()
            stats["lights"] += 1
        elif cls.startswith("prop_") or cls.startswith("npc_"):
            stats["props_skipped"][cls] = stats["props_skipped"].get(cls, 0) + 1

SETUP_SCRIPT = r'''-- P2MapSetup (made by p2_to_roblox.py)
-- Runs when this map is in Workspace (a server Script). You can also paste it into the command bar with the map
-- selected (change `map` to that model) to see the result in edit mode.
--   * every part with a MaterialVariant gets that variant's BaseMaterial (a variant only shows on its own material)
--   * tag P2NoPortal -> attribute NoPortal = true (your portal gun refuses those surfaces)
--   * placeholders (tag P2Placeholder + "P2Asset:<name>") -> a clone of that model from ReplicatedStorage.PortalAssets
local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local map = script.Parent

local BLOCKED = { [Enum.Material.Metal] = true, [Enum.Material.DiamondPlate] = true, [Enum.Material.Foil] = true,
	[Enum.Material.CorrodedMetal] = true, [Enum.Material.Plastic] = true, [Enum.Material.Glass] = true }
local bases, warned = {}, {}
for _, p in ipairs(map:GetDescendants()) do
	if p:IsA("BasePart") then
		local mv = p.MaterialVariant
		if mv ~= "" then
			if bases[mv] == nil then
				local v = MaterialService:FindFirstChild(mv, true)
				bases[mv] = (v and v:IsA("MaterialVariant")) and v.BaseMaterial or false
				if not bases[mv] then warn("[P2MapSetup] no MaterialVariant called '" .. mv .. "' in MaterialService") end
			end
			if bases[mv] then
				local portalable = not p:HasTag("P2NoPortal")
				if portalable and BLOCKED[bases[mv]] and not warned[mv] then
					warned[mv] = true
					warn("[P2MapSetup] '" .. mv .. "' is a portal surface but its BaseMaterial is " .. bases[mv].Name
						.. " (the portal gun blocks that). Set its BaseMaterial to SmoothPlastic or Concrete.")
				end
				p.Material = bases[mv]
			end
		end
		if p:HasTag("P2NoPortal") then p:SetAttribute("NoPortal", true) end
	end
end

local assets = ReplicatedStorage:FindFirstChild("PortalAssets")
local function findAsset(name)
	if not assets then return nil end
	for _, folder in ipairs({ "TestElements", "TestingAssets", "EditorAssets", "Cubes" }) do
		local f = assets:FindFirstChild(folder)
		local a = f and f:FindFirstChild(name)
		if a then return a end
	end
	return assets:FindFirstChild(name, true)
end
for _, p in ipairs(map:GetDescendants()) do
	if p:IsA("BasePart") and p:HasTag("P2Placeholder") then
		local assetName, attrs = nil, {}
		for _, t in ipairs(p:GetTags()) do
			local a = t:match("^P2Asset:(.+)$")
			if a then assetName = a end
			local k, v = t:match("^P2Attr:([^=]+)=(.*)$")
			if k then attrs[k] = v end
		end
		if assetName == "Cube" and attrs.CubeType then assetName = findAsset(attrs.CubeType) and attrs.CubeType or assetName end
		local template = assetName and findAsset(assetName)
		if template then
			local c = template:Clone()
			if c:IsA("Model") then c:PivotTo(p.CFrame) elseif c:IsA("BasePart") then c.CFrame = p.CFrame end
			for k, v in pairs(attrs) do c:SetAttribute(k, v) end
			c.Parent = p.Parent
			p:Destroy()
		else
			warn("[P2MapSetup] no model '" .. tostring(assetName) .. "' in ReplicatedStorage.PortalAssets - left a placeholder")
		end
	end
end
'''

# ---------------------------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Portal 2 map (.vmf / .bsp) -> Roblox model (.rbxmx)")
    ap.add_argument("input", help="the .vmf (best) or .bsp")
    ap.add_argument("-o", "--output", help="the .rbxmx to write (default: next to the input)")
    ap.add_argument("--name", help="the model's name (CoopHub for the co-op hub)")
    ap.add_argument("--scale", type=float, default=1 / 14.7, help="studs per Hammer unit (default 1/14.7)")
    ap.add_argument("--materials", default=os.path.join(HERE, "p2_materials.json"), help="texture -> MaterialVariant rules")
    ap.add_argument("--thickness", type=float, default=0.2, help="studs: thickness of odd shapes' faces")
    ap.add_argument("--no-face-plates", dest="face_plates", action="store_false", help="one material per box, no side plates")
    ap.add_argument("--no-lights", dest="lights", action="store_false", help="leave the lights out")
    ap.add_argument("--no-center", dest="center", action="store_false", help="keep Hammer's coordinates (else the map is centred, floor at Y = 0)")
    opts = ap.parse_args()

    ext = os.path.splitext(opts.input)[1].lower()
    print("Reading", opts.input)
    if ext == ".vmf":
        brushes, entities = read_vmf(opts.input)
    elif ext == ".bsp":
        brushes, entities = read_bsp(opts.input)
    else:
        raise SystemExit("give it a .vmf or a .bsp")

    # brush entities that aren't geometry (triggers, areaportals...) don't get built
    keep = []
    for b in brushes:
        if b.entity == "worldspawn" or b.entity in INVISIBLE_ENTITIES or not SKIP_BRUSH_ENTITIES.match(b.entity):
            keep.append(b)
    mats = Materials(opts.materials)
    xf = Xform(opts.scale)

    if opts.center and keep:
        pts = [xf.p(v) for b in keep[:4000] for f in brush_faces(b) for v in f[2]]
        if pts:
            lo = tuple(min(p[i] for p in pts) for i in range(3))
            hi = tuple(max(p[i] for p in pts) for i in range(3))
            xf.offset = (-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2)

    name = opts.name or os.path.splitext(os.path.basename(opts.input))[0]
    out_path = opts.output or os.path.splitext(opts.input)[0] + ".rbxmx"
    stats = {"boxes": 0, "wedges": 0, "shapes": 0, "triangles": 0, "plates": 0, "skipped": 0, "degenerate": 0,
             "spawns": 0, "placeholders": 0, "lights": 0, "props_skipped": {}}

    w = Writer()
    w.out.write('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n')
    w.open("Model", name)
    w.open("Folder", "Geometry")
    for i, b in enumerate(keep):
        convert_brush(w, b, xf, mats, opts, stats)
        if i and i % 2000 == 0:
            print("  %d / %d brushes" % (i, len(keep)))
    w.close()
    w.open("Folder", "Entities")
    convert_entities(w, entities, xf, mats, opts, stats)
    w.close()
    w.open("Script", "P2MapSetup", '<ProtectedString name="Source"><![CDATA[%s]]></ProtectedString>' % SETUP_SCRIPT)
    w.close()
    w.close()
    w.out.write("</roblox>\n")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(w.out.getvalue())

    print("Wrote", out_path)
    print("  %d boxes, %d ramps, %d other shapes (%d triangle wedges), %d side plates" %
          (stats["boxes"], stats["wedges"], stats["shapes"], stats["triangles"], stats["plates"]))
    print("  %d spawns, %d test element placeholders, %d lights; %d tool / trigger brushes skipped, %d broken brushes" %
          (stats["spawns"], stats["placeholders"], stats["lights"], stats["skipped"], stats["degenerate"]))
    if stats["props_skipped"]:
        print("  models not converted (no .mdl support - add them by hand):",
              ", ".join("%s x%d" % kv for kv in sorted(stats["props_skipped"].items(), key=lambda kv: -kv[1])[:12]))
    if mats.unmatched:
        print("  textures with no rule in %s (grey for now - add rules for them):" % os.path.basename(opts.materials))
        for tex, n in sorted(mats.unmatched.items(), key=lambda kv: -kv[1])[:25]:
            print("    %-50s %d brush sides" % (tex, n))

if __name__ == "__main__":
    main()
