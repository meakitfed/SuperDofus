"""
Reads the Dofus 3 client's native code (roadmap P1.13g): the rules the client itself runs (zone
shapes, spell previews...) are compiled by IL2CPP into GameAssembly.dll; the Cpp2IL assemblies
MelonLoader leaves in the install keep every method's name and address ([Address(RVA=...)]).

    python tools/client_code/client_code.py names                  # method addresses -> <work>/names.tsv
    python tools/client_code/client_code.py import                 # Ghidra project of GameAssembly.dll, labelled
    python tools/client_code/client_code.py strings                # decrypted string literals -> <work>/strings.tsv
    python tools/client_code/client_code.py find "SpellZoneShape.*blhx"     # methods matching a regex
    python tools/client_code/client_code.py xref 0x1eb28f0         # functions calling that address
    python tools/client_code/client_code.py decomp out.c "Shapes\\..*Cone" 0x1ec6d50   # decompile (regexes or RVAs)
    python tools/client_code/client_code.py usage 0x1862770e0      # metadata slot (lRam... in decomp) -> type
    python tools/client_code/client_code.py refs 0x1862770e0       # functions reading that data address

<work> = %LOCALAPPDATA%/SuperDofus/client_code (outside the repo: the output is Ankama's code, never
commit it). Ghidra: GHIDRA_HOME (default C:/dofus3_reversing/ghidra/ghidra_12.1.3_PUBLIC) and
JAVA_HOME (default C:/dofus3_reversing/jdk21/jdk-21). `import` takes a few minutes and ~500 MB, no
auto-analysis: `decomp` creates the functions it needs. Names are obfuscated for most classes
(`gru.blgy`), the namespaces and many types are not (`SpellZoneShapeCircleBehavior`); cite a rule
as "client code <Type>.<method>" with what it does, in the rule's comment. Once `strings` has run,
`decomp` writes the obfuscated string literals out (STR('a')) in place of their accessor calls.
"""
from __future__ import annotations

import bisect
import os
import re
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCAL = Path(os.environ.get("LOCALAPPDATA", ""))
GAME = LOCAL / "Ankama" / "Dofus-dofus3"
DLL = GAME / "GameAssembly.dll"
WORK = LOCAL / "SuperDofus" / "client_code"
NAMES = WORK / "names.tsv"
GHIDRA = Path(os.environ.get("GHIDRA_HOME", "C:/dofus3_reversing/ghidra/ghidra_12.1.3_PUBLIC"))
JAVA = os.environ.get("JAVA_HOME", "C:/dofus3_reversing/jdk21/jdk-21")


def load_names() -> dict[int, str]:
    out: dict[int, str] = {}
    for line in NAMES.read_text(encoding="utf-8").splitlines():
        r, n = line.split("\t", 1)
        out.setdefault(int(r, 16), n)
    return out


def find(pattern: str) -> list[tuple[int, str]]:
    pat = re.compile(pattern)
    return [(r, n) for r, n in sorted(load_names().items()) if pat.search(n)]


def callers(targets: list[int]) -> dict[int, list[int]]:
    """E8 / E9 rel32 calls to each target, in the code section (named "il2cpp", not .text)."""
    data = DLL.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    nsec, opt = struct.unpack_from("<H", data, pe + 6)[0], struct.unpack_from("<H", data, pe + 20)[0]
    out: dict[int, list[int]] = {t: [] for t in targets}
    for i in range(nsec):
        o = pe + 24 + opt + 40 * i
        if data[o:o + 8].rstrip(b"\0") not in (b"il2cpp", b".text"):
            continue
        vsize, va, rsize, raw = struct.unpack_from("<IIII", data, o + 8)
        buf = data[raw:raw + rsize]
        for m in re.finditer(b"[\xe8\xe9]", buf):
            p = m.start()
            if p + 5 > len(buf):
                break
            t = va + p + 5 + struct.unpack_from("<i", buf, p + 1)[0]
            if t in out:
                out[t].append(va + p)
    return out


def sections(data: bytes) -> list[tuple[bytes, int, int, int]]:
    """(name, rva, virtual size, file offset) of each PE section."""
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    nsec, opt = struct.unpack_from("<H", data, pe + 6)[0], struct.unpack_from("<H", data, pe + 20)[0]
    out = []
    for i in range(nsec):
        o = pe + 24 + opt + 40 * i
        vsize, va, rsize, raw = struct.unpack_from("<IIII", data, o + 8)
        out.append((data[o:o + 8].rstrip(b"\0"), va, vsize, raw))
    return out


# The string literals are obfuscated (P1.13h): `<PrivateImplementationDetails>{..}.a::<name>()` returns
# a string cut from one byte array (a::.cctor: its initial data, byte i ^= i ^ 0xAA), each accessor
# being `xor r9d,r9d; mov edx,<offset>; mov ecx,<index>; lea r8d,[r9+<length>]` (or mov r8d,<length>).
ACCESSOR = re.compile(rb"\x45\x33\xc9\xba(....)\xb9(....)(?:\x45\x8d\x41(.)|\x41\xb8(....)|\x45\x8d\x81(....))", re.S)
METADATA = GAME / "Dofus_Data" / "il2cpp_data" / "Metadata" / "global-metadata.dat"
STRINGS = WORK / "strings.tsv"


