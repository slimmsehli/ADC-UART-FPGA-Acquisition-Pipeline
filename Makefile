# =============================================================================
#  Usage:
#    make sim      — run simulation only (firmware must exist)
#    make wave     — open waveform in GTKWave
#    make clean    — remove all build outputs
# =============================================================================
CORE     = ./defines.v ./fifo.v ./uart.v ./cli_decoder.v ./uart_decoder_top.v ./adc.v ./top.v
SIMDIR   = ./simulation
TOP      = top
SIMBIN   = simv                  # compiled simulation binary
VCD      = $(SIMDIR)/waves.vcd
HEX_CONV = ./scripts/hex_convert.py

.PHONY: all firmware sim wave disasm clean

all: clean firmware comp run
sim: clean comp run

# --- Verilator simulation -----------------------------------------------

comp:
	verilator --binary -j 0 --trace -Wall --timescale 1ps/1ps \
	$(VTB) $(CORE) \
	--top $(TOP)  +define+old --Mdir $(SIMDIR) -o $(SIMBIN) \
	-Wno-UNDRIVEN -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-IMPLICIT -Wno-PINCONNECTEMPTY -Wno-DECLFILENAME -Wno-BLKSEQ \
	-Wno-UNUSEDPARAM -Wno-WIDTHTRUNC -Wno-VARHIDDEN -Wno-REDEFMACRO -Wno-PINMISSING -Wno-GENUNNAMED -Wno-CASEINCOMPLETE

run:
	./simulation/simv +MEM_FILE=$(HEX) +VCD_FILE=$(VCD)

wave: $(VCD)
	gtkwave $(VCD) &

clean:
	rm -f  $(SIMBIN) $(VCD)
	rm -rf $(SIMDIR)/*
	rm -f waves.vcd
	rm -rf *.hex

