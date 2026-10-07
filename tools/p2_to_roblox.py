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
    try:
        pts = [tuple(float(c) for c in m) for m in PLANE_RE.findall(s)]
    except ValueError:
        return None
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
            ent["_kv"] = [(kk, vv) for kk, vv in v if isinstance(vv, str)]
            for kk, vv in v:
                if kk.lower() == "connections" and isinstance(vv, list):
                    ent["_kv"] += [(ck, cv) for ck, cv in vv if isinstance(cv, str)]
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

    def unlzma(blob):
        if blob[:4] == b"LZMA":  # compressed lump: rebuild an .lzma header for Python's lzma
            actual, lz_size = struct.unpack_from("<II", blob, 4)
            props = blob[12:17]
            header = props + struct.pack("<Q", actual)
            blob = lzma.decompress(header + blob[17:17 + lz_size], format=lzma.FORMAT_ALONE)
        return blob

    def lump(i):
        ofs, ln = lumps[i]
        return unlzma(data[ofs:ofs + ln])

    ent_text = lump(0).rstrip(b"\0").decode("utf-8", "replace")
    entities = []
    for k, v in parse_keyvalues(ent_text):
        if isinstance(v, list):
            ent = {kk.lower(): vv for kk, vv in v if isinstance(vv, str)}
            ent["_kv"] = [(kk, vv) for kk, vv in v if isinstance(vv, str)]
            entities.append(ent)

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
    # static props (game lump "sprp"): they aren't entities in a compiled map
    statics = 0
    try:
        gl = lump(35)
        for gi in range(struct.unpack_from("<i", gl, 0)[0]):
            gid, gflags, gver, gofs, glen = struct.unpack_from("<4sHHii", gl, 4 + gi * 16)
            if gid != b"prps":
                continue
            sp = unlzma(data[gofs:gofs + glen]) if gflags & 1 else data[gofs:gofs + glen]
            pos = 0
            ndict = struct.unpack_from("<i", sp, pos)[0]
            pos += 4
            names = [sp[pos + i * 128:pos + (i + 1) * 128].split(b"\0")[0].decode("latin-1") for i in range(ndict)]
            pos += ndict * 128
            nleaf = struct.unpack_from("<i", sp, pos)[0]
            pos += 4 + nleaf * (4 if gver >= 12 else 2)
            nprops = struct.unpack_from("<i", sp, pos)[0]
            pos += 4
            if nprops <= 0:
                break
            size = (len(sp) - pos) // nprops
            for i in range(nprops):
                b = pos + i * size
                o = struct.unpack_from("<3f", sp, b)
                a = struct.unpack_from("<3f", sp, b + 12)
                mi = struct.unpack_from("<H", sp, b + 24)[0]
                skin = struct.unpack_from("<i", sp, b + 32)[0]
                scale = struct.unpack_from("<f", sp, b + size - 4)[0] if gver >= 11 and size in (80, 88) else 1.0
                if mi >= len(names):
                    continue
                entities.append({"classname": "prop_static", "model": names[mi], "_kv": [],
                                 "origin": "%g %g %g" % o, "angles": "%g %g %g" % a, "skin": str(skin),
                                 "modelscale": "%g" % (scale if 0.01 < scale < 100 else 1.0)})
                statics += 1
    except (struct.error, ValueError, IndexError, lzma.LZMAError) as err:
        print("  (static props couldn't be read: %s)" % err)
    try:
        read_bsp.pak = lump(40)
    except (struct.error, ValueError, IndexError, lzma.LZMAError):
        read_bsp.pak = None
    print(f"  BSP version {version}: {len(brushes)} solid brushes, {len(entities) - statics} entities, {statics} static props")
    return brushes, entities
read_bsp.pak = None

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
    # the map's cubemap copies of a material: maps/<map>/<material>_x_y_z -> <material>
    CUBEMAP_COPY = re.compile(r"^maps/[^/]+/(.+?)(?:_-?\d+){3}$")

    def get(self, tex):
        m = self.CUBEMAP_COPY.match(tex)
        if m:
            tex = m.group(1)
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
    def mark(self):
        return self.out.tell()
    def rollback(self, pos):
        self.out.seek(pos)
        self.out.truncate()

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

# ----- Portal 2's connections ("outputs"): OnPressed -> door, Open, , 0, -1 -----
def outputs_of(ent):
    outs = []
    for k, v in ent.get("_kv", []):
        if not k.lower().startswith("on") and not k.lower().startswith("out"):
            continue
        parts = v.split("\x1b") if "\x1b" in v else v.split(",")
        if len(parts) < 2:
            continue
        while len(parts) < 5:
            parts.append("")
        try:
            delay = float(parts[3] or 0)
        except ValueError:
            delay = 0.0
        try:
            times = int(float(parts[4] or -1))
        except ValueError:
            times = -1
        outs.append([k, parts[0], parts[1], parts[2], delay, times])
    return outs

# the keys the map's I/O script needs
IO_KEYS = ("startdisabled", "startenabled", "startstate", "linearforce", "max", "min", "startvalue", "refiretime",
           "initialvalue", "launchtarget", "playerspeed", "physicsspeed", "entitytemplate", "spawnflags", "cubetype",
           "lowerrandombound", "upperrandombound", "usetrandomtime") + tuple("template%02d" % i for i in range(1, 17))
# brush triggers that become invisible boxes the I/O script watches
TRIGGER_CLASSES = {"trigger_once", "trigger_multiple", "trigger_playerteam", "trigger_coop_manager", "trigger_look"}
# classes the I/O script runs
LOGIC_CLASSES = {"logic_auto", "logic_relay", "logic_branch", "logic_coop_manager", "math_counter", "logic_timer",
                 "env_entity_maker", "point_template", "logic_compare", "logic_case"}
EXIT_RE = re.compile(r"changelevel|transition|@exit|end_level|exit_teleport|levelend|elevator_end", re.I)

def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ") + '"'
    if isinstance(v, dict):
        return "{" + ", ".join("[%s] = %s" % (lua_value(k), lua_value(x)) for k, x in v.items()) + "}"
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua_value(x) for x in v) + "}"
    return "nil"
IDENT = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))

def convert_entities(w, entities, xf, mats, opts, stats):
    io_records = {}
    # cubes a point_template spawns later aren't in the map at the start (unless flag 2 keeps them)
    templated = set()
    names = {}
    for ent in entities:
        if ent.get("targetname"):
            names.setdefault(ent["targetname"].lower(), []).append(ent)
    launch_targets = {ent.get("launchtarget", "").lower() for ent in entities if ent.get("launchtarget")}
    for ent in entities:
        if ent.get("classname") == "point_template" and not (int(ent.get("spawnflags", "0") or 0) & 2):
            for i in range(1, 17):
                t = ent.get("template%02d" % i)
                if t:
                    templated.add(t.lower())
    for idx, ent in enumerate(entities):
        mark = w.mark()
        try:
            _convert_entity(w, idx, ent, entities, xf, mats, opts, stats, io_records, templated, names, launch_targets)
        except Exception as err:
            w.rollback(mark)
            stats["errors"].append("entity %s (%s): %s" % (ent.get("classname", "?"), ent.get("targetname", ""), err))
    return io_records

