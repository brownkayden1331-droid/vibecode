#!/usr/bin/env python3
"""
p2_models.py - rip Source engine (Portal 2) models into .glb files Roblox Studio's 3D importer can open.

    python p2_models.py --game "D:/SteamLibrary/steamapps/common/Portal 2" --find crusher
    python p2_models.py --game "D:/.../Portal 2" --rip "models/props_underground/*.mdl" -o ripped

What you get per model (<name>.glb):
    the mesh (LOD 0, the default body groups, the default skin), its textures (from the .vtf, as PNG inside the .glb),
    and the skeleton (rig) with skin weights when the model has more than one bone, so it imports as a rigged
    MeshPart with Bones you can animate in Roblox. Positions are in studs (14.7 Hammer units = 1 stud) with Roblox's
    axes, so import with the scale unit set to Stud.
    Animations (.mdl sequences / .ani) are not converted.

Files come from (first match wins): the map's own pakfile (when converting a .bsp), then the game's loose files and
VPKs: update, portal2_dlc3, portal2_dlc2, portal2_dlc1, portal2 (and any other folder with a pak01_dir.vpk).
Only the Python standard library is used.
"""
import fnmatch
import json
import math
import os
import re
import struct
import zipfile
import zlib
import io

SCALE = 1 / 14.7

# ---------------------------------------------------------------------------------------------------------------
# game files: the map's pakfile, loose folders, VPKs
# ---------------------------------------------------------------------------------------------------------------
def norm(path):
    return re.sub(r"/+", "/", path.replace("\\", "/")).lower().lstrip("/")

class PakSource:
    """the .bsp's pakfile lump (a zip)"""
    def __init__(self, blob):
        self.zip = zipfile.ZipFile(io.BytesIO(blob))
        self.names = {norm(n): n for n in self.zip.namelist()}
    def read(self, p):
        n = self.names.get(p)
        return self.zip.read(n) if n else None
    def list(self):
        return self.names.keys()

class DirSource:
    """loose files in a content folder (portal2/, portal2_dlc1/...)"""
    def __init__(self, root):
        self.root = root
        self._listed = None
    def read(self, p):
        full = os.path.join(self.root, *p.split("/"))
        if os.path.isfile(full):
            with open(full, "rb") as f:
                return f.read()
        return None
    def list(self):
        if self._listed is None:
            self._listed = []
            for sub in ("models", "materials"):
                top = os.path.join(self.root, sub)
                for dirpath, _dirs, files in os.walk(top):
                    rel = os.path.relpath(dirpath, self.root)
                    for fn in files:
                        self._listed.append(norm(os.path.join(rel, fn)))
        return self._listed

VPK_SIG = 0x55AA1234

class VpkSource:
    """a pak01_dir.vpk and its pak01_NNN.vpk archives"""
    def __init__(self, dir_path):
        self.prefix = dir_path[:-len("_dir.vpk")] if dir_path.lower().endswith("_dir.vpk") else dir_path[:-4]
        with open(dir_path, "rb") as f:
            data = f.read()
        sig, version, tree_len = struct.unpack_from("<III", data, 0)
        if sig != VPK_SIG or version not in (1, 2):
            raise ValueError("not a VPK directory: " + dir_path)
        pos = 12 if version == 1 else 28
        self.data_start = pos + tree_len
        self.entries = {}
        self.dir_data = data
        self.handles = {}

        def cstr():
            nonlocal pos
            end = data.index(b"\0", pos)
            s = data[pos:end].decode("latin-1")
            pos = end + 1
            return s
        while pos < self.data_start:
            ext = cstr()
            if not ext:
                break
            while True:
                folder = cstr()
                if not folder:
                    break
                while True:
                    name = cstr()
                    if not name:
                        break
                    _crc, pre_len, arch, ofs, ln, _term = struct.unpack_from("<IHHIIH", data, pos)
                    pos += 18
                    pre = data[pos:pos + pre_len]
                    pos += pre_len
                    full = ("" if folder.strip() == "" else folder + "/") + name + ("" if ext.strip() == "" else "." + ext)
                    self.entries[norm(full)] = (arch, ofs, ln, pre)

    def read(self, p):
        e = self.entries.get(p)
        if not e:
            return None
        arch, ofs, ln, pre = e
        if ln == 0:
            return pre
        if arch == 0x7FFF:
            return pre + self.dir_data[self.data_start + ofs:self.data_start + ofs + ln]
        fh = self.handles.get(arch)
        if fh is None:
            fh = self.handles[arch] = open("%s_%03d.vpk" % (self.prefix, arch), "rb")
        fh.seek(ofs)
        return pre + fh.read(ln)

    def list(self):
        return self.entries.keys()

CONTENT_ORDER = ("update", "portal2_dlc3", "portal2_dlc2", "portal2_dlc1", "portal2")

def find_game_dir(path):
    """from a map's path (…/Portal 2/portal2/maps/x.bsp) or any folder inside the game: the game's root folder"""
    if not path:
        return None
    d = os.path.abspath(path)
    if os.path.isfile(d):
        d = os.path.dirname(d)
    for _ in range(8):
        for name in CONTENT_ORDER:
            if os.path.isfile(os.path.join(d, name, "pak01_dir.vpk")):
                return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return None

