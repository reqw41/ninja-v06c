#!/usr/bin/env python3
"""Extract Ninja's RAM payload and build verified SkoolKit output."""

from contextlib import redirect_stdout
from functools import reduce
from operator import xor
from pathlib import Path
from shutil import copytree
from tempfile import TemporaryDirectory

from skoolkit import SkoolKitError, skool2asm, skool2bin, skool2html, sna2skool
from skoolkit.tape import parse_tap

ROOT = Path(__file__).resolve().parents[1]
TAPE = ROOT / "orig" / "emu-land-zip" / "Ninja (1987)(Entertainment USA).tap"
CONTROL = ROOT / "src" / "ninja.ctl"
OUTPUT = ROOT / "build" / "zx"
ORIGIN = 0x4000
PAYLOAD_SIZE = 0xBF80


def extract_ram():
    tape = parse_tap(TAPE.read_bytes())
    if tape.warnings:
        raise ValueError("; ".join(tape.warnings))
    blocks = tape.blocks
    if len(blocks) != 5:
        raise ValueError(f"Expected 5 TAP blocks, found {len(blocks)}")
    for block in blocks:
        if len(block.data) < 2 or reduce(xor, block.data, 0):
            raise ValueError(f"Invalid TAP checksum or length in block {block.number}")
    final = blocks[-1].data
    if final[0] != 0xFF or len(final) != PAYLOAD_SIZE + 2:
        raise ValueError(f"Expected a {PAYLOAD_SIZE}-byte data payload in TAP block 5")
    return final[1:-1]


def build(stage, payload):
    binary = stage / "ram4000.bin"
    listing = stage / "ninja.skool"
    rebuilt = stage / "rebuilt.bin"
    binary.write_bytes(payload)

    with listing.open("w", encoding="utf-8") as stream, redirect_stdout(stream):
        sna2skool.main(["-H", "-o", str(ORIGIN), "-c", str(CONTROL), str(binary)])
    skool2bin.main(["-i", str(listing), str(rebuilt)])
    if rebuilt.read_bytes() != payload:
        raise ValueError("Rebuilt bytes differ from the TAP payload")
    rebuilt.unlink()

    with (stage / "ninja.asm").open("w", encoding="utf-8") as stream, redirect_stdout(stream):
        skool2asm.main(["-H", str(listing)])
    skool2html.main(["-q", "-d", str(stage / "html"), str(listing)])


def main():
    try:
        payload = extract_ram()
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        with TemporaryDirectory(dir=OUTPUT.parent) as tmp:
            stage = Path(tmp)
            build(stage, payload)
            copytree(stage, OUTPUT, dirs_exist_ok=True)
    except (OSError, SkoolKitError, ValueError) as exc:
        raise SystemExit(str(exc)) from exc
    print(f"Verified all {len(payload)} bytes. Output: {OUTPUT}")


if __name__ == "__main__":
    main()