def build_strings() -> None:
    """<work>/strings.tsv: accessor name -> decrypted literal."""
    names = [(r, n) for r, n in load_names().items() if "<PrivateImplementationDetails>" in n and ".a::" in n]
    data = DLL.read_bytes()
    secs = sections(data)
    table = {}
    for r, n in names:
        for _, va, vs, raw in secs:
            if va <= r < va + vs:
                m = ACCESSOR.search(data, raw + r - va, raw + r - va + 0x90)
                if m:
                    ln = m.group(3) or m.group(4) or m.group(5)
                    table[n.split("::")[1]] = (struct.unpack("<I", m.group(1))[0],
                                               int.from_bytes(ln, "little", signed=len(ln) == 1))
    total = max(o + ln for o, ln in table.values())
    meta = METADATA.read_bytes()
    # the blob: where the whole decrypted range is UTF-8 and the literals have no control characters
    import numpy as np
    f = np.frombuffer(meta, dtype=np.uint8)
    idx = np.arange(len(f), dtype=np.int64)
    best = (0, 0)
    for k in range(256):
        d = f ^ ((idx - k) & 0xFF).astype(np.uint8) ^ 0xAA
        pr = (d >= 0x20) & (d < 0x7F)
        x = np.diff(np.concatenate([[0], pr.astype(np.int8), [0]]))
        s, e = np.where(x == 1)[0], np.where(x == -1)[0]
        i = (e - s).argmax()
        best = max(best, (int(e[i] - s[i]), int(s[i]), k))
    _, s, k = best
    # the key only depends on the position mod 256: every aligned window inside the text decrypts;
    # the blob is the lowest one (before it, the metadata is not text)
    blob = b""
    for b in range(s - (s - k) % 256, max(-1, s - total - 256), -256):
        d = np.frombuffer(meta[b:b + total], dtype=np.uint8) ^ (np.arange(total) & 0xFF).astype(np.uint8) ^ 0xAA
        if ((d < 0x20) & (d != 9) & (d != 10) & (d != 13)).any():
            if blob:
                break
            continue
        try:
            bytes(d).decode("utf-8")
            blob = bytes(d)
        except UnicodeDecodeError:
            if blob:
                break
    with STRINGS.open("w", encoding="utf-8") as out:
        for n, (o, ln) in sorted(table.items()):
            out.write(f"{n}\t{blob[o:o + ln].decode('utf-8', 'replace')!r}\n")
    print(f"-> {STRINGS} ({len(table)} literals, blob {total} bytes)")


def annotate(path: Path) -> None:
    """Replaces each obfuscated literal's accessor call by STR(<its text>) in a decompiled file."""
    if not STRINGS.exists():
        return
    lit = dict(line.rstrip("\n").split("\t", 1) for line in STRINGS.open(encoding="utf-8"))
    text = re.sub(r"<PrivateImplementationDetails>_\w+?__a__(\w+)\s*\(0\)",
                  lambda m: f"STR({lit[m.group(1)]})" if m.group(1) in lit else m.group(0),
                  path.read_text(encoding="utf-8", errors="replace"))
    path.write_text(text, encoding="utf-8")


def headless(*args: str) -> None:
    env = dict(os.environ, JAVA_HOME=JAVA)
    cmd = [str(GHIDRA / "support" / "analyzeHeadless.bat"), str(WORK), "GA", *args, "-scriptPath", str(HERE)]
    with open(WORK / "ghidra.log", "w", encoding="utf-8", errors="replace") as log:
        subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)


# Metadata usages (P1.13k): the decompiled code reads types through slots (`lRam00000001862770e0`,
# FUN_1805658a0(0x1862770e0) initialises them). In the file, a slot holds (kind << 29) | (index << 1) | 1;
# kind 1 = a type: index into Il2CppMetadataRegistration.types (Il2CppType*: data = the type definition
# index for a class / value type), whose name is in global-metadata.dat (v39 header: sections of
# (offset, size, count), strings = 2, typeDefinitions = 19, a definition starting with its name index).
BASE = 0x180000000


def _registration_types(data: bytes, secs) -> tuple[int, int]:
    """(types VA, count). Il2CppMetadataRegistration: ..., typesCount, types, methodSpecsCount, methodSpecs,
    fieldOffsetsCount, fieldOffsets, typeDefinitionsSizesCount (= fieldOffsetsCount), typeDefinitionsSizes."""
    import numpy as np
    for name, va, vsize, raw in secs:
        if name != b".rdata":
            continue
        n = min(vsize, len(data) - raw) // 8
        q = np.frombuffer(data, dtype=np.uint64, count=n, offset=raw)
        ptr = (q > BASE) & (q < BASE + len(data) * 4)
        cnt = (q > 5000) & (q < 1000000)
        k = np.nonzero(cnt[:-3] & ptr[1:-2] & (q[:-3] == q[2:-1]) & ptr[3:])[0]
        if len(k):
            i = int(k[0])
            return int(q[i - 3]), int(q[i - 4])
    raise SystemExit("Il2CppMetadataRegistration not found")