def _convert_entity(w, idx, ent, entities, xf, mats, opts, stats, io_records, templated, names, launch_targets):
    if True:
        cls = ent.get("classname", "")
        rule = mats.entities.get(cls)
        name = ent.get("targetname", "")
        eid = "e%d" % idx
        outs = outputs_of(ent)
        # everything with a name or connections goes into the map's I/O table
        if name or outs or cls in LOGIC_CLASSES:
            rec = {"c": cls, "n": name.lower(), "o": outs, "kv": {k: ent[k] for k in IO_KEYS if k in ent}}
            if cls in ("prop_weighted_cube", "prop_monster_box"):
                rec["cube"] = CUBE_TYPES.get(ent.get("cubetype", "0"), "Normal")
            io_records[eid] = rec
        if rule and rule.get("skip"):
            return
        if name.lower() in templated and cls in ("prop_weighted_cube", "prop_monster_box"):
            return  # (spawned by its env_entity_maker / point_template when the map asks for it)
        if cls in TRIGGER_CLASSES:
            bb = entity_bounds(ent, xf)
            if bb:
                tags = ["P2Trigger", "P2Ent:" + eid]
                if any(EXIT_RE.search(" ".join(str(x) for x in o)) for o in outs) or EXIT_RE.search(name):
                    tags.append("PortalChamberExit")  # the end of the map: PortalServer finishes the chamber
                part_xml(w, "Part", cls, bb[0], IDENT, tuple(max(c, 0.5) for c in bb[1]), {"base": "SmoothPlastic"}, tags, False, 1.0)
                stats["triggers"] += 1
            return
        if cls == "env_entity_maker" or (cls == "info_target" and name.lower() in launch_targets):
            part_xml(w, "Part", cls, origin_of(ent, xf), angles_axes(ent, xf), (1.0, 1.0, 1.0), {"base": "SmoothPlastic"},
                     ["P2Point", "P2Ent:" + eid], False, 1.0)
            return
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
            tags.append("P2Ent:" + eid)
            if rule.get("brush"):
                bb = entity_bounds(ent, xf)
                if not bb:
                    return
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
        elif ent.get("model", "").lower().endswith(".mdl") and opts.props:
            stats["props"].append((eid, ent))
        elif cls.startswith("prop_") or cls.startswith("npc_"):
            stats["props_skipped"][cls] = stats["props_skipped"].get(cls, 0) + 1

def model_axes(ent, xf):
    """the prop's rotation for a mesh ripped with Source +X -> Roblox +X (see p2_models.rb)"""
    right, up, back = angles_axes(ent, xf)
    return mul(back, -1), up, right

def convert_props(w, props, xf, opts, stats, models_dir):
    """every prop with a .mdl: rip the model (once per model) and leave a placeholder box the setup script swaps"""
    import p2_models
    ripper = None
    if opts.rip:
        game = opts.game or p2_models.find_game_dir(opts.input)
        pak = getattr(read_bsp, "pak", None) if opts.input.lower().endswith(".bsp") else None
        if game or pak:
            print("Ripping models from", game or "the map's pakfile")
            fs = p2_models.GameFS(game, pak)
            ripper = p2_models.Ripper(fs, models_dir, max_tex=opts.max_texture, scale=xf.s)
        else:
            print("  (no game folder: props get placeholders only - set the Portal 2 folder to rip their models)")
    infos = {}
    paths = sorted({p2_models.norm(ent["model"]) for _, ent in props})
    for n, path in enumerate(paths):
        info = None
        if ripper:
            try:
                info = ripper.rip(path)
                stats["ripped"] += 1
            except Exception as err:
                stats["rip_failed"] += 1
                stats["errors"].append("model %s: %s" % (path, err))
            if n % 10 == 9:
                print("  %d / %d models" % (n + 1, len(paths)))
        infos[path] = info
    for eid, ent in props:
        path = p2_models.norm(ent["model"])
        info = infos.get(path)
        try:
            scale = float(ent.get("modelscale", "1") or 1)
        except ValueError:
            scale = 1.0
        if not 0.01 < scale < 100:
            scale = 1.0
        axes = model_axes(ent, xf)
        origin = origin_of(ent, xf)
        tags = ["P2Model", "P2Mdl:" + p2_models.model_name(path), "P2Ent:" + eid]
        if info:
            lo, hi = info["min"], info["max"]
            c = tuple((lo[i] + hi[i]) / 2 * scale for i in range(3))
            pos = add(origin, add(add(mul(axes[0], c[0]), mul(axes[1], c[1])), mul(axes[2], c[2])))
            size = tuple(max((hi[i] - lo[i]) * scale, 0.05) for i in range(3))
        else:
            tags.append("P2NoBox")
            pos, size = origin, (1.0, 1.0, 1.0)
        if ent.get("skin", "0") not in ("0", ""):
            tags.append("P2Attr:Skin=" + ent["skin"])
        name = path.rsplit("/", 1)[-1][:-4] if path.endswith(".mdl") else path
        part_xml(w, "Part", name, pos, axes, size, {"base": "SmoothPlastic", "color": [150, 90, 220]}, tags, False, 0.7)

