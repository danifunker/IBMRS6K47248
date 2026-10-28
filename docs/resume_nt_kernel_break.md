# Hand-off to the NT session: the "phantom trap" was NT's own debug-service trap; the CPU is fine

(Written 2026-10-28 evening by the CPU session that ran `docs/resume_cpu_trap_fable.md`. Paste everything
below the line into the NT session, or start a new one in `C:\Temp\mistercore\IBMRS6K47248`. It replaces
the CPU-side analysis in `docs/resume_cpu_trap_fable.md`, `docs/resume_cpu_trap_handoff.md` and the
"current blocker" section of `docs/resume_nt_setup.md`.)

---

## The result in one paragraph

The 21 program exceptions with SRR1's trap bit at 0x800A3B80 are **real `twi` instructions executed on
purpose**: NT's `DbgLoadImageSymbols`, called once per loaded module, ends in `DebugService`, which on
PowerPC is `twi 31,r0,23` (DEBUG_LOAD_SYMBOLS_BREAKPOINT). The CPU executed exactly the words that are in
memory; what was wrong was the map we compared them with. The kernel that runs is **`ntkrnlmp.exe`**
(the multiprocessor kernel, from `\ppc` on the CD), **loaded at 0x80049000**, not `ntoskrnl.exe` at its
image base 0x80010000. With that map every retired word of the board's 64-entry retire ring matches the
file, run after run, with the one page-aligned delta 0x39000. **There is no CPU bug here**; nothing in
`rtl/DSPPC604/` was changed. The real stop is what comes after the 21 traps: a `twi 31,r0,22`
(a `DbgBreakPoint`-class trap) at 0x800A3B58, after which the kernel talks KD on COM1 forever. That is
almost certainly a **bugcheck** (KeBugCheckEx breaks into the debugger it initialises at crash time)
whose code we have not captured yet.

## The evidence

1. **The ring capture** (`Y:\ibmrs6k-bench-logs\nt_c1ring_20261028.raw`, the "IL=" block): the debug
   build now dumps, at the first vector-0x700 retire after the port-92 switch, the last 64 instructions
   retired as `pppppppp:iiiiiiii` (PC and the word the CPU executed), oldest first after the first
   printed entry (which is the newest, the vector's own `00000700:7CB243A6`). The last entries:

   ```
   800A3CA0:93A1FFF4 800A3CA4:93C1FFF8 800A3CA8:607E0000 800A3CAC:60830000 800A3CB0:93E1FFFC
   800A3CB4:9421FFA0 800A3CB8:7FA802A6 800A3CBC:3BE10038 800A3CC0:907F0000 800A3CC4:90BF0004
   800A3CC8:48008209 (bl 800ABED0 = RtlImageNtHeader: it checks "MZ" and "PE") ... 800B8224:83C1FFF8
   800A3CCC:60000000 800A3CD0:28830000 800A3CD4:41860018 800A3CD8:81630058 (CheckSum)
   800A3CDC:917F0008 800A3CE0:80630050 (SizeOfImage) 800A3CE4:907F000C 800A3CE8:48000010
   800A3CF8:63C30000 800A3CFC:63E40000 800A3D00:4BFFFE81 (bl -0x180 -> 800A3B80)
   ```

   Not one of these is the word `ntoskrnl.exe` has at that address. All of them are `ntkrnlmp.exe`'s
   words at address minus 0x39000 (checked with a script over every run of consecutive PCs in the ring;
   `ntoskrnl.exe` matches only partially and with inconsistent deltas: a different build of the same
   code).
2. **`ntkrnlmp.exe` at 0x8006AB50-0x8006AB98** (memory 0x800A3B50-0x800A3B98) is the row of debug-service
   traps: `0fe00016` (twi 31,r0,22) at AB50, AB58, AB60; `0fe00015` (21) at AB78; **`0fe00017` (23) at
   AB80**; `0fe00018` (24) at AB88; `0fe00014` (20) at AB98. So SRR0 0x800A3B80 is `twi 31,r0,23`, and
   LR 0x800A3D04 is the return address of the `bl` at 3D00. Both are what a correct CPU produces.
3. The kernel files: `ntoskrnl.exe` on the CD is byte-identical to `Y:\ibmrs6k-bench-logs\NTOSKRNL.ppc`
   (MD5 117f4579...), so the mistake was the file, not the copy. Both kernels are now on Y:
   (`ntoskrnl_iso.exe`, `ntkrnlmp_iso.exe`). `txtsetup.sif` on the CD: `Multiprocessor = ntkrnlmp.exe`,
   `Uniprocessor = ntoskrnl.exe`, and **`OsLoadOptions = "/nodebug"`**.
4. The bench test written for the CPU hunt (`sim/tests/le_fold.rom`, `scratch/work/run_fold.sh`): the
   `ntoskrnl.exe` words 0x800A3A80-0x800A3D60 run little-endian at their own addresses (IR/DR on through
   BATs, both caches on, MSR 00013031), 4096 iterations of both entry paths: "FOLD OK", no exception.
   Consistent with the result; keep it as the LE/BAT/fold regression it is.

## What this means for NT setup

- **The 21 traps are normal** (21 modules: the kernel, the HAL, the boot drivers). Any plan that treats
  them as a fault is void.
- **The real stop is the trap at 0x800A3B58** (`twi 31,r0,22`, ntkrnlmp 0x8006AB58): with `/nodebug`
  a plain breakpoint has no debugger to go to, so the way the kernel reaches it and then sends KD
  state-change packets on COM1 is KeBugCheckEx: it initialises KD at crash time and breaks. The
  bugcheck code is unknown. On a real machine the HAL would also have drawn the blue stop screen through
  its own display code (the screen stayed at "Windows NT Setup": the HAL's text-mode re-init on our S3
  may be a separate issue).
- **Why the MP kernel?** setupldr picks `ntkrnlmp.exe` when the ARC configuration tree holds more than
  one processor node. The 7248 is a uniprocessor; the tree ARC builds from our firmware says otherwise,
  or setupldr's PPC rule differs. Worth checking in ARC (its "Display hardware configuration" if it has
  one) and in setupldr's code. The MP kernel on one CPU normally runs, but it is one more difference
  from a real 7248.