class GameFS:
    def __init__(self, game_dir=None, pak_blob=None, log=print):
        self.sources = []
        self.log = log
        if pak_blob:
            try:
                self.sources.append(PakSource(pak_blob))
            except (zipfile.BadZipFile, ValueError, OSError):
                log("  (the map's pakfile couldn't be read)")
        if game_dir:
            folders = [n for n in CONTENT_ORDER if os.path.isdir(os.path.join(game_dir, n))]
            try:
                others = sorted(n for n in os.listdir(game_dir)
                                if n not in folders and os.path.isfile(os.path.join(game_dir, n, "pak01_dir.vpk")))
            except OSError:
                others = []
            for n in folders + others:
                root = os.path.join(game_dir, n)
                self.sources.append(DirSource(root))
                vpk = os.path.join(root, "pak01_dir.vpk")
                if os.path.isfile(vpk):
                    try:
                        self.sources.append(VpkSource(vpk))
                    except (ValueError, OSError, struct.error) as err:
                        log("  couldn't read %s: %s" % (vpk, err))

    def read(self, path):
        p = norm(path)
        for s in self.sources:
            data = s.read(p)
            if data is not None:
                return data
        return None

    def find(self, pattern):
        """model paths (models/...mdl) matching a pattern: a glob (models/props/*.mdl) or just a word (crusher)"""
        pat = norm(pattern)
        if not any(c in pat for c in "*?["):
            pat = "*" + pat + "*"
        out = set()
        for s in self.sources:
            for p in s.list():
                if p.endswith(".mdl") and fnmatch.fnmatchcase(p, pat):
                    out.add(p)
        return sorted(out)

# ---------------------------------------------------------------------------------------------------------------
# .mdl / .vvd / .vtx
# ---------------------------------------------------------------------------------------------------------------
def cstr_at(data, ofs):
    if ofs < 0 or ofs >= len(data):
        return ""
    end = data.find(b"\0", ofs)
    if end < 0:
        end = len(data)
    return data[ofs:end].decode("latin-1")

class Mdl:
    pass