SETUP_SCRIPT = r'''-- P2MapSetup (made by p2_to_roblox.py)
-- Runs when this map is in Workspace (a server Script).
--   1. every part with a MaterialVariant gets that variant's BaseMaterial; tag P2NoPortal -> attribute NoPortal
--   2. placeholders -> clones from ReplicatedStorage.PortalAssets, tagged so your scripts run them (buttons, cubes,
--      lasers, catchers, fizzlers, funnels, bridges, pedestals, turrets, faith plates)
--   3. Portal 2's connections (P2IO): buttons, triggers, relays, branches, co-op managers, counters, timers, cube
--      makers, doors - "OnPressed -> door Open" etc. work like in Portal 2
local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local map = script.Parent

-- ==========================================
-- 1. MATERIALS
-- ==========================================
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
				if not p:HasTag("P2NoPortal") and BLOCKED[bases[mv]] and not warned[mv] then
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

-- ==========================================
-- 2. PLACEHOLDERS -> YOUR MODELS
-- ==========================================
local assets = ReplicatedStorage:FindFirstChild("PortalAssets")
local function findAsset(name)
	if not assets or not name then return nil end
	for _, folder in ipairs({ "TestElements", "TestingAssets", "EditorAssets", "Cubes" }) do
		local f = assets:FindFirstChild(folder)
		local a = f and f:FindFirstChild(name)
		if a then return a end
	end
	return assets:FindFirstChild(name, true)
end
-- the tags your scripts look for (PortalServer presses PeTIFloorButton models, TestElementsServer runs the rest)
local ELEMENT_TAGS = { Button = "PeTIFloorButton", Cube = "PortalCube", ["Laser Emitter"] = "LaserEmitter",
	["Laser Catcher"] = "LaserCatcher", Fizzler = "Fizzler", TBeam = "Funnel", LightBridgeFree = "LightBridge",
	PedestalButton = "PedestalButton", Turret = "Turret" }
local entInst = {} -- Portal 2 entity id -> the part / model standing for it
local function setAll(inst, k, v)
	inst:SetAttribute(k, v)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("Model") then d:SetAttribute(k, v) end
	end
end
-- ripped props (p2_models / the converter's Props folder): ReplicatedStorage.P2Models (or ServerStorage.P2Models)
-- holds the imported .glb models, named like the file (props_underground_crusher)
local MODEL_TURN = 0 -- degrees: if every imported prop faces the wrong way, try 180 (or 90 / -90)
local modelFolders = {}
for _, parent in ipairs({ ReplicatedStorage, game:GetService("ServerStorage"), map }) do
	local f = parent:FindFirstChild("P2Models")
	if f then table.insert(modelFolders, f) end
end
local missingModels, missingCount = {}, 0
local function placeModel(p)
	local name
	for _, t in ipairs(p:GetTags()) do name = t:match("^P2Mdl:(.+)$") or name end
	local template
	for _, f in ipairs(modelFolders) do
		local m = f:FindFirstChild(name, true)
		if m and (m:IsA("Model") or m:IsA("BasePart")) then template = m break end
	end
	if not template then
		if not missingModels[name] then
			missingModels[name] = true
			missingCount += 1
		end
		return nil
	end
	local c = template:Clone()
	local target = p.CFrame * CFrame.Angles(0, math.rad(MODEL_TURN), 0)
	local want = math.max(p.Size.X, p.Size.Y, p.Size.Z)
	local fit = not p:HasTag("P2NoBox")
	if c:IsA("Model") then
		local cf, size = c:GetBoundingBox()
		local have = math.max(size.X, size.Y, size.Z)
		if fit and have > 1e-3 and math.abs(want / have - 1) > 0.01 then
			c:ScaleTo(c:GetScale() * want / have)
			cf = c:GetBoundingBox()
		end
		c:PivotTo(target * (cf:Inverse() * c:GetPivot()))
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = true end
		end
	else
		local have = math.max(c.Size.X, c.Size.Y, c.Size.Z)
		if fit and have > 1e-3 then c.Size = c.Size * (want / have) end
		c.CFrame = target
		c.Anchored = true
	end
	for _, t in ipairs(p:GetTags()) do
		local k, v = t:match("^P2Attr:([^=]+)=(.*)$")
		if k then c:SetAttribute(k, v) end
	end
	c.Name = p.Name
	c.Parent = p.Parent
	p:Destroy()
	return c
end

for _, p in ipairs(map:GetDescendants()) do
	if p:IsA("BasePart") then
		local id
		for _, t in ipairs(p:GetTags()) do id = t:match("^P2Ent:(.+)$") or id end
		if p:HasTag("P2Model") then
			local c = placeModel(p)
			if id then entInst[id] = c or p end
		elseif p:HasTag("P2Placeholder") then
			local assetName, attrs = nil, {}
			for _, t in ipairs(p:GetTags()) do
				assetName = t:match("^P2Asset:(.+)$") or assetName
				local k, v = t:match("^P2Attr:([^=]+)=(.*)$")
				if k then attrs[k] = v end
			end
			local templateName = assetName
			if assetName == "Cube" and attrs.CubeType and findAsset(attrs.CubeType) then templateName = attrs.CubeType end
			local template = findAsset(templateName)
			if template then
				local c = template:Clone()
				local cf = p.CFrame
				if assetName == "FaithPlate" then cf = CFrame.new(p.Position - Vector3.new(0, p.Size.Y / 2, 0)) end -- on the floor of its trigger
				if c:IsA("Model") then c:PivotTo(cf) elseif c:IsA("BasePart") then c.CFrame = cf end
				for k, v in pairs(attrs) do c:SetAttribute(k, v) end
				if ELEMENT_TAGS[assetName] then c:AddTag(ELEMENT_TAGS[assetName]) end
				if id then c:AddTag("P2Ent:" .. id) end
				c.Parent = p.Parent
				p:Destroy()
				if id then entInst[id] = c end
			else
				warn("[P2MapSetup] no model '" .. tostring(templateName) .. "' in ReplicatedStorage.PortalAssets - left a placeholder")
				if id then entInst[id] = p end
			end
		elseif id then
			entInst[id] = p -- triggers / points
		end
	end
end

if missingCount > 0 then
	warn("[P2MapSetup] " .. missingCount .. " ripped models aren't in ReplicatedStorage.P2Models yet (their purple boxes stay)."
		.. " Import the .glb files the converter wrote (<map>_models) with Import 3D and put them in that folder.")
end

-- ==========================================
-- 3. PORTAL 2 I/O
-- ==========================================
local ioModule = map:FindFirstChild("P2IO")
local okIO, IO = false, nil
if ioModule then okIO, IO = pcall(require, ioModule) end
if not okIO or type(IO) ~= "table" then return end

local byName = {}
for id, e in pairs(IO) do
	e.id = id
	e.enabled = true
	if e.n ~= "" then
		byName[e.n] = byName[e.n] or {}
		table.insert(byName[e.n], e)
	end
end
local function kv(e, k) return e.kv and e.kv[k] end
local function num(x, d) return tonumber(x) or d end
local function alive() return map.Parent ~= nil end

local fire, input
local function targets(name, selfE)
	name = string.lower(name or "")
	if name == "!self" then return { selfE } end
	if name:sub(1, 1) == "!" then return {} end
	local out = {}
	if name:sub(-1) == "*" then
		local pre = name:sub(1, -2)
		for n, list in pairs(byName) do
			if n:sub(1, #pre) == pre then for _, e in ipairs(list) do table.insert(out, e) end end
		end
	else
		for _, e in ipairs(byName[name] or {}) do table.insert(out, e) end
	end
	return out
end

fire = function(e, output)
	local lo = string.lower(output)
	for _, o in ipairs(e.o or {}) do
		if string.lower(o[1]) == lo and o[6] ~= 0 then
			if o[6] > 0 then o[6] -= 1 end
			local tgt, inp, param = o[2], o[3], o[4]
			task.delay(o[5] or 0, function()
				if not alive() then return end
				for _, t in ipairs(targets(tgt, e)) do
					local ok, err = pcall(input, t, inp, param, e)
					if not ok then warn("[P2MapSetup] " .. tostring(t.n) .. "." .. tostring(inp) .. ": " .. tostring(err)) end
				end
			end)
		end
	end
end

local function setEnabled(e, on)
	e.enabled = on
	local inst = entInst[e.id]
	if inst and inst.Parent then setAll(inst, "Enabled", on) end
end

-- cube makers: a fresh cube of the template's type at the maker (the old one goes, like Portal 2)
local function cubeTypeOf(maker)
	for _, pt in ipairs(targets(kv(maker, "entitytemplate"), maker)) do
		for i = 1, 16 do
			local t = pt.kv and pt.kv[("template%02d"):format(i)]
			for _, ce in ipairs(targets(t, pt)) do
				if ce.cube then return ce.cube end
			end
		end
	end
	return "Normal"
end
local function spawnFromMaker(e)
	local at = entInst[e.id]
	if not at then return end
	if e.spawned and e.spawned.Parent then e.spawned:Destroy() end
	local kind = cubeTypeOf(e)
	local template = findAsset(kind) or findAsset("Cube")
	if not template then warn("[P2MapSetup] no cube model for the cube maker") return end
	local c = template:Clone()
	if c:IsA("Model") then c:PivotTo(at.CFrame) elseif c:IsA("BasePart") then c.CFrame = at.CFrame end
	c:SetAttribute("CubeType", kind)
	c:AddTag("PortalCube")
	c.Parent = map
	e.spawned = c
	fire(e, "OnEntitySpawned")
end

local function counterCheck(e)
	local mx, mn = num(kv(e, "max"), 0), num(kv(e, "min"), 0)
	if mx ~= 0 and e.value >= mx then
		e.value = mx
		fire(e, "OnHitMax")
	elseif (mn ~= 0 or mx ~= 0) and e.value <= mn then
		e.value = mn
		fire(e, "OnHitMin")
	end
end

local ON = { enable = true, turnon = true, activate = true, enablerefire = true, start = true }
local OFF = { disable = true, turnoff = true, deactivate = true, stop = true }
input = function(e, inp, param, caller)
	local i = string.lower(inp or "")
	local c = e.c
	local inst = entInst[e.id]
	local user = i:match("^fireuser(%d)$")
	if user then fire(e, "OnUser" .. user) return end
	if i == "kill" or i == "dissolve" or i == "killhierarchy" then
		if inst and inst.Parent then inst:Destroy() end
		entInst[e.id] = nil
		e.enabled = false
		return
	end
	if c == "prop_testchamber_door" then
		if i == "open" or i == "close" then
			local open = i == "open"
			if inst then inst:SetAttribute("Open", open) end -- the door model's own script opens / closes on "Open"
			fire(e, open and "OnOpen" or "OnClose")
			task.delay(1, function() fire(e, open and "OnFullyOpen" or "OnFullyClosed") end)
		end
		return
	elseif c == "logic_relay" then
		if i == "trigger" then
			if e.enabled then
				fire(e, "OnTrigger")
				if num(kv(e, "spawnflags"), 0) % 2 == 1 then e.enabled = false end -- "only trigger once"
			end
		elseif i == "enable" then e.enabled = true
		elseif i == "disable" then e.enabled = false
		elseif i == "toggle" then e.enabled = not e.enabled end
		return
	elseif c == "logic_branch" then
		e.value = e.value or num(kv(e, "initialvalue"), 0) ~= 0
		if i == "setvalue" or i == "setvaluetest" then e.value = num(param, 0) ~= 0
		elseif i == "toggle" or i == "toggletest" then e.value = not e.value end
		if i == "test" or i == "setvaluetest" or i == "toggletest" then fire(e, e.value and "OnTrue" or "OnFalse") end
		return
	elseif c == "logic_coop_manager" then
		if i == "setstateatrue" then e.a = true elseif i == "setstateafalse" then e.a = false
		elseif i == "setstatebtrue" then e.b = true elseif i == "setstatebfalse" then e.b = false end
		local all, any = (e.a and e.b) == true, (e.a or e.b) == true
		if all ~= (e.lastAll == true) then e.lastAll = all fire(e, all and "OnChangeToAllTrue" or "OnChangeToAnyFalse") end
		if any ~= (e.lastAny == true) then e.lastAny = any fire(e, any and "OnChangeToAnyTrue" or "OnChangeToAllFalse") end
		return
	elseif c == "math_counter" then
		e.value = e.value or num(kv(e, "startvalue"), 0)
		if i == "add" then e.value += num(param, 0) counterCheck(e)
		elseif i == "subtract" then e.value -= num(param, 0) counterCheck(e)
		elseif i == "setvalue" then e.value = num(param, 0) counterCheck(e)
		elseif i == "setvaluenofire" then e.value = num(param, 0)
		elseif i == "getvalue" then fire(e, "OnGetValue") end
		return
	elseif c == "logic_timer" then
		if i == "refiretime" then e.kv.refiretime = param end
		if ON[i] or i == "toggle" and not e.enabled then e.enabled = true e.timerToken = (e.timerToken or 0) + 1 e.startTimer()
		elseif OFF[i] or i == "toggle" then e.enabled = false e.timerToken = (e.timerToken or 0) + 1
		elseif i == "firetimer" then fire(e, "OnTimer") end
		return
	elseif c == "env_entity_maker" then
		if i == "forcespawn" then spawnFromMaker(e) end
		return
	elseif c == "prop_tractor_beam" and i == "setlinearforce" then
		local f = num(param, 250)
		if inst then
			setAll(inst, "Reversed", f < 0)
			setAll(inst, "Speed", math.clamp(math.abs(f) / 14.7, 2, 40))
		end
		return
	elseif c == "prop_floor_button" or c == "prop_floor_cube_button" or c == "prop_floor_ball_button" then
		if i == "pressin" then fire(e, "OnPressed") elseif i == "pressout" then fire(e, "OnUnPressed") end
		return
	elseif c == "prop_button" or c == "prop_under_button" then
		if i == "press" then fire(e, "OnPressed") end
		if ON[i] then e.enabled = true elseif OFF[i] then e.enabled = false end
		return
	end
	if ON[i] then setEnabled(e, true)
	elseif OFF[i] then setEnabled(e, false)
	elseif i == "toggle" then setEnabled(e, not e.enabled) end
end

-- ----- start states -----
for _, e in pairs(IO) do
	local k = e.kv or {}
	local startsOff = k.startdisabled == "1" or k.startenabled == "0" or (e.c == "env_portal_laser" and k.startstate == "1")
	if startsOff then setEnabled(e, false) end
	if e.c == "prop_tractor_beam" and k.linearforce then input(e, "SetLinearForce", k.linearforce) end
	if e.c == "logic_timer" then
		e.startTimer = function()
			local my = e.timerToken
			task.spawn(function()
				while alive() and e.enabled and e.timerToken == my do
					local lo, hi = num(k.lowerrandombound, 0), num(k.upperrandombound, 0)
					local wait = (k.usetrandomtime == "1" and hi > 0) and (lo + math.random() * (hi - lo)) or num(k.refiretime, 1)
					task.wait(math.max(wait, 0.05))
					if alive() and e.enabled and e.timerToken == my then fire(e, "OnTimer") end
				end
			end)
		end
		e.timerToken = 0
		if not startsOff then e.startTimer() end
	end
	-- faith plates aim at their launch target (FaithPlateServer reads AimPoint)
	if e.c == "trigger_catapult" and k.launchtarget then
		local inst = entInst[e.id]
		for _, t in ipairs(targets(k.launchtarget, e)) do
			local tp = entInst[t.id]
			if inst and tp and tp:IsA("BasePart") then inst:SetAttribute("AimPoint", tp.Position) end
		end
	end
end

-- ----- buttons / pedestals / catchers: their "Pressed" -> OnPressed / OnUnPressed ... -----
local function watchPressed(e, onOut, offOut)
	local inst = entInst[e.id]
	if not inst then return end
	local was = false
	local function check()
		local on = inst:GetAttribute("Pressed") == true or inst:GetAttribute("PressesButton") == true
		if not on then
			for _, d in ipairs(inst:GetDescendants()) do
				if (d:IsA("Model") or d:IsA("BasePart")) and (d:GetAttribute("Pressed") == true or d:GetAttribute("PressesButton") == true) then on = true break end
			end
		end
		if on == was then return end
		was = on
		if e.enabled == false then return end
		if on then fire(e, onOut) elseif offOut then fire(e, offOut) end
	end
	local function hook(d)
		if d:IsA("Model") or d:IsA("BasePart") then
			d:GetAttributeChangedSignal("Pressed"):Connect(check)
			d:GetAttributeChangedSignal("PressesButton"):Connect(check)
		end
	end
	hook(inst)
	for _, d in ipairs(inst:GetDescendants()) do hook(d) end
	inst.DescendantAdded:Connect(hook)
end
for _, e in pairs(IO) do
	if e.c == "prop_floor_button" or e.c == "prop_floor_cube_button" or e.c == "prop_floor_ball_button" then
		watchPressed(e, "OnPressed", "OnUnPressed")
	elseif e.c == "prop_button" or e.c == "prop_under_button" then
		watchPressed(e, "OnPressed", "OnButtonReset")
	elseif e.c == "prop_laser_catcher" or e.c == "prop_laser_relay" then
		watchPressed(e, "OnPowered", "OnUnpowered")
	end
end

-- ----- triggers: players walking in / out -----
local triggers = {}
for _, e in pairs(IO) do
	local inst = entInst[e.id]
	if inst and inst:IsA("BasePart") and inst:HasTag("P2Trigger") then
		e.inside = {}
		table.insert(triggers, e)
	end
end
if #triggers > 0 then
	task.spawn(function()
		local params = OverlapParams.new()
		while alive() do
			task.wait(0.1)
			for _, e in ipairs(triggers) do
				local part = entInst[e.id]
				if part and part.Parent and e.enabled ~= false then
					local now = {}
					for _, p in ipairs(workspace:GetPartBoundsInBox(part.CFrame, part.Size, params)) do
						local m = p:FindFirstAncestorOfClass("Model")
						local pl = m and Players:GetPlayerFromCharacter(m)
						if pl then now[pl] = true end
					end
					local wasEmpty = next(e.inside) == nil
					for pl in pairs(now) do
						if not e.inside[pl] then
							fire(e, "OnStartTouch")
							if wasEmpty then
								fire(e, "OnStartTouchAll")
								fire(e, "OnTrigger")
								if e.c == "trigger_once" then e.enabled = false end
							end
							wasEmpty = false
						end
					end
					for pl in pairs(e.inside) do
						if not now[pl] then fire(e, "OnEndTouch") end
					end
					if next(now) == nil and next(e.inside) ~= nil then fire(e, "OnEndTouchAll") end
					e.inside = now
				end
			end
		end
	end)
end

-- ----- the map starts -----
task.delay(0.5, function()
	for _, e in pairs(IO) do
		if e.c == "logic_auto" then
			for _, out in ipairs({ "OnMapSpawn", "OnNewGame", "OnMultiNewMap", "OnMultiNewRound", "OnMapTransition" }) do fire(e, out) end
		end
	end
end)
'''