- The HAL loaded is presumably `halcaro.dll` (Carolina = the 7248/7247 planar family); the other HALs
  on the CD are haleagle, halfire, halppc, halps, halvict, halwood.

## Next captures, cheapest first (all with the ring build already on the board)

1. **The bugcheck code.** Change the logger's trigger in `IBMRS6K7248.sv` (~line 730, `isi_go`) from
   "the first vector-0x700 retire after the switch" to "the first 0x700 retire whose previous retired PC
   is 0x800A3B58" (the `pc_prev` register exists, ~line 600), rebuild (~25 min), boot NT setup, and read
   the ring and the 40 GPR writes: KeBugCheckEx's arguments are in r3-r7 at the `bl` to the breakpoint
   routine a few instructions earlier, and the ring shows the call path into it. Alternatively decode the
   KD state-change packet already captured (the `30 30 30 30` leader): it carries the exception record
   and, in NT 4's PPC packet, a context block with the GPRs.
2. **The loaded-module list.** The 21 `DbgLoadImageSymbols` calls each pass the module name in r3
   (a STRING at `ori r3,r30,0`, 3CF8): a ring dump at each (or the 40-GPR dump) would list what was
   loaded, i.e. which driver is the last before the crash.
3. **The MP kernel question**: a `strings`-level look at setupldr for how it counts processors, or
   simply what ARC shows.

## The board (.92) as left

- `/media/fat/_Unstable/IBMRS6K7248.rbf` = the ring build (`scratch/work/IBMRS6K7248_ring.rbf`,
  = the previous debug build + the ring dump at the first 0x700; CPU slack -2.70 ns). The previous
  core is `/media/fat/_Unstable/IBMRS6K7248_pgm_prev.rbf.bak`.
- NT setup is sitting at its screen with the kernel in the KD loop (the capture above). Boot it again
  per `docs/resume_nt_setup.md` ("The board" section); `scratch/work/ntboot92.sh` (run through
  `r92.sh`) starts a fresh `/tmp/c1ring.raw` recording and loads `/tmp/ntarc.mgl`; the key sequence
  (Enter, Enter, Down, Enter, `cd:` `\` `ppc` `\` `setupldr`, Enter, 15-40 s between keys) took
  6 minutes to the kernel's trap today. `scratch/work/waitring.sh` waits on the board for the `IL=`
  dump and prints it; `scratch/work/snap92.sh` takes `RAWF=/tmp/c1ring.raw` for its tail.
- `/tmp/board.lock` was released by this session.

## Files touched by the CPU session

- `IBMRS6K7248.sv`: one line, the ring dumps at `isi_go` too.
- `sim/tests/le_fold_be.S`, `le_fold_le.S`, `le_fold_kernel.inc`, the `le_fold.rom` rule in
  `sim/tests/Makefile` (clang-18 for both endiannesses; the LE blob is stored with each doubleword
  reversed, as ARC lays memory out; the handler at 0x700 shows SRR0/SRR1 as LR on the bench's io trace).
- `scratch/work/run_fold.sh`, `ntboot92.sh`, `waitring.sh`, `lock92.sh`, `iso92.sh`, `txt92.sh`.
- `docs/bringup_log.md`: the finding. `docs/resume_cpu_trap_fable.md` and
  `docs/resume_cpu_trap_handoff.md`: marked superseded by this document.
