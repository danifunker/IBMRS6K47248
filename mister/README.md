# What this core needs from Main_MiSTer

Most of the core runs on a stock Main. Its image entries are `SC` rows, which stock Main remembers
and mounts again at every core load. The NVRAM file is one of those mounts.

**Main_MiSTer branch `ibmrs6k`** (cut from master `8328d9f`, commit `4043afc`) has this core's own
`support/ibmrs6k/`, its hooks beside hp9k's in `user_io.cpp` and `support.h`:

- the Ethernet bridge below (`ibmrs6k_enet`);
- the CD-ROM slot (SC2): ISO, CUE/BIN and CHD, with the track table and CD-audio windows the SCSI
  target reads (`ibmrs6k_cdrom`, a copy of `support/hp9k`'s CD layer). With a stock Main the CD is
  one data track and only flat images work;
- the hard-disk write buffer for SC0 and SC1 (`ibmrs6k_disk`, a copy of `support/hp9k`'s).

Each hook is gated on the RBF name `IBMRS6K7248`. The branch builds clean with the ARM toolchain
(WSL: `/opt/gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf/bin`, `make -j`). On .92
(2026-10-25): the bridge writes the PROM MAC (`08:00:5A` + eth0's last three bytes, here
`08:00:5A:61:56:F1`), the firmware's SMS shows it as the integrated Ethernet's hardware address,
and SMS's ping (Utilities, Remote Initial Program Load Setup) from 192.168.99.243 to a PC on the
LAN succeeds; the AIX 4.3.3 install CD (ISO) boots from the CD slot to AIX's console prompt. Not
yet run: CUE/BIN and CHD images, CD audio, the write buffer under heavy writes. The files here are
the bridge as first written; the branch is the reference.

## The Ethernet bridge (`Main_MiSTer/support/ibmrs6k/`)

The planar's Am79C970 PCnet is modelled in the FPGA (`rtl/machine/IBMRS6K7248_pcnet.sv`). Main is
only the wire. Frames cross the shared DDR3 mailbox at ARM physical `1FF0_0000`, the same layout the
HP 9000, Sun and NeXT cores use (`rtl/machine/IBMRS6K7248_enetbox.sv` describes it). This core's magic
is `RS6ETH01`, with 16 RX slots.

`ibmrs6k_enet.cpp` is a copy of `support/hp9k/hp9k_enet.cpp` with three changes:

- the magic;
- the OSD bits (`[8:6]`, when the RBF is `IBMRS6K7248`);
- one addition: at every core start-up it writes the MAC for the PCnet's address PROM at mailbox
  `+0x38`. That MAC is IBM's OUI (`08:00:5A`) plus the last three bytes of the board's `eth0`, so it
  is stable per board and differs between boards. Without it, the core uses `08:00:5A:4D:52:01`.

To merge it into Main, copy the folder into `support/` and add four lines:

```cpp
// support.h, beside the hp9k bridge's include
#include "support/ibmrs6k/ibmrs6k_enet.h"

// user_io.cpp, where the other bridges stop (user_io_rbf... before a new core):
	ibmrs6k_enet_stop();

// user_io.cpp, where they start (beside "if (is_hp9k_family()) hp9k_enet_start();"):
				ibmrs6k_enet_start();      // returns at once unless the core is IBMRS6K7248

// user_io.cpp, where they poll (beside "hp9k_enet_poll();"):
	ibmrs6k_enet_poll();
```

The Makefile already compiles `support/*/*.cpp`. The bridge has been syntax-checked against Main
`e698ccd`. It hasn't been run on a board yet.

## The OSD's Network interface row

`O[8:6],Network interface,eth0,None,eth1,macvlan,tap0`: Main's bridge reads it directly, so a change
takes effect at once. The core only uses it to drop frames while it is `None`.