# ---------------------------------------------------------------------------------------------------------------
def find_materials():
    # next to the .exe / .py first (so you can edit it), then the copy packed inside the .exe
    places = [os.path.dirname(os.path.abspath(sys.executable)) if getattr(sys, "frozen", False) else HERE,
              os.getcwd(), getattr(sys, "_MEIPASS", HERE), HERE]
    for d in places:
        p = os.path.join(d, "p2_materials.json")
        if os.path.isfile(p):
            return p
    return os.path.join(HERE, "p2_materials.json")

def main(argv=None):
    ap = argparse.ArgumentParser(description="Portal 2 map (.vmf / .bsp) -> Roblox model (.rbxmx)")
    ap.add_argument("input", help="the .vmf (best) or .bsp")
    ap.add_argument("-o", "--output", help="the .rbxmx to write (default: next to the input)")
    ap.add_argument("--name", help="the model's name (CoopHub for the co-op hub)")
    ap.add_argument("--scale", type=float, default=1 / 14.7, help="studs per Hammer unit (default 1/14.7)")
    ap.add_argument("--materials", default=find_materials(), help="texture -> MaterialVariant rules")
    ap.add_argument("--thickness", type=float, default=0.2, help="studs: thickness of odd shapes' faces")
    ap.add_argument("--no-face-plates", dest="face_plates", action="store_false", help="one material per box, no side plates")
    ap.add_argument("--no-lights", dest="lights", action="store_false", help="leave the lights out")
    ap.add_argument("--no-center", dest="center", action="store_false", help="keep Hammer's coordinates (else the map is centred, floor at Y = 0)")
    ap.add_argument("--game", help="the game's folder (…/steamapps/common/Portal 2) to rip the map's models from "
                                   "(found from the map's path when it's inside the game)")
    ap.add_argument("--no-models", dest="rip", action="store_false", help="don't rip the props' models (placeholders only)")
    ap.add_argument("--no-props", dest="props", action="store_false", help="leave props out completely")
    ap.add_argument("--models-dir", help="folder for the ripped .glb files (default: <output>_models)")
    ap.add_argument("--max-texture", type=int, default=1024, help="largest ripped texture size (default 1024)")
    opts = ap.parse_args(argv)
    if not os.path.isfile(opts.input):
        raise SystemExit("can't find the map: %s" % opts.input)
    if not os.path.isfile(opts.materials):
        raise SystemExit("can't find %s (keep p2_materials.json next to the converter)" % opts.materials)

    ext = os.path.splitext(opts.input)[1].lower()
    print("Reading", opts.input)
    if ext == ".vmf":
        brushes, entities = read_vmf(opts.input)
    elif ext == ".bsp":
        try:
            brushes, entities = read_bsp(opts.input)
        except (struct.error, IndexError, ValueError, lzma.LZMAError) as err:
            raise SystemExit("the .bsp looks cut off or damaged (%s). Decompile it to a .vmf with BSPSource and convert that." % err)
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
        pts = []
        for b in keep[:4000]:
            try:
                pts.extend(xf.p(v) for f in brush_faces(b) for v in f[2])
            except Exception:
                pass
        if pts:
            lo = tuple(min(p[i] for p in pts) for i in range(3))
            hi = tuple(max(p[i] for p in pts) for i in range(3))
            xf.offset = (-(lo[0] + hi[0]) / 2, -lo[1], -(lo[2] + hi[2]) / 2)

    name = opts.name or os.path.splitext(os.path.basename(opts.input))[0]
    out_path = opts.output or os.path.splitext(opts.input)[0] + ".rbxmx"
    stats = {"boxes": 0, "wedges": 0, "shapes": 0, "triangles": 0, "plates": 0, "skipped": 0, "degenerate": 0,
             "spawns": 0, "placeholders": 0, "lights": 0, "triggers": 0, "props_skipped": {}, "errors": [],
             "props": [], "ripped": 0, "rip_failed": 0}

    w = Writer()
    w.out.write('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n')
    w.open("Model", name)
    w.open("Folder", "Geometry")
    for i, b in enumerate(keep):
        mark = w.mark()
        try:
            convert_brush(w, b, xf, mats, opts, stats)
        except Exception as err:
            w.rollback(mark)
            stats["degenerate"] += 1
            if len(stats["errors"]) < 200:
                stats["errors"].append("brush %d (%s): %s" % (i, b.entity, err))
        if i and i % 2000 == 0:
            print("  %d / %d brushes" % (i, len(keep)))
    w.close()
    w.open("Folder", "Entities")
    io_records = convert_entities(w, entities, xf, mats, opts, stats)
    w.close()
    models_dir = None
    if stats["props"]:
        models_dir = opts.models_dir or os.path.splitext(out_path)[0] + "_models"
        w.open("Folder", "Props")
        convert_props(w, stats["props"], xf, opts, stats, models_dir)
        w.close()
    # Portal 2's connections, for the I/O part of P2MapSetup
    w.open("ModuleScript", "P2IO", '<ProtectedString name="Source"><![CDATA[return %s\n]]></ProtectedString>'
           % lua_value(io_records).replace("]]>", "] ]>"))
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
    print("  %d spawns, %d test element placeholders, %d triggers, %d lights; %d tool / trigger brushes skipped, %d broken brushes" %
          (stats["spawns"], stats["placeholders"], stats["triggers"], stats["lights"], stats["skipped"], stats["degenerate"]))
    print("  %d entities with names / connections kept for the map's I/O" % len(io_records))
    if stats["props"]:
        print("  %d props (%d models ripped%s)" % (len(stats["props"]), stats["ripped"],
              ", %d couldn't be ripped" % stats["rip_failed"] if stats["rip_failed"] else ""))
        if stats["ripped"]:
            print("  -> the models are in %s" % models_dir)
            print("     In Studio: Import 3D, pick all the .glb files (scale unit: Stud), and put the imported models in")
            print("     ReplicatedStorage > P2Models (make that folder). P2MapSetup swaps each prop placeholder for its model.")
    if stats["props_skipped"]:
        print("  models not converted (no .mdl support - add them by hand):",
              ", ".join("%s x%d" % kv for kv in sorted(stats["props_skipped"].items(), key=lambda kv: -kv[1])[:12]))
    if mats.unmatched:
        print("  textures with no rule in %s (grey for now - add rules for them):" % os.path.basename(opts.materials))
        for tex, n in sorted(mats.unmatched.items(), key=lambda kv: -kv[1])[:25]:
            print("    %-50s %d brush sides" % (tex, n))
    if stats["errors"]:
        print("  %d things couldn't be converted and were left out:" % len(stats["errors"]))
        for e in stats["errors"][:15]:
            print("    " + e)

