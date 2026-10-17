/* fst2vcd: an FST waveform to VCD, with Verilator's bundled GTKWave FST reader.
   fst2vcd IN.fst OUT.vcd   (sim/Makefile: make tools/fst2vcd) */
#include <stdio.h>
#include "fstapi.h"

int main(int argc, char** argv) {
	if (argc != 3) { fprintf(stderr, "fst2vcd IN.fst OUT.vcd\n"); return 2; }
	void* ctx = fstReaderOpen(argv[1]);
	if (!ctx) { fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
	FILE* f = fopen(argv[2], "w");
	if (!f) { perror(argv[2]); return 1; }
	fstReaderProcessHier(ctx, f);
	fstReaderSetFacProcessMaskAll(ctx);
	fstReaderIterBlocks(ctx, NULL, NULL, f);
	fclose(f);
	fstReaderClose(ctx);
	return 0;
}
