derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

# The core PLL's outputs are unrelated clock domains: 0 unused (20 MHz),
# 1 the CPU and the machine, 2 the SDRAM, hps_io, the ROM upload and the
# picture (100 MHz). At 100 MHz Quartus merges counters 1 and 2 into one;
# a group is made only for each counter that exists. What crosses between
# them is safe by construction (DSPPC604_memcdc's toggles; the reset and the
# quasi-static options through two flip-flops), as in MacPPC7300.
set pll_groups {}
foreach i {0 1 2} {
	set c [get_clocks -nowarn "*|pll|pll_inst|altera_pll_i|*\[$i\].*|divclk"]
	if {[get_collection_size $c] > 0} { lappend pll_groups -group $c }
}
set_clock_groups -asynchronous {*}$pll_groups
