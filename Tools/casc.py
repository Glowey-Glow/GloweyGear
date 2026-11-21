import os, struct, zlib, glob, io
ROOT = r"D:\World of Warcraft"
DATA = os.path.join(ROOT, "Data")

def build_config(product):
    lines = open(os.path.join(ROOT, ".build.info"), encoding="utf-8").read().splitlines()
    hdr = [h.split("!")[0] for h in lines[0].split("|")]
    for l in lines[1:]:
        r = dict(zip(hdr, l.split("|")))
        if r["Product"] == product:
            k = r["Build Key"]
            p = os.path.join(DATA, "config", k[:2], k[2:4], k)
            cfg = {}
            for ln in open(p, encoding="utf-8"):
                if " = " in ln:
                    a, b = ln.strip().split(" = ", 1); cfg[a] = b.split()
            return cfg
    raise KeyError(product)

class Casc:
    def __init__(self, product="wowf"):
        self.cfg = build_config(product)
        self.idx = {}
        newest = {}
        for f in glob.glob(os.path.join(DATA, "data", "*.idx")):
            b = os.path.basename(f); bucket = b[:2]; ver = int(b[2:10], 16)
            if bucket not in newest or ver > newest[bucket][0]: newest[bucket] = (ver, f)
        for ver, f in newest.values():
            d = open(f, "rb").read()
            hl = struct.unpack_from("<I", d, 0)[0]
            # header: len, hash, version(2), bucket(1), extra(1), sizeB, offB, keyB, ...
            sizeB, offB, keyB, fbits = d[12], d[13], d[14], d[15]
            pos = (8 + hl + 0x0F) & ~0x0F
            dl = struct.unpack_from("<I", d, pos)[0]; pos += 8
            end = pos + dl
            rec = keyB + offB + sizeB
            while pos + rec <= end:
                key = d[pos:pos+keyB]
                hi = d[pos+keyB]; lo = struct.unpack_from(">I", d, pos+keyB+1)[0]
                size = struct.unpack_from("<I", d, pos+keyB+offB)[0]
                arch = (hi << 2) | (lo >> 30); off = lo & 0x3FFFFFFF
                if key not in self.idx: self.idx[key] = (arch, off, size)
                pos += rec
        self.enc = None; self.root = None; self.names = None
        self.handles = {}

    def raw(self, ekey):
        arch, off, size = self.idx[ekey[:9]]
        h = self.handles.get(arch)
        if h is None:
            h = self.handles[arch] = open(os.path.join(DATA, "data", "data.%03d" % arch), "rb")
        h.seek(off + 30)
        return blte(h.read(size - 30))

    def load(self):
        ekey = bytes.fromhex(self.cfg["encoding"][1])
        d = self.raw(ekey)
        assert d[:2] == b"EN"
        ck, ek = d[3], d[4]
        cps, eps = struct.unpack_from(">HH", d, 5)
        cpc, epc = struct.unpack_from(">II", d, 9)
        espec = struct.unpack_from(">I", d, 18)[0]
        pos = 22 + espec + cpc * (ck + 16)
        self.enc = {}
        for i in range(cpc):
            p = pos + i * cps * 1024; e = p + cps * 1024
            while p < e:
                n = d[p]
                if n == 0: break
                c = d[p+6:p+6+ck]
                self.enc[c] = d[p+6+ck:p+6+ck+ek]
                p += 6 + ck + n * ek
        r = self.raw(self.enc[bytes.fromhex(self.cfg["root"][0])])
        self.root = {}; self.names = {}
        p = 0
        assert r[:4] == b"TSFM", r[:4]
        hs = struct.unpack_from("<I", r, 4)[0]
        if hs > 1000: # old header: total, named
            p = 12
            newfmt = False
        else:
            ver = struct.unpack_from("<I", r, 8)[0]
            p = hs; newfmt = ver >= 2
        while p < len(r):
            if newfmt:
                n, loc, f1, f2, f3 = struct.unpack_from("<IIIIB", r, p); p += 17
                cflags = f1 | f2 | (f3 << 17)
            else:
                n, cflags, loc = struct.unpack_from("<III", r, p); p += 12
            ids = []; fid = -1
            for d4 in struct.unpack_from("<%dI" % n, r, p):
                fid += d4 + 1; ids.append(fid)
            p += 4 * n
            cks = [r[p+16*i:p+16*i+16] for i in range(n)]; p += 16 * n
            hashes = None
            if not (cflags & 0x10000000):
                hashes = struct.unpack_from("<%dQ" % n, r, p); p += 8 * n
            ok = (loc & 0x2) or loc == 0xFFFFFFFF or (loc & 0x1FFFF) == 0x1FFFF
            for i, f in enumerate(ids):
                if ok or f not in self.root: 
                    if ok or f not in self.root: self.root[f] = cks[i]
                if hashes: self.names[hashes[i]] = f
        return self

    def get(self, fid):
        return self.raw(self.enc[self.root[fid]])

def blte(d):
    assert d[:4] == b"BLTE", d[:8]
    hs = struct.unpack_from(">I", d, 4)[0]
    out = []
    if hs == 0:
        chunks = [(len(d) - 8, 8)]
    else:
        n = struct.unpack_from(">I", d, 8)[0] & 0xFFFFFF
        chunks = []; p = hs
        for i in range(n):
            cs = struct.unpack_from(">I", d, 12 + i * 24)[0]
            chunks.append((cs, p)); p += cs
    for cs, p in chunks:
        m = d[p:p+1]; body = d[p+1:p+cs]
        if m == b"N": out.append(body)
        elif m == b"Z": out.append(zlib.decompress(body))
        else: raise ValueError("mode %r" % m)
    return b"".join(out)

if __name__ == "__main__":
    c = Casc().load()
    print("idx", len(c.idx), "enc", len(c.enc), "root", len(c.root), "named", len(c.names))