def usage(addrs: list[int]) -> None:
    data, md = DLL.read_bytes(), METADATA.read_bytes()
    secs = sections(data)

    def at(va: int, n: int = 8) -> bytes:
        for _, sva, vsize, raw in secs:
            if sva <= va - BASE < sva + vsize:
                o = raw + va - BASE - sva
                return data[o:o + n]
        raise KeyError(hex(va))

    def q(va: int) -> int:
        return struct.unpack("<Q", at(va))[0]

    types, count = _registration_types(data, secs)
    str_off = struct.unpack_from("<I", md, 8 + 12 * 2)[0]
    td_off, td_size, td_count = struct.unpack_from("<Iii", md, 8 + 12 * 19)

    def cstr(i: int) -> str:
        return md[str_off + i:md.index(b"\0", str_off + i)].decode("utf-8", "replace")

    for a in addrs:
        a = a if a >= BASE else a + BASE
        v = q(a)
        kind, idx = v >> 29, (v & 0x1FFFFFFF) >> 1
        name = "(not a type: method / field / string slot)"
        if kind == 1 and idx < count:
            p = q(types + idx * 8)
            d, bits = q(p), struct.unpack("<I", at(p + 8, 4))[0]
            if (bits >> 16) & 0xFF in (0x11, 0x12) and d < td_count:
                ni, nsi = struct.unpack_from("<II", md, td_off + d * (td_size // td_count))
                name = (cstr(nsi) + "." if cstr(nsi) else "") + cstr(ni)
            else:
                name = f"(type of kind {(bits >> 16) & 0xFF:#x})"
        print(hex(a), f"kind {kind} index {idx}", name)


def refs(addrs: list[int]) -> None:
    """Functions with a RIP-relative operand (rel32 ending the instruction) on each data address."""
    import numpy as np
    data = DLL.read_bytes()
    names = sorted(load_names().items())
    starts = [r for r, _ in names]
    targets = [a - BASE if a >= BASE else a for a in addrs]
    for name, va, vsize, raw in sections(data):
        if name != b"il2cpp":
            continue
        n = vsize - 8
        b = np.frombuffer(data, dtype=np.uint8, count=n + 4, offset=raw).astype(np.int64)
        rel = b[0:n] | b[1:n + 1] << 8 | b[2:n + 2] << 16 | b[3:n + 3] << 24
        rel = np.where(rel >= 2**31, rel - 2**32, rel)
        dest = np.arange(n, dtype=np.int64) + va + 4 + rel
        for t in targets:
            fns: dict[str, int] = {}
            for h in np.nonzero(dest == t)[0]:
                f = names[bisect.bisect_right(starts, va + int(h)) - 1][1]
                fns[f] = fns.get(f, 0) + 1
            print("==", hex(t + BASE), sum(fns.values()))
            for f, c in sorted(fns.items()):
                print("  ", f, c)


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        return
    cmd, args = sys.argv[1], sys.argv[2:]
    WORK.mkdir(parents=True, exist_ok=True)
    if cmd == "names":
        subprocess.run(["dotnet", "run", str(HERE / "methods.cs"), "--", "all", str(NAMES)], check=True)
        print(f"-> {NAMES} ({sum(1 for _ in NAMES.open(encoding='utf-8'))} methods)")
    elif cmd == "import":
        headless("-import", str(DLL), "-noanalysis", "-postScript", "Label.java", str(NAMES))
        print(f"-> {WORK / 'GA.rep'} (log: {WORK / 'ghidra.log'})")
    elif cmd == "find":
        for r, n in find(args[0]):
            print(hex(r), n)
    elif cmd == "xref":
        names = load_names()
        starts = sorted(names)
        targets = [int(a, 16) for a in args]
        for t, sites in callers(targets).items():
            print("==", hex(t), names.get(t, "?"))
            for s in sites:
                f = starts[bisect.bisect_right(starts, s) - 1]
                print(f"   {hex(s)}  in {hex(f)} {names[f]}")
    elif cmd == "decomp":
        out, rvas = Path(args[0]).resolve(), []
        for a in args[1:]:
            rvas += [hex(int(a, 16))] if re.fullmatch(r"0x[0-9a-fA-F]+", a) else [hex(r) for r, _ in find(a)]
        lst = WORK / "decomp_list.txt"
        lst.write_text("\n".join(rvas), encoding="utf-8")
        headless("-process", "GameAssembly.dll", "-noanalysis", "-readOnly", "-postScript", "Decomp.java",
                 str(out), "@" + str(lst))
        annotate(out)
        print(f"-> {out} ({len(rvas)} functions)")
    elif cmd == "strings":
        build_strings()
    elif cmd == "usage":
        usage([int(a, 16) for a in args])
    elif cmd == "refs":
        refs([int(a, 16) for a in args])
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
