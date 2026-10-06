"""Lookup of Dofus i18n texts: python tools/i18n_lookup.py 554207 535632 ..."""
import struct, sys
from pathlib import Path

BIN = Path(__file__).resolve().parent.parent / "game/content/Content/I18n/fr.bin"
_b = BIN.read_bytes()
_n = _b[0]
_count = struct.unpack_from("<i", _b, 1 + _n)[0]
_tab = 1 + _n + 4
_idx = {}
for i in range(_count):
    k, off = struct.unpack_from("<ii", _b, _tab + i * 8)
    _idx[k] = off


def text(i: int) -> str:
    off = _idx.get(int(i))
    if off is None:
        return ""
    ln = shift = 0
    while True:
        c = _b[off]; off += 1
        ln |= (c & 0x7F) << shift; shift += 7
        if c < 0x80:
            break
    return _b[off:off + ln].decode("utf-8")


if __name__ == "__main__":
    for a in sys.argv[1:]:
        print(a, text(a))
