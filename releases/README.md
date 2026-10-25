# Releases

## 7248_SMS_v1.07.img

The System Management Services diskette, version 1.07, for the RS/6000 43P
type 7248 (Models 100, 120, 132): a raw 1.44 MB FAT12 image (MD5
`77a5682c00c610c18341ea6dbb776a16`). Mount it as the OSD's `Floppy`:

- F4 at the POST icons (after the keyboard icon, before the speaker): the text SMS
  ("1. Manage Configuration ...").
- F1 at the icons, or a plain boot with the diskette in: the graphical SMS.

It is `sms107.dd` from IBM's firmware 1.11 package for the 7248 (`7248100.bin`,
mirrored at http://ps-2.kev009.com/rs6000-firmware/; the ZIP password is the one IBM
published, `**RS/6000**`). Use it rather than the 7020-40P's SMS diskettes: SMS 1.28
for the 40P calls ROM services the 7248's firmware (v1.12) does not have, and its
configuration menus stop in the firmware's debugger (ABEND 0001000A).

The same package's `fw-111.dd` is a flash update diskette (firmware 1.11, older than
the core's 1.12): don't boot it.