class _QueueWriter:
    """print() from the conversion thread -> the window's log"""
    def __init__(self, q):
        self.q = q
    def write(self, text):
        if text:
            self.q.put(text)
    def flush(self):
        pass

def save_crash(text):
    for d in (os.getcwd(), os.path.dirname(os.path.abspath(sys.executable)) if getattr(sys, "frozen", False) else HERE,
              os.path.expanduser("~")):
        try:
            log = os.path.join(d, "p2_to_roblox_crash.txt")
            with open(log, "w", encoding="utf-8") as f:
                f.write(text)
            return log
        except OSError:
            continue
    return None

def gui(initial=None):
    """the converter's window: a "Convert a map" tab, a "Rip models" tab, and the log underneath"""
    import queue
    import subprocess
    import threading
    import tkinter as tk
    from tkinter import filedialog, ttk
    import p2_models

    root = tk.Tk()
    root.title("Portal 2 Map Converter")
    root.geometry("820x700")
    root.minsize(660, 560)
    try:
        ttk.Style(root).theme_use("vista" if sys.platform == "win32" else "clam")
    except tk.TclError:
        pass

    v_in = tk.StringVar(value=initial or "")
    v_out = tk.StringVar()
    v_name = tk.StringVar()
    v_units = tk.StringVar(value="14.7")
    v_mats = tk.StringVar(value=find_materials())
    v_plates = tk.BooleanVar(value=True)
    v_lights = tk.BooleanVar(value=True)
    v_center = tk.BooleanVar(value=True)
    v_hub = tk.BooleanVar(value=False)
    v_game = tk.StringVar(value=p2_models.find_game_dir(initial) or "")
    v_rip = tk.BooleanVar(value=True)
    v_search = tk.StringVar(value="crusher")
    v_ripdir = tk.StringVar(value=os.path.join(os.path.expanduser("~"), "Desktop", "Portal 2 models"))
    out_auto = {"path": ""}

    def default_out(*_):
        path = v_in.get().strip().strip('"')
        if path and (not v_out.get() or v_out.get() == out_auto["path"]):
            out_auto["path"] = (os.path.join(os.path.dirname(path), "CoopHub.rbxmx") if v_hub.get()
                                else os.path.splitext(path)[0] + ".rbxmx")
            v_out.set(out_auto["path"])
        if path and not v_game.get():
            v_game.set(p2_models.find_game_dir(path) or "")
    v_in.trace_add("write", default_out)

    def on_hub():
        if v_hub.get():
            v_name.set("CoopHub")
        elif v_name.get() == "CoopHub":
            v_name.set("")
        default_out()

    def pick_in():
        p = filedialog.askopenfilename(title="Portal 2 map", filetypes=[("Portal 2 maps", "*.vmf *.bsp"), ("All files", "*.*")])
        if p:
            v_in.set(p)
    def pick_out():
        p = filedialog.asksaveasfilename(title="Save the Roblox model as", defaultextension=".rbxmx",
                                         filetypes=[("Roblox model", "*.rbxmx")], initialfile=os.path.basename(v_out.get() or ""))
        if p:
            v_out.set(p)
    def pick_mats():
        p = filedialog.askopenfilename(title="Material rules", filetypes=[("JSON", "*.json"), ("All files", "*.*")])
        if p:
            v_mats.set(p)
    def pick_game():
        p = filedialog.askdirectory(title="The Portal 2 folder (steamapps/common/Portal 2)")
        if p:
            v_game.set(p2_models.find_game_dir(p) or p)
    def pick_ripdir():
        p = filedialog.askdirectory(title="Save the ripped models in")
        if p:
            v_ripdir.set(p)

    nb = ttk.Notebook(root)
    nb.pack(fill="x", padx=10, pady=(10, 0))

    # ---------------- tab 1: convert a map
    frm = ttk.Frame(nb, padding=12)
    nb.add(frm, text="  Convert a map  ")
    frm.columnconfigure(1, weight=1)

    def file_row(parent, r, label, var, cmd):
        ttk.Label(parent, text=label).grid(row=r, column=0, sticky="w", pady=3)
        ttk.Entry(parent, textvariable=var).grid(row=r, column=1, sticky="ew", padx=6, pady=3)
        ttk.Button(parent, text="Browse...", command=cmd).grid(row=r, column=2, pady=3)
    file_row(frm, 0, "Map (.vmf / .bsp)", v_in, pick_in)
    file_row(frm, 1, "Save as", v_out, pick_out)
    ttk.Label(frm, text="Model name").grid(row=2, column=0, sticky="w", pady=3)
    name_row = ttk.Frame(frm)
    name_row.grid(row=2, column=1, columnspan=2, sticky="ew", padx=6)
    name_row.columnconfigure(0, weight=1)
    ttk.Entry(name_row, textvariable=v_name).grid(row=0, column=0, sticky="ew")
    ttk.Checkbutton(name_row, text="This is the co-op hub", variable=v_hub, command=on_hub).grid(row=0, column=1, padx=(10, 0))
    ttk.Label(frm, text="(empty = the map's file name)", foreground="#777").grid(row=3, column=1, sticky="w", padx=6)

    props_box = ttk.LabelFrame(frm, text="Props (models)", padding=8)
    props_box.grid(row=4, column=0, columnspan=3, sticky="ew", pady=(8, 4))
    props_box.columnconfigure(1, weight=1)
    ttk.Label(props_box, text="Portal 2 folder").grid(row=0, column=0, sticky="w")
    ttk.Entry(props_box, textvariable=v_game).grid(row=0, column=1, sticky="ew", padx=6)
    ttk.Button(props_box, text="Browse...", command=pick_game).grid(row=0, column=2)
    ttk.Checkbutton(props_box, text="Rip the props' models with their textures and rigs (.glb files next to the map)",
                    variable=v_rip).grid(row=1, column=0, columnspan=3, sticky="w", pady=(6, 0))

    opts_box = ttk.LabelFrame(frm, text="Options", padding=8)
    opts_box.grid(row=5, column=0, columnspan=3, sticky="ew", pady=(4, 6))
    ttk.Label(opts_box, text="Hammer units per stud").grid(row=0, column=0, sticky="w")
    ttk.Entry(opts_box, textvariable=v_units, width=8).grid(row=0, column=1, sticky="w", padx=(6, 18))
    ttk.Checkbutton(opts_box, text="Side plates (one texture per side)", variable=v_plates).grid(row=0, column=2, sticky="w", padx=(0, 12))
    ttk.Checkbutton(opts_box, text="Lights", variable=v_lights).grid(row=0, column=3, sticky="w", padx=(0, 12))
    ttk.Checkbutton(opts_box, text="Centre the map", variable=v_center).grid(row=0, column=4, sticky="w")
    mats_row = ttk.Frame(opts_box)
    mats_row.grid(row=1, column=0, columnspan=6, sticky="ew", pady=(8, 0))
    mats_row.columnconfigure(1, weight=1)
    ttk.Label(mats_row, text="Material rules").grid(row=0, column=0, sticky="w")
    ttk.Entry(mats_row, textvariable=v_mats).grid(row=0, column=1, sticky="ew", padx=6)
    ttk.Button(mats_row, text="Browse...", command=pick_mats).grid(row=0, column=2)
    convert_btn = ttk.Button(frm, text="Convert")
    convert_btn.grid(row=6, column=0, sticky="w", pady=(4, 0))

    # ---------------- tab 2: rip models
    rip = ttk.Frame(nb, padding=12)
    nb.add(rip, text="  Rip models  ")
    rip.columnconfigure(1, weight=1)
    file_row(rip, 0, "Portal 2 folder", v_game, pick_game)
    ttk.Label(rip, text="Search").grid(row=1, column=0, sticky="w", pady=3)
    search_entry = ttk.Entry(rip, textvariable=v_search)
    search_entry.grid(row=1, column=1, sticky="ew", padx=6, pady=3)
    find_btn = ttk.Button(rip, text="Find")
    find_btn.grid(row=1, column=2, pady=3)
    ttk.Label(rip, text="a word (crusher, turret, cube) or a pattern (models/props_underground/*.mdl)",
              foreground="#777").grid(row=2, column=1, sticky="w", padx=6)
    list_frame = ttk.Frame(rip)
    list_frame.grid(row=3, column=0, columnspan=3, sticky="nsew", pady=4)
    found = tk.Listbox(list_frame, selectmode="extended", height=8, activestyle="none")
    lsb = ttk.Scrollbar(list_frame, command=found.yview)
    found.configure(yscrollcommand=lsb.set)
    lsb.pack(side="right", fill="y")
    found.pack(side="left", fill="both", expand=True)
    file_row(rip, 4, "Save to", v_ripdir, pick_ripdir)
    rip_btns = ttk.Frame(rip)
    rip_btns.grid(row=5, column=0, columnspan=3, sticky="w", pady=(4, 0))
    rip_sel_btn = ttk.Button(rip_btns, text="Rip selected")
    rip_sel_btn.pack(side="left")
    rip_all_btn = ttk.Button(rip_btns, text="Rip all found")
    rip_all_btn.pack(side="left", padx=6)
    found_label = ttk.Label(rip_btns, text="")
    found_label.pack(side="left", padx=8)

    # ---------------- shared: status + log
    bottom = ttk.Frame(root, padding=(10, 6, 10, 10))
    bottom.pack(fill="both", expand=True)
    btns = ttk.Frame(bottom)
    btns.pack(fill="x", pady=(0, 6))
    open_btn = ttk.Button(btns, text="Open folder", state="disabled")
    open_btn.pack(side="left")
    bar = ttk.Progressbar(btns, mode="indeterminate", length=180)
    bar.pack(side="right")
    status = ttk.Label(btns, text="")
    status.pack(side="right", padx=8)
    log_frame = ttk.Frame(bottom)
    log_frame.pack(fill="both", expand=True)
    log = tk.Text(log_frame, wrap="word", height=10, font=("Consolas", 9), state="disabled", background="#1e1e1e",
                  foreground="#dcdcdc", insertbackground="#dcdcdc", relief="flat", padx=6, pady=6)
    sb = ttk.Scrollbar(log_frame, command=log.yview)
    log.configure(yscrollcommand=sb.set)
    sb.pack(side="right", fill="y")
    log.pack(side="left", fill="both", expand=True)
    log.tag_configure("err", foreground="#ff8080")
    log.tag_configure("ok", foreground="#8fe08f")

    def write_log(text, tag=None):
        log.configure(state="normal")
        log.insert("end", text, tag)
        log.see("end")
        log.configure(state="disabled")
    def clear_log():
        log.configure(state="normal")
        log.delete("1.0", "end")
        log.configure(state="disabled")

    q = queue.Queue()
    state = {"busy": False, "open": None, "done_text": ""}
    busy_buttons = (convert_btn, find_btn, rip_sel_btn, rip_all_btn)

    def worker(fn):
        old_out, old_err = sys.stdout, sys.stderr
        sys.stdout = sys.stderr = _QueueWriter(q)
        result = ("ok", None)
        try:
            fn()
        except SystemExit as e:
            if e.code not in (None, 0):
                result = ("stop", str(e.code))
        except BaseException:
            import traceback
            result = ("crash", traceback.format_exc())
        finally:
            sys.stdout, sys.stderr = old_out, old_err
        q.put(result)

    def poll():
        try:
            while True:
                item = q.get_nowait()
                if isinstance(item, tuple) and item[0] == "list":
                    found.delete(0, "end")
                    for p in item[1]:
                        found.insert("end", p)
                    found_label.configure(text="%d models" % len(item[1]))
                elif isinstance(item, tuple):
                    finish(*item)
                else:
                    write_log(item)
        except queue.Empty:
            pass
        if state["busy"]:
            root.after(80, poll)

    def start(fn, text, open_path=None, done_text=""):
        if state["busy"]:
            return False
        state["busy"], state["open"], state["done_text"] = True, open_path, done_text
        clear_log()
        for b in busy_buttons:
            b.configure(state="disabled")
        open_btn.configure(state="disabled")
        status.configure(text=text)
        bar.start(12)
        threading.Thread(target=worker, args=(fn,), daemon=True).start()
        root.after(80, poll)
        return True

    def finish(kind, detail):
        state["busy"] = False
        bar.stop()
        for b in busy_buttons:
            b.configure(state="normal")
        if kind == "ok":
            status.configure(text="Done")
            if state["done_text"]:
                write_log("\n" + state["done_text"] + "\n", "ok")
            if state["open"]:
                open_btn.configure(state="normal")
        elif kind == "stop":
            status.configure(text="Stopped")
            write_log("\nStopped: %s\n" % detail, "err")
        else:
            status.configure(text="Crashed")
            where = save_crash(detail)
            write_log("\nThe converter crashed:\n%s" % detail, "err")
            if where:
                write_log("Saved this to %s - send it to whoever fixes the tool.\n" % where, "err")

    def convert():
        path = v_in.get().strip().strip('"')
        if not path:
            write_log("Pick a map first.\n", "err")
            return
        try:
            units = float(v_units.get())
            if units <= 0:
                raise ValueError
        except ValueError:
            write_log("Hammer units per stud must be a number above 0 (14.7 is normal).\n", "err")
            return
        argv = [path, "--scale", repr(1 / units), "--materials", v_mats.get().strip()]
        out = v_out.get().strip().strip('"')
        if out:
            argv += ["-o", out]
        if v_name.get().strip():
            argv += ["--name", v_name.get().strip()]
        if not v_plates.get():
            argv.append("--no-face-plates")
        if not v_lights.get():
            argv.append("--no-lights")
        if not v_center.get():
            argv.append("--no-center")
        if v_game.get().strip():
            argv += ["--game", v_game.get().strip()]
        if not v_rip.get():
            argv.append("--no-models")
        start(lambda: main(argv), "Converting...", out or os.path.splitext(path)[0] + ".rbxmx",
              "Done - drag the .rbxmx into Studio (or right-click > Insert from File).")

    fs_cache = {}
    def game_fs():
        game = v_game.get().strip()
        if not game or not os.path.isdir(game):
            raise SystemExit("set the Portal 2 folder first (…/steamapps/common/Portal 2)")
        game = p2_models.find_game_dir(game) or game
        if fs_cache.get("dir") != game:
            print("Reading the game's files...")
            fs_cache["dir"], fs_cache["fs"] = game, p2_models.GameFS(game)
        return fs_cache["fs"]

    def find_models():
        pattern = v_search.get().strip() or "*"
        def run_find():
            items = game_fs().find(pattern)
            q.put(("list", items))
            print("%d models match \"%s\"" % (len(items), pattern))
            if not items:
                print("(try a shorter word, or * for every model)")
        start(run_find, "Searching...")

    def rip_paths(paths):
        if not paths:
            write_log("Find some models first (and select the ones you want).\n", "err")
            return
        out_dir = v_ripdir.get().strip() or "ripped_models"
        def run_rip():
            r = p2_models.Ripper(game_fs(), out_dir)
            ok = 0
            for p in paths:
                try:
                    info = r.rip(p)
                    ok += 1
                    print("%s -> %s.glb (%d triangles%s)" % (p, info["name"], info["tris"],
                          ", rig with %d bones" % info["bones"] if info["bones"] > 1 else ""))
                except Exception as err:
                    print("couldn't rip %s: %s" % (p, err))
            print("\n%d of %d models ripped into %s" % (ok, len(paths), out_dir))
        start(run_rip, "Ripping...", os.path.join(out_dir, "."),
              "In Studio: Import 3D, pick the .glb files (scale unit: Stud). Rigged models come in with their Bones.")

    def open_folder():
        target = state["open"] or ""
        folder = target if os.path.isdir(target) else os.path.dirname(os.path.abspath(target))
        try:
            if sys.platform == "win32":
                if os.path.isfile(target):
                    subprocess.Popen(["explorer", "/select,", os.path.abspath(target)])
                else:
                    os.startfile(folder)  # noqa - Windows only
            elif sys.platform == "darwin":
                subprocess.Popen(["open", folder])
            else:
                subprocess.Popen(["xdg-open", folder])
        except OSError as err:
            write_log("Couldn't open the folder: %s\n" % err, "err")

    convert_btn.configure(command=convert)
    find_btn.configure(command=find_models)
    search_entry.bind("<Return>", lambda _e: find_models())
    rip_sel_btn.configure(command=lambda: rip_paths([found.get(i) for i in found.curselection()]))
    rip_all_btn.configure(command=lambda: rip_paths(list(found.get(0, "end"))))
    open_btn.configure(command=open_folder)
    write_log("Convert a map: pick a Portal 2 map (.vmf is best - decompile a .bsp with BSPSource) and press Convert.\n"
              "With the Portal 2 folder set, the map's props are ripped too (.glb with textures and rigs).\n"
              "Rip models: search the game's models and rip any of them.\n")
    if initial:
        default_out()
    root.mainloop()

