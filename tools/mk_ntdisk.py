#!/usr/bin/env python3
# Build a blank SCSI disk image ready for Windows NT on the 7248 core: ARC on the disk itself, so the
# machine boots ARC without the diskette, and an ARC system partition for NT's OS loader.
#
#   python3 mk_ntdisk.py ARC_DISKETTE.img OUT.img [SIZE_MB]       (SIZE_MB default 2048)
#
# ARC_DISKETTE.img is IBM's ARC boot diskette for PReP (rs6karc151.img, ARC 2.11 EC): its PReP boot
# partition (type 41) is copied as it is. The image built:
#   partition 1  type 41, active   sectors 32-10239 (5 MB)   ARC's boot image (the 7248's firmware boots it)
#   partition 2  type 04 (FAT16)   sectors 10240-20479 (5 MB) empty, formatted: the system partition
#   the rest      unpartitioned:   NT setup makes and formats its partition there (NTFS or FAT)
# This is the layout ARC's own Simple Setup makes, with a small system partition instead of one FAT
# partition over the whole disk. Python 3 standard library only; OUT.img is written sparse.
import struct
import sys

SECTOR = 512
ARC_START, ARC_SIZE = 32, 10208          # as ARC's Simple Setup places it
FAT_START, FAT_SIZE = 10240, 10240       # 5 MB at 5 MB


def chs(lba, heads=64, spt=32):
    """CHS bytes for an MBR entry (64 heads x 32 sectors: 1 MB cylinders); past 1023 cylinders, the maximum."""
    c, r = divmod(lba, heads * spt)
    h, s = divmod(r, spt)
    if c > 1023:
        c, h, s = 1023, heads - 1, spt - 1
    return bytes([h, ((s + 1) & 0x3F) | ((c >> 2) & 0xC0), c & 0xFF])


def mbr_entry(active, ptype, start, count, prep=False):
    if prep:                              # the PReP boot partition as IBM's diskettes and AIX write it
        first, last = b'\xff\xff\xff', b'\xff\xff\xff'
    else:
        first, last = chs(start), chs(start + count - 1)
    return bytes([0x80 if active else 0x00]) + first + bytes([ptype]) + last + struct.pack('<II', start, count)


def fat16(total, hidden, label=b'SYSTEM     '):
    """A formatted FAT16 volume of `total` sectors: one sector a cluster, two FATs, 512 root entries."""
    root_secs = 512 * 32 // SECTOR
    fat_secs = 1
    while True:                           # the FAT must cover the clusters it leaves
        clusters = total - 1 - root_secs - 2 * fat_secs
        need = ((clusters + 2) * 2 + SECTOR - 1) // SECTOR
        if need <= fat_secs:
            break
        fat_secs = need
    assert 4085 <= clusters < 65525, clusters
    bs = bytearray(SECTOR)
    bs[0:3] = b'\xEB\x3C\x90'
    bs[3:11] = b'MSDOS5.0'
    struct.pack_into('<HBHBHHBHHHII', bs, 11, SECTOR, 1, 1, 2, 512, total if total < 65536 else 0, 0xF8,
                     fat_secs, 32, 64, hidden, total if total >= 65536 else 0)
    struct.pack_into('<BBBI', bs, 36, 0x80, 0, 0x29, 0x7248A0C0)
    bs[43:54] = label
    bs[54:62] = b'FAT16   '
    bs[510:512] = b'\x55\xAA'
    fat = bytearray(fat_secs * SECTOR)
    fat[0:4] = b'\xF8\xFF\xFF\xFF'
    root = bytearray(root_secs * SECTOR)
    root[0:11] = label                    # the volume label entry
    root[11] = 0x08
    return bytes(bs) + bytes(fat) * 2 + bytes(root)


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__ or 'usage: mk_ntdisk.py ARC_DISKETTE.img OUT.img [SIZE_MB]')
    arc_path, out_path = sys.argv[1], sys.argv[2]
    size_mb = int(sys.argv[3]) if len(sys.argv) == 4 else 2048
    total = size_mb * 2048
    if total < FAT_START + FAT_SIZE + 2048:
        sys.exit('the disk must be larger than 11 MB')

    d = open(arc_path, 'rb').read()
    if d[510:512] != b'\x55\xAA':
        sys.exit('%s: no partition table' % arc_path)
    for i in range(4):
        e = d[446 + 16 * i:462 + 16 * i]
        if e[4] == 0x41:
            start, count = struct.unpack('<II', e[8:16])
            break
    else:
        sys.exit('%s: no PReP boot partition (type 41)' % arc_path)
    boot = d[start * SECTOR:(start + count) * SECTOR]
    if count > ARC_SIZE or len(boot) != count * SECTOR:
        sys.exit('%s: the boot partition (%d sectors) does not fit or is cut short' % (arc_path, count))

    mbr = bytearray(SECTOR)
    mbr[446:462] = mbr_entry(True, 0x41, ARC_START, ARC_SIZE, prep=True)
    mbr[462:478] = mbr_entry(False, 0x04, FAT_START, FAT_SIZE)
    mbr[510:512] = b'\x55\xAA'

    with open(out_path, 'wb') as f:
        f.truncate(total * SECTOR)        # sparse: only what follows takes space
        f.seek(0)
        f.write(mbr)
        f.seek(ARC_START * SECTOR)
        f.write(boot)
        f.seek(FAT_START * SECTOR)
        f.write(fat16(FAT_SIZE, FAT_START))
    print('%s: %d MB; ARC boot partition (%d sectors of ARC, from %s), 5 MB FAT16 system partition, %d MB free'
          % (out_path, size_mb, count, arc_path, (total - FAT_START - FAT_SIZE) // 2048))


if __name__ == '__main__':
    main()
