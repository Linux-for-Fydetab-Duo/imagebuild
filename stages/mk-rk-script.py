#!/usr/bin/env python3
"""Build a u-boot legacy script image in Rockchip's dialect.

The Fydetab Duo's u-boot (rockchip-linux 2017.09, commit 63c55618) patches the
`source` command's payload seek:

    cmd/source.c:   while (*data++ != IMAGE_PARAM_INVAL);
    include/image.h:#define IMAGE_PARAM_INVAL 0xffffffff

Upstream u-boot terminates the multi-image size table with a ZERO word, and
upstream mkimage writes [len][0x00000000][text]. On this device that terminator
is never found, the data pointer runs past the script, and u-boot executes
whatever follows in RAM -- seen on serial as a huge garbage `Unknown command`
followed by "SCRIPT FAILED: continuing...", after which the device silently
boots the eMMC instead.

So the size table here is [len][0xffffffff], matching the vendor SDK's mkimage
output byte for byte (verified against the last known-good boot.scr.uimg).
`source()` checks magic, header CRC, data CRC and image type -- not arch -- but
IH_ARCH_ARM is used to match the known-good image anyway.

Usage: mk-rk-script.py <boot.cmd> <boot.scr> [name]
"""

import binascii
import os
import struct
import sys

IH_MAGIC = 0x27051956
IH_OS_LINUX = 5
IH_ARCH_ARM = 2
IH_TYPE_SCRIPT = 6
IH_COMP_NONE = 0
IMAGE_PARAM_INVAL = 0xFFFFFFFF


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    name = (sys.argv[3] if len(sys.argv) > 3 else "boot script").encode()[:31]

    # Strip comment and blank lines: keep the payload identical in character to
    # the vendor-produced script (which contains none), rather than betting on
    # 2017-era hush comment handling from a device round-trip away.
    lines = open(src, "rb").read().splitlines()
    text = b"\n".join(l for l in lines if l.strip() and not l.lstrip().startswith(b"#")) + b"\n"
    data = struct.pack(">II", len(text), IMAGE_PARAM_INVAL) + text

    # Reproducible: timestamp from the source file, not the build moment.
    mtime = int(os.stat(src).st_mtime)
    dcrc = binascii.crc32(data) & 0xFFFFFFFF

    def header(hcrc: int) -> bytes:
        return struct.pack(
            ">7I4B32s",
            IH_MAGIC, hcrc, mtime, len(data), 0, 0, dcrc,
            IH_OS_LINUX, IH_ARCH_ARM, IH_TYPE_SCRIPT, IH_COMP_NONE,
            name.ljust(32, b"\0"),
        )

    hcrc = binascii.crc32(header(0)) & 0xFFFFFFFF
    with open(dst, "wb") as f:
        f.write(header(hcrc) + data)
    print(f"    {os.path.basename(dst)}: {len(data)} data bytes, "
          f"dcrc {dcrc:#010x}, rockchip terminator")


if __name__ == "__main__":
    main()
