# What this core needs from Main_MiSTer

Most of the core runs on a stock Main. Its image entries are `SC` rows, which stock Main remembers
and mounts again at every core load. The NVRAM file is one of those mounts. Only the Ethernet bridge
needs code in Main.

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
