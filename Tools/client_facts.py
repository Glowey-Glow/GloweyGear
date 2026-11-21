"""Reads two sets of facts out of the installed game, for Stats.lua and its tests.

    python -I Tools/client_facts.py

Writes Tools/tests/fixtures/client_stat_keys.txt and client_combat_ratings.txt:

  * The names C_Item.GetItemStats can answer with. Its table is keyed by the names of the game's
    own global strings; the names are read from the client's GlobalStrings database (file data ID
    1394440): every name starting ITEM_MOD_ or EMPTY_SOCKET_, and RESISTANCE0_NAME to 6. Beside each
    ITEM_MOD_ name goes the English text stored next to it, which is what says what the stat is.
    One of the database's ten blocks is encrypted in the install and is skipped (it reads as
    zeros): a name stored only there would be missing, which is why /gear debug still reports any
    name met in play that Stats.lua has no line for.
  * The combat ratings table (file data ID 1391669, "gametables/combatratings.txt" on the mainline
    family): for each column, the set of values over all level rows. On this client every column
    holds one value at every level.

It needs the owner's game-file reader (E:\\daylight\\GloweyHUD\\tools\\mockup\\casc.py), which
opens the game's local data read-only. Nothing is sent anywhere. Not part of the zip players
download.
"""
import os
import re
import struct
import sys
import zlib

READER = r"E:\daylight\GloweyHUD\tools\mockup"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "tests", "fixtures")
GLOBAL_STRINGS, COMBAT_RATINGS = 1394440, 1391669


def unpack(blob):
    """A BLTE container's blocks joined; an encrypted block becomes zeros of its size."""
    if blob[:4] != b"BLTE":
        raise ValueError("not a BLTE container")
    header = struct.unpack_from(">I", blob, 4)[0]
    if header == 0:
        return blob[9:] if blob[8:9] == b"N" else zlib.decompress(blob[9:]), 0
    count = struct.unpack_from(">I", blob, 8)[0] & 0xFFFFFF
    at, parts, skipped = header, [], 0
    for i in range(count):
        packed, plain = struct.unpack_from(">II", blob, 12 + i * 24)
        mode, body = blob[at:at + 1], blob[at + 1:at + packed]
        at += packed
        if mode == b"N":
            parts.append(body)
        elif mode == b"Z":
            parts.append(zlib.decompress(body))
        else:
            skipped += 1
            parts.append(b"\0" * plain)
    return b"".join(parts), skipped


def main():
    sys.path.insert(0, READER)
    import casc  # noqa: E402  (the owner's reader)

    store = casc.Casc().load()

    def read(file_id):
        archive, offset, size = store.idx[store.enc[store.root[file_id]][:9]]
        with open(os.path.join(casc.DATA, "data", "data.%03d" % archive), "rb") as handle:
            handle.seek(offset + 30)
            return unpack(handle.read(size - 30))

    os.makedirs(OUT, exist_ok=True)

    data, skipped = read(GLOBAL_STRINGS)
    pieces = data.split(b"\0")
    wanted = re.compile(rb"^(ITEM_MOD_[A-Z0-9_]+|EMPTY_SOCKET_[A-Z0-9_]+|RESISTANCE[0-9]_NAME)$")
    names = {}
    for i, piece in enumerate(pieces):
        if wanted.match(piece):
            text = pieces[i + 1].decode("utf-8", "replace") if i + 1 < len(pieces) else ""
            # (The text stored after a name is its own when it is a sentence, not another name.)
            if re.match(r"^[A-Z0-9_]+$", text):
                text = ""
            names.setdefault(piece.decode(), text[:120])
    with open(os.path.join(OUT, "client_stat_keys.txt"), "w", encoding="utf-8", newline="\n") as out:
        out.write("# Names the stat call can answer with, from the client's GlobalStrings database "
                  "(Tools/client_facts.py).\n# name<TAB>the English text stored beside it, when it is a sentence\n")
        for name in sorted(names):
            out.write("%s\t%s\n" % (name, names[name]))
    print("%d names (%d encrypted block(s) skipped)" % (len(names), skipped))

    table, _ = read(COMBAT_RATINGS)
    rows = [line.rstrip("\r").split("\t") for line in table.decode("latin-1").split("\n") if line.strip()]
    head, body = rows[0], rows[1:]
    with open(os.path.join(OUT, "client_combat_ratings.txt"), "w", encoding="utf-8", newline="\n") as out:
        out.write("# The client's combat ratings table (Tools/client_facts.py): %d level rows, levels %s to %s.\n"
                  "# column<TAB>every value the column holds over all levels\n" % (len(body), body[0][0], body[-1][0]))
        for column in range(1, len(head)):
            values = sorted({row[column] for row in body if len(row) > column}, key=float)
            out.write("%s\t%s\n" % (head[column], " ".join(values)))
    print("%d rating columns over %d levels" % (len(head) - 1, len(body)))


if __name__ == "__main__":
    main()