def parse_mdl(data):
    if data[:4] != b"IDST":
        raise ValueError("not a .mdl")
    m = Mdl()
    m.version = struct.unpack_from("<i", data, 4)[0]
    if not 44 <= m.version <= 49:
        raise ValueError("unsupported .mdl version %d" % m.version)
    m.name = cstr_at(data, 12)
    numbones, boneindex = struct.unpack_from("<ii", data, 156)
    (numtex, texindex, numcd, cdindex, numskinref, numfam, skinindex,
     numbody, bodyindex) = struct.unpack_from("<9i", data, 204)
    if not (0 <= numbones < 1024 and 0 <= numtex < 1024 and 0 <= numbody < 256):
        raise ValueError("damaged .mdl header")
    m.bones = []
    for i in range(numbones):
        b = boneindex + i * 216
        nameofs, parent = struct.unpack_from("<ii", data, b)
        pos = struct.unpack_from("<3f", data, b + 32)
        quat = struct.unpack_from("<4f", data, b + 44)
        p2b = struct.unpack_from("<12f", data, b + 96)
        m.bones.append({"name": cstr_at(data, b + nameofs) or "bone%d" % i, "parent": parent, "pos": pos,
                        "quat": quat, "pose_to_bone": p2b})
    m.textures = []
    for i in range(numtex):
        b = texindex + i * 64
        m.textures.append(cstr_at(data, b + struct.unpack_from("<i", data, b)[0]).replace("\\", "/"))
    m.cdmaterials = []
    for i in range(numcd):
        p = cstr_at(data, struct.unpack_from("<i", data, cdindex + i * 4)[0]).replace("\\", "/").strip("/")
        m.cdmaterials.append(p + "/" if p else "")
    m.skins = []
    for f in range(numfam):
        m.skins.append(list(struct.unpack_from("<%dh" % numskinref, data, skinindex + f * numskinref * 2)))
    m.bodyparts = []
    for i in range(numbody):
        b = bodyindex + i * 16
        nameofs, nummodels, _base, modelindex = struct.unpack_from("<4i", data, b)
        models = []
        for j in range(nummodels):
            mb = b + modelindex + j * 148
            name = data[mb:mb + 64].split(b"\0")[0].decode("latin-1")
            (_type, _radius, nummeshes, meshindex, numverts, vertindex) = struct.unpack_from("<ifiiii", data, mb + 64)
            meshes = []
            for k in range(nummeshes):
                eb = mb + meshindex + k * 116
                material, _mi, mnumverts, vertoffset = struct.unpack_from("<4i", data, eb)
                meshes.append({"material": material, "numverts": mnumverts, "vertoffset": vertoffset})
            models.append({"name": name, "numverts": numverts, "vertstart": vertindex // 48, "meshes": meshes})
        m.bodyparts.append({"name": cstr_at(data, b + nameofs), "models": models})
    return m

def parse_vvd(data):
    """-> list of LOD 0 vertices: (pos, normal, uv, [(bone, weight)])"""
    if data[:4] != b"IDSV":
        raise ValueError("not a .vvd")
    lods = struct.unpack_from("<8i", data, 16)
    numfix, fixstart, vertstart = struct.unpack_from("<3i", data, 48)
    count = lods[0]
    order = None
    if numfix > 0:
        order = []
        for i in range(numfix):
            lod, src, n = struct.unpack_from("<3i", data, fixstart + i * 12)
            if lod >= 0:
                order.extend(range(src, src + n))
    out = []
    for idx in (order if order is not None else range(count)):
        b = vertstart + idx * 48
        w = struct.unpack_from("<3f", data, b)
        bones = struct.unpack_from("<3B", data, b + 12)
        nb = data[b + 15]
        pos = struct.unpack_from("<3f", data, b + 16)
        nrm = struct.unpack_from("<3f", data, b + 28)
        uv = struct.unpack_from("<2f", data, b + 40)
        out.append((pos, nrm, uv, [(bones[i], w[i]) for i in range(min(nb, 3)) if w[i] > 0]))
    return out

def parse_vtx(data, sg_size):
    """-> [bodypart][model] -> [mesh] -> [mesh-local vertex ids, 3 per triangle] (LOD 0)"""
    (_ver, _vc, _mbs, _mbt, _mbv, _chk, _numlods, _mr, numbody, bodyofs) = struct.unpack_from("<iiHHiiiiii", data, 0)
    strip_size = 27 if sg_size == 25 else 35
    if not 0 <= numbody < 256:
        raise ValueError("damaged .vtx")
    result = []
    for bp in range(numbody):
        bpb = bodyofs + bp * 8
        nmodels, mofs = struct.unpack_from("<ii", data, bpb)
        models = []
        for mi in range(nmodels):
            mb = bpb + mofs + mi * 8
            nlods, lofs = struct.unpack_from("<ii", data, mb)
            meshes = []
            if nlods > 0:
                lb = mb + lofs
                nmesh, meshofs = struct.unpack_from("<ii", data, lb)
                for k in range(nmesh):
                    meb = lb + meshofs + k * 9
                    nsg, sgofs = struct.unpack_from("<ii", data, meb)
                    tris = []
                    for g in range(nsg):
                        sgb = meb + sgofs + g * sg_size
                        nv, vofs, ni, iofs, ns, sofs = struct.unpack_from("<6i", data, sgb)
                        if not (0 <= nv <= 65536 and 0 <= ni <= 3000000 and 0 <= ns <= 65536):
                            raise ValueError("bad strip group")
                        if sgb + vofs + nv * 9 > len(data) or sgb + iofs + ni * 2 > len(data):
                            raise ValueError("strip group out of range")
                        orig = [struct.unpack_from("<H", data, sgb + vofs + v * 9 + 4)[0] for v in range(nv)]
                        idx = struct.unpack_from("<%dH" % ni, data, sgb + iofs)
                        if any(i >= nv for i in idx):
                            raise ValueError("index out of range")
                        strips = []
                        for s in range(ns):
                            sb = sgb + sofs + s * strip_size
                            sni, sio, _snv, _svo, _snb, sflags = struct.unpack_from("<iiiihB", data, sb)
                            strips.append((sni, sio, sflags))
                        if any(f & 2 for _, _, f in strips):  # triangle strips (old compiles)
                            for sni, sio, f in strips:
                                seq = idx[sio:sio + sni]
                                if f & 2:
                                    for t in range(len(seq) - 2):
                                        a, b, c = seq[t], seq[t + 1], seq[t + 2]
                                        if a == b or b == c or a == c:
                                            continue
                                        tris.extend((orig[a], orig[b], orig[c]) if t % 2 == 0 else (orig[b], orig[a], orig[c]))
                                else:
                                    tris.extend(orig[i] for i in seq[:len(seq) - len(seq) % 3])
                        else:
                            if ni % 3:
                                raise ValueError("index count not a multiple of 3")
                            tris.extend(orig[i] for i in idx)
                    meshes.append(tris)
            models.append(meshes)
        result.append(models)
    return result

def read_vtx(data, mdl):
    """the strip group header is 25 bytes in older models and 33 in newer ones (Portal 2 has both): try both"""
    order = (33, 25) if mdl.version >= 49 else (25, 33)
    last = None
    for sg in order:
        try:
            res = parse_vtx(data, sg)
            # must match the .mdl's layout
            ok = len(res) == len(mdl.bodyparts) and all(
                len(res[i]) == len(bp["models"]) and all(
                    len(res[i][j]) == len(md["meshes"]) and all(
                        all(v < me["numverts"] for v in res[i][j][k]) for k, me in enumerate(md["meshes"]))
                    for j, md in enumerate(bp["models"]))
                for i, bp in enumerate(mdl.bodyparts))
            if ok:
                return res
            last = ValueError("the .vtx doesn't match the .mdl")
        except (struct.error, ValueError, IndexError) as err:
            last = err
    raise last

# ---------------------------------------------------------------------------------------------------------------
# materials: .vmt -> base texture, .vtf -> RGBA
# ---------------------------------------------------------------------------------------------------------------
TOKEN_RE = re.compile(r'"([^"]*)"|(\{)|(\})|//[^\n]*|([^\s{}"]+)')

def parse_vmt(text):
    """-> (shader, {lower key: value}) of the top level (nested blocks like proxies skipped, patch handled outside)"""
    tokens = []
    for m in TOKEN_RE.finditer(text):
        if m.group(1) is not None:
            tokens.append(("s", m.group(1)))
        elif m.group(2):
            tokens.append(("{", "{"))
        elif m.group(3):
            tokens.append(("}", "}"))
        elif m.group(4) is not None:
            tokens.append(("s", m.group(4)))
    shader, keys, blocks = "", {}, {}
    i = 0
    if i < len(tokens) and tokens[i][0] == "s":
        shader = tokens[i][1].lower()
        i += 1
    if i < len(tokens) and tokens[i][0] == "{":
        i += 1
    depth_stack = []
    current = keys
    while i < len(tokens):
        kind, val = tokens[i]
        if kind == "}":
            if not depth_stack:
                break
            current = depth_stack.pop()
            i += 1
            continue
        if kind == "s":
            if i + 1 < len(tokens) and tokens[i + 1][0] == "{":
                block = {}
                if current is keys:
                    blocks[val.lower()] = block
                depth_stack.append(current)
                current = block
                i += 2
                continue
            if i + 1 < len(tokens) and tokens[i + 1][0] == "s":
                current.setdefault(val.lower(), tokens[i + 1][1])
                i += 2
                continue
        i += 1
    return shader, keys, blocks

def load_material(fs, mdl, tex_name):
    """-> (vmt path, {keys}) or (None, {})"""
    name = tex_name.lower().replace("\\", "/").strip("/")
    for cd in mdl.cdmaterials + [""]:
        path = "materials/" + (cd.lower() + name if cd else name) + ".vmt"
        data = fs.read(path)
        if data is None:
            continue
        shader, keys, blocks = parse_vmt(data.decode("utf-8", "replace"))
        if shader == "patch" and keys.get("include"):
            inc = fs.read(keys["include"])
            if inc is not None:
                _s, base, _b = parse_vmt(inc.decode("utf-8", "replace"))
                for blk in ("replace", "insert"):
                    for k, v in blocks.get(blk, {}).items():
                        if isinstance(v, str):
                            base[k] = v
                keys = base
        return path, keys
    return None, {}

FORMAT_BITS = {0: 32, 1: 32, 2: 24, 3: 24, 4: 16, 5: 8, 6: 16, 8: 8, 9: 24, 10: 24, 11: 32, 12: 32, 16: 32, 17: 16,
               18: 16, 19: 16, 21: 16, 22: 16, 23: 32, 24: 64, 25: 64, 26: 32}
BLOCK_BYTES = {13: 8, 14: 16, 15: 16, 20: 8}

def frame_size(fmt, w, h):
    if fmt in BLOCK_BYTES:
        return ((w + 3) // 4) * ((h + 3) // 4) * BLOCK_BYTES[fmt]
    return w * h * FORMAT_BITS[fmt] // 8

def _c565(c):
    r, g, b = (c >> 11) & 31, (c >> 5) & 63, c & 31
    return (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)

def decode_dxt(data, w, h, fmt):
    out = bytearray(w * h * 4)
    bw, bh = (w + 3) // 4, (h + 3) // 4
    step = BLOCK_BYTES[fmt]
    pos = 0
    for by in range(bh):
        for bx in range(bw):
            blk = data[pos:pos + step]
            pos += step
            alphas = None
            if fmt == 15:  # DXT5: interpolated alpha
                a0, a1 = blk[0], blk[1]
                bits = int.from_bytes(blk[2:8], "little")
                if a0 > a1:
                    pal = [a0, a1] + [((7 - i) * a0 + i * a1) // 7 for i in range(1, 7)]
                else:
                    pal = [a0, a1] + [((5 - i) * a0 + i * a1) // 5 for i in range(1, 5)] + [0, 255]
                alphas = [pal[(bits >> (3 * i)) & 7] for i in range(16)]
                cblk = blk[8:]
            elif fmt == 14:  # DXT3: explicit alpha
                bits = int.from_bytes(blk[0:8], "little")
                alphas = [((bits >> (4 * i)) & 15) * 17 for i in range(16)]
                cblk = blk[8:]
            else:
                cblk = blk
            c0, c1, idx = struct.unpack_from("<HHI", cblk, 0)
            r0, g0, b0 = _c565(c0)
            r1, g1, b1 = _c565(c1)
            if c0 > c1 or fmt in (14, 15):
                cols = [(r0, g0, b0, 255), (r1, g1, b1, 255),
                        ((2 * r0 + r1) // 3, (2 * g0 + g1) // 3, (2 * b0 + b1) // 3, 255),
                        ((r0 + 2 * r1) // 3, (g0 + 2 * g1) // 3, (b0 + 2 * b1) // 3, 255)]
            else:
                cols = [(r0, g0, b0, 255), (r1, g1, b1, 255),
                        ((r0 + r1) // 2, (g0 + g1) // 2, (b0 + b1) // 2, 255), (0, 0, 0, 0 if fmt == 20 else 255)]
            for py in range(4):
                y = by * 4 + py
                if y >= h:
                    break
                row = y * w
                for px in range(4):
                    x = bx * 4 + px
                    if x >= w:
                        break
                    i = py * 4 + px
                    c = cols[(idx >> (2 * i)) & 3]
                    o = (row + x) * 4
                    out[o] = c[0]
                    out[o + 1] = c[1]
                    out[o + 2] = c[2]
                    out[o + 3] = alphas[i] if alphas is not None else c[3]
    return out

def decode_plain(data, w, h, fmt):
    n = w * h
    out = bytearray(n * 4)
    bpp = FORMAT_BITS[fmt] // 8
    for i in range(n):
        p = data[i * bpp:(i + 1) * bpp]
        if fmt == 0:
            r, g, b, a = p
        elif fmt == 1:
            a, b, g, r = p
        elif fmt in (2, 9):
            r, g, b = p
            a = 255
        elif fmt in (3, 10):
            b, g, r = p
            a = 255
        elif fmt == 11:
            a, r, g, b = p
        elif fmt == 12:
            b, g, r, a = p
        elif fmt == 16:
            b, g, r, _x = p
            a = 255
        elif fmt == 5:
            r = g = b = p[0]
            a = 255
        elif fmt == 6:
            r = g = b = p[0]
            a = p[1]
        elif fmt == 8:
            r = g = b = 255
            a = p[0]
        elif fmt in (4, 17):
            v = p[0] | p[1] << 8
            x, y, z = (v >> 11) & 31, (v >> 5) & 63, v & 31
            r, g, b = (x * 255 // 31, y * 255 // 63, z * 255 // 31) if fmt == 4 else (z * 255 // 31, y * 255 // 63, x * 255 // 31)
            a = 255
        elif fmt in (18, 21):
            v = p[0] | p[1] << 8
            b, g, r = (v & 31) * 255 // 31, ((v >> 5) & 31) * 255 // 31, ((v >> 10) & 31) * 255 // 31
            a = 255 if fmt == 18 or v >> 15 else 0
        elif fmt == 19:
            v = p[0] | p[1] << 8
            b, g, r, a = (v & 15) * 17, ((v >> 4) & 15) * 17, ((v >> 8) & 15) * 17, ((v >> 12) & 15) * 17
        else:
            r, g, b, a = 128, 128, 128, 255
        o = i * 4
        out[o:o + 4] = bytes((r, g, b, a))
    return out

def decode_vtf(data, max_size=1024):
    """-> (width, height, RGBA bytes) of the biggest mip that fits max_size, first frame"""
    if data[:4] != b"VTF\0":
        raise ValueError("not a .vtf")
    major, minor = struct.unpack_from("<II", data, 4)
    (header_size, width, height, flags, frames, _first) = struct.unpack_from("<IHHIHH", data, 12)
    high_fmt = struct.unpack_from("<i", data, 52)[0]
    mips = data[56]
    low_fmt = struct.unpack_from("<i", data, 57)[0]
    low_w, low_h = data[61], data[62]
    if high_fmt not in FORMAT_BITS and high_fmt not in BLOCK_BYTES:
        raise ValueError("texture format %d isn't supported" % high_fmt)
    if high_fmt in (24, 25):
        raise ValueError("HDR textures aren't supported")
    depth = 1
    if minor >= 2:
        depth = max(1, struct.unpack_from("<H", data, 63)[0])
    faces = 1
    if flags & 0x4000:  # environment map
        faces = 6 if minor >= 5 else 7
    high_ofs = -1
    if minor >= 3:
        nres = struct.unpack_from("<I", data, 68)[0]
        for i in range(nres):
            rid, _rf, rdata = struct.unpack_from("<3sBI", data, 80 + i * 8)
            if rid == b"\x30\0\0":
                high_ofs = rdata
    if high_ofs < 0:
        low = frame_size(low_fmt, low_w, low_h) if low_fmt >= 0 else 0
        high_ofs = header_size + low
    # mips are stored smallest first; pick the largest that fits
    want = 0
    while want < mips - 1 and max(width >> want, height >> want) > max_size:
        want += 1
    ofs = high_ofs
    for mip in range(mips - 1, want, -1):
        mw, mh = max(1, width >> mip), max(1, height >> mip)
        ofs += frame_size(high_fmt, mw, mh) * frames * faces * depth
    w, h = max(1, width >> want), max(1, height >> want)
    size = frame_size(high_fmt, w, h)
    blob = data[ofs:ofs + size]
    if len(blob) < size:
        raise ValueError("texture data cut off")
    if high_fmt in BLOCK_BYTES:
        return w, h, decode_dxt(blob, w, h, high_fmt)
    return w, h, decode_plain(blob, w, h, high_fmt)

def png_bytes(w, h, rgba, keep_alpha):
    if keep_alpha:
        stride, color_type, px = w * 4, 6, rgba
    else:
        px = bytearray(w * h * 3)
        px[0::3] = rgba[0::4]
        px[1::3] = rgba[1::4]
        px[2::3] = rgba[2::4]
        stride, color_type = w * 3, 2
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += px[y * stride:(y + 1) * stride]

    def chunk(tag, body):
        c = struct.pack(">I", len(body)) + tag + body
        return c + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))

# ---------------------------------------------------------------------------------------------------------------
# Source -> Roblox space, matrices
# ---------------------------------------------------------------------------------------------------------------
def rb(v, s=1.0):
    """Source (x fwd, y left, z up) -> Roblox (x, y up, z): (x, z, -y)"""
    return (v[0] * s, v[2] * s, -v[1] * s)

C = ((1, 0, 0), (0, 0, 1), (0, -1, 0))  # rows: Roblox from Source

def mat3_mul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))

def mat3_t(a):
    return tuple(tuple(a[j][i] for j in range(3)) for i in range(3))

def conv_affine(rot, t, s):
    """Source affine (3x3 rot, translation) -> Roblox: C R C^-1, s C t"""
    return mat3_mul(mat3_mul(C, rot), mat3_t(C)), rb(t, s)

def affine_inv(rot, t):
    rt = mat3_t(rot)
    return rt, tuple(-sum(rt[i][k] * t[k] for k in range(3)) for i in range(3))

def affine_mul(a, b):
    ra, ta = a
    rb_, tb = b
    return mat3_mul(ra, rb_), tuple(sum(ra[i][k] * tb[k] for k in range(3)) + ta[i] for i in range(3))

def orthonormal(r):
    """clean up a rotation (bones' matrices are floats; glTF wants exact rotations)"""
    x = r[0][0], r[1][0], r[2][0]
    y = r[0][1], r[1][1], r[2][1]
    def nrm(v):
        l = math.sqrt(sum(c * c for c in v)) or 1.0
        return tuple(c / l for c in v)
    def crs(a, b):
        return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
    x = nrm(x)
    z = nrm(crs(x, y))
    y = crs(z, x)
    return ((x[0], y[0], z[0]), (x[1], y[1], z[1]), (x[2], y[2], z[2]))

def mat_to_quat(m):
    tr = m[0][0] + m[1][1] + m[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        w, x, y, z = 0.25 * s, (m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s
    elif m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
        w, x, y, z = (m[2][1] - m[1][2]) / s, 0.25 * s, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s
    elif m[1][1] > m[2][2]:
        s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
        w, x, y, z = (m[0][2] - m[2][0]) / s, (m[0][1] + m[1][0]) / s, 0.25 * s, (m[1][2] + m[2][1]) / s
    else:
        s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
        w, x, y, z = (m[1][0] - m[0][1]) / s, (m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, 0.25 * s
    l = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
    return (x / l, y / l, z / l, w / l)

# ---------------------------------------------------------------------------------------------------------------
# .glb writer
# ---------------------------------------------------------------------------------------------------------------
class Glb:
    def __init__(self):
        self.bin = bytearray()
        self.views, self.accessors = [], []
    def view(self, blob, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        v = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(blob)}
        if target:
            v["target"] = target
        self.bin += blob
        self.views.append(v)
        return len(self.views) - 1
    def accessor(self, fmt, ctype, atype, values, flat, target=None, minmax=False):
        blob = struct.pack("<%d%s" % (len(flat), fmt), *flat)
        a = {"bufferView": self.view(blob, target), "componentType": ctype, "count": len(values), "type": atype}
        if minmax:
            n = len(values[0])
            a["min"] = [min(v[i] for v in values) for i in range(n)]
            a["max"] = [max(v[i] for v in values) for i in range(n)]
        self.accessors.append(a)
        return len(self.accessors) - 1
    def write(self, path, gltf):
        gltf["buffers"] = [{"byteLength": len(self.bin)}]
        gltf["bufferViews"] = self.views
        gltf["accessors"] = self.accessors
        js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
        js += b" " * ((4 - len(js) % 4) % 4)
        binb = bytes(self.bin) + b"\0" * ((4 - len(self.bin) % 4) % 4)
        total = 12 + 8 + len(js) + 8 + len(binb)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
            f.write(struct.pack("<II", len(binb), 0x004E4942) + binb)

# ---------------------------------------------------------------------------------------------------------------
# ripping
# ---------------------------------------------------------------------------------------------------------------
def model_name(path):
    """models/props_underground/crusher.mdl -> props_underground_crusher (the .glb's and the Roblox model's name)"""
    p = norm(path)
    if p.startswith("models/"):
        p = p[7:]
    if p.endswith(".mdl"):
        p = p[:-4]
    return re.sub(r"[^a-z0-9_\-]+", "_", p)[:90] or "model"

class Ripper:
    def __init__(self, fs, out_dir, log=print, max_tex=1024, scale=SCALE):
        self.fs, self.out_dir, self.log = fs, out_dir, log
        self.max_tex, self.scale = max_tex, scale
        self.tex_cache = {}
        self.done = {}  # model path -> info dict or None (failed)
        os.makedirs(out_dir, exist_ok=True)

    def texture(self, mdl, tex_name):
        """-> (png bytes or None, alpha mode, material name)"""
        vmt_path, keys = load_material(self.fs, mdl, tex_name)
        base = keys.get("$basetexture")
        alpha = "OPAQUE"
        if keys.get("$translucent", "0").strip() not in ("0", ""):
            alpha = "BLEND"
        elif keys.get("$alphatest", "0").strip() not in ("0", ""):
            alpha = "MASK"
        if not base:
            return None, alpha
        key = (norm(base), alpha)
        if key in self.tex_cache:
            return self.tex_cache[key], alpha
        png = None
        data = self.fs.read("materials/" + norm(base).replace(".vtf", "") + ".vtf")
        if data is not None:
            try:
                w, h, rgba = decode_vtf(data, self.max_tex)
                png = png_bytes(w, h, rgba, alpha != "OPAQUE")
            except (ValueError, struct.error, IndexError, KeyError) as err:
                self.log("    texture %s: %s" % (base, err))
        else:
            self.log("    missing texture materials/%s.vtf" % base)
        self.tex_cache[key] = png
        return png, alpha

    def rip(self, path):
        """-> info {name, file, min, max, bones} (Roblox studs, model space) or None"""
        p = norm(path)
        if not p.endswith(".mdl"):
            p += ".mdl"
        if p in self.done:
            return self.done[p]
        self.done[p] = None
        mdl_b = self.fs.read(p)
        if mdl_b is None:
            raise FileNotFoundError("model not found: " + p)
        base = p[:-4]
        vvd_b = self.fs.read(base + ".vvd")
        vtx_b = None
        for ext in (".dx90.vtx", ".vtx", ".dx80.vtx", ".sw.vtx"):
            vtx_b = self.fs.read(base + ext)
            if vtx_b is not None:
                break
        if vvd_b is None or vtx_b is None:
            raise FileNotFoundError("%s has no %s" % (p, ".vvd" if vvd_b is None else ".vtx"))
        mdl = parse_mdl(mdl_b)
        verts = parse_vvd(vvd_b)
        vtx = read_vtx(vtx_b, mdl)
        info = self.write_glb(p, mdl, verts, vtx)
        self.done[p] = info
        return info

    def write_glb(self, path, mdl, verts, vtx):
        name = model_name(path)
        s = self.scale
        skin_row = mdl.skins[0] if mdl.skins else []
        # triangles per material (body part model 0 = the default body)
        groups = {}
        for bi, bp in enumerate(mdl.bodyparts):
            if not bp["models"]:
                continue
            md = bp["models"][0]
            for k, me in enumerate(md["meshes"]):
                tris = vtx[bi][0][k]
                if not tris:
                    continue
                first = md["vertstart"] + me["vertoffset"]
                mat = me["material"]
                tex = skin_row[mat] if 0 <= mat < len(skin_row) else mat
                lst = groups.setdefault(tex, [])
                lst.extend(first + v for v in tris)
        if not groups:
            raise ValueError("no triangles")
        if max(max(g) for g in groups.values()) >= len(verts):
            raise ValueError("the .vvd has fewer vertices than the model uses")

        rigged = len(mdl.bones) > 1
        glb = Glb()
        # node 0 = the mesh; node 1 = the rig's root (rigged models only), its children the root bones
        gltf = {"asset": {"version": "2.0", "generator": "p2_models.py"}, "scene": 0, "scenes": [{"nodes": [0]}],
                "nodes": [], "meshes": [], "materials": [], "textures": [],
                "images": [], "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]}
        prims = []
        lo, hi = [1e18] * 3, [-1e18] * 3
        for tex, ids in groups.items():
            # winding: make the triangles face the way the normals point (glTF = counter-clockwise)
            score = 0.0
            for t in range(0, len(ids), 3):
                a, b, c = (verts[ids[t + i]] for i in range(3))
                pa, pb, pc = a[0], b[0], c[0]
                e1 = (pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2])
                e2 = (pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2])
                n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
                vn = [a[1][i] + b[1][i] + c[1][i] for i in range(3)]
                score += n[0] * vn[0] + n[1] * vn[1] + n[2] * vn[2]
            flip = score < 0
            local, order, idx = {}, [], []
            for t in range(0, len(ids), 3):
                tri = (ids[t], ids[t + 2], ids[t + 1]) if flip else (ids[t], ids[t + 1], ids[t + 2])
                for v in tri:
                    if v not in local:
                        local[v] = len(order)
                        order.append(v)
                    idx.append(local[v])
            pos = [rb(verts[v][0], s) for v in order]
            nrm = []
            for v in order:
                n = rb(verts[v][1])
                l = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]) or 1.0
                nrm.append((n[0] / l, n[1] / l, n[2] / l))
            uvs = [verts[v][2] for v in order]
            for q in pos:
                for i in range(3):
                    lo[i], hi[i] = min(lo[i], q[i]), max(hi[i], q[i])
            attrs = {"POSITION": glb.accessor("f", 5126, "VEC3", pos, [c for q in pos for c in q], 34962, True),
                     "NORMAL": glb.accessor("f", 5126, "VEC3", nrm, [c for q in nrm for c in q], 34962),
                     "TEXCOORD_0": glb.accessor("f", 5126, "VEC2", uvs, [c for q in uvs for c in q], 34962)}
            if rigged:
                joints, weights = [], []
                for v in order:
                    bw = verts[v][3][:4] or [(0, 1.0)]
                    tot = sum(w for _, w in bw) or 1.0
                    j = [b for b, _ in bw] + [0] * (4 - len(bw))
                    w = [x / tot for _, x in bw] + [0.0] * (4 - len(bw))
                    joints.append(j)
                    weights.append(w)
                attrs["JOINTS_0"] = glb.accessor("H", 5123, "VEC4", joints, [c for q in joints for c in q], 34962)
                attrs["WEIGHTS_0"] = glb.accessor("f", 5126, "VEC4", weights, [c for q in weights for c in q], 34962)
            big = len(order) > 65535
            ind = glb.accessor("I" if big else "H", 5125 if big else 5123, "SCALAR", [(i,) for i in idx], idx, 34963)
            # material
            tex_name = mdl.textures[tex] if 0 <= tex < len(mdl.textures) else "material%d" % tex
            png, alpha = self.texture(mdl, tex_name)
            mat = {"name": tex_name.split("/")[-1], "doubleSided": False,
                   "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 1.0}}
            if alpha != "OPAQUE":
                mat["alphaMode"] = alpha
            if png:
                gltf["images"].append({"bufferView": glb.view(png), "mimeType": "image/png", "name": mat["name"]})
                gltf["textures"].append({"source": len(gltf["images"]) - 1, "sampler": 0})
                mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": len(gltf["textures"]) - 1}
            else:
                mat["pbrMetallicRoughness"]["baseColorFactor"] = [0.6, 0.6, 0.6, 1.0]
            gltf["materials"].append(mat)
            prims.append({"attributes": attrs, "indices": ind, "material": len(gltf["materials"]) - 1})
        gltf["meshes"].append({"name": name, "primitives": prims})
        mesh_node = {"name": name, "mesh": 0}
        gltf["nodes"].append(mesh_node)

        if rigged:
            # the rest pose = the bind pose (from poseToBone), so the mesh shows exactly as in Source
            binds = []
            for b in mdl.bones:
                m = b["pose_to_bone"]
                rot = ((m[0], m[1], m[2]), (m[4], m[5], m[6]), (m[8], m[9], m[10]))
                t = (m[3], m[7], m[11])
                r2, t2 = conv_affine(rot, t, s)
                binds.append((orthonormal(r2), t2))  # model -> bone (inverse bind)
            gltf["nodes"].append({"name": name + "_rig", "children": []})
            gltf["scenes"][0]["nodes"].append(1)
            first_joint = len(gltf["nodes"])
            for i, b in enumerate(mdl.bones):
                world = affine_inv(*binds[i])
                par = b["parent"]
                local = affine_mul(binds[par], world) if 0 <= par < len(mdl.bones) else world
                q = mat_to_quat(orthonormal(local[0]))
                gltf["nodes"].append({"name": b["name"], "translation": list(local[1]), "rotation": list(q)})
            for i, b in enumerate(mdl.bones):
                par = b["parent"]
                if 0 <= par < len(mdl.bones):
                    gltf["nodes"][first_joint + par].setdefault("children", []).append(first_joint + i)
                else:
                    gltf["nodes"][1]["children"].append(first_joint + i)
            ibm = []
            for r, t in binds:  # column-major 4x4
                ibm += [r[0][0], r[1][0], r[2][0], 0.0, r[0][1], r[1][1], r[2][1], 0.0,
                        r[0][2], r[1][2], r[2][2], 0.0, t[0], t[1], t[2], 1.0]
            acc = glb.accessor("f", 5126, "MAT4", [None] * len(binds), ibm)
            gltf["skins"] = [{"name": name + "_rig", "joints": list(range(first_joint, first_joint + len(mdl.bones))),
                              "inverseBindMatrices": acc}]
            mesh_node["skin"] = 0
        for k in ("textures", "images"):
            if not gltf[k]:
                del gltf[k]
        if "textures" not in gltf:
            del gltf["samplers"]
        file = os.path.join(self.out_dir, name + ".glb")
        glb.write(file, gltf)
        return {"name": name, "file": file, "min": tuple(lo), "max": tuple(hi), "bones": len(mdl.bones),
                "tris": sum(len(g) // 3 for g in groups.values())}

# ---------------------------------------------------------------------------------------------------------------
def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description="Rip Source (Portal 2) models to .glb (mesh, textures, rig)")
    ap.add_argument("--game", required=True, help="the game's folder (…/steamapps/common/Portal 2)")
    ap.add_argument("--find", help="list models whose path matches (a word or a glob like models/props/*.mdl)")
    ap.add_argument("--rip", action="append", default=[], help="model path or glob to rip (repeatable)")
    ap.add_argument("-o", "--output", default="ripped_models", help="folder for the .glb files")
    ap.add_argument("--max-texture", type=int, default=1024, help="largest texture size (default 1024)")
    opts = ap.parse_args(argv)
    fs = GameFS(opts.game)
    if opts.find:
        for p in fs.find(opts.find):
            print(p)
    paths = []
    for pat in opts.rip:
        paths += fs.find(pat) if any(c in pat for c in "*?[") else [pat]
    if paths:
        r = Ripper(fs, opts.output, max_tex=opts.max_texture)
        for p in paths:
            try:
                info = r.rip(p)
                print("ripped %s -> %s (%d triangles, %d bones)" % (p, info["file"], info["tris"], info["bones"]))
            except Exception as err:  # keep going with the rest
                print("couldn't rip %s: %s" % (p, err))

if __name__ == "__main__":
    main()