def console_fallback():
    """no window possible: ask in the console"""
    print("Portal 2 map -> Roblox converter")
    path = input("Map file (drag it into this window, then press Enter): ").strip().strip('"').strip("'")
    if not path:
        raise SystemExit("no map picked")
    name = input("Model name (Enter = the map's name, CoopHub for the co-op hub): ").strip()
    return [path] + (["--name", name] if name else [])

def run():
    frozen = getattr(sys, "frozen", False)
    # the windowed .exe has no console: command-line runs print nowhere instead of crashing
    if sys.stdout is None:
        sys.stdout = open(os.devnull, "w")
    if sys.stderr is None:
        sys.stderr = open(os.devnull, "w")
    args = sys.argv[1:]
    # the window: when double-clicked (no options) or as the .exe; a map dragged onto it is filled in
    if not args or (frozen and len(args) == 1 and os.path.isfile(args[0])) or args == ["--gui"]:
        initial = args[0] if args and args[0] != "--gui" else None
        try:
            import tkinter  # noqa: F401
            gui(initial)
            return
        except ImportError:
            pass
        args = [initial] if initial else None
    interactive = sys.stdin is not None and sys.stdout is not None and (not sys.argv[1:] or frozen)
    code = 0
    try:
        main(args if args else console_fallback())
    except SystemExit as e:
        if e.code not in (None, 0):
            print("\nStopped:", e.code)
            code = 1
    except BaseException:
        import traceback
        code = 1
        text = traceback.format_exc()
        print("\nThe converter crashed:\n" + text)
        where = save_crash(text)
        if where:
            print("Saved this to", where, "- send it to whoever fixes the tool.")
    if interactive:
        try:
            input("\nPress Enter to close...")
        except (EOFError, KeyboardInterrupt, RuntimeError):
            pass
    sys.exit(code)

if __name__ == "__main__":
    run()
