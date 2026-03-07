# =============================================================================
#  Makefile — Build firmware + run PicoRV32 simulation
#
#  Requirements:
#    - riscv32-unknown-elf-gcc  (RISC-V toolchain)
#    - verilator                (Verilator simulator)
#    - gtkwave                  (optional, for waveforms)
#
#  Install toolchain (Ubuntu/Debian):
#    sudo apt install gcc-riscv64-unknown-elf
#    sudo apt install verilator gtkwave
#
#  Usage:
#    make          — build firmware + run simulation
#    make firmware — build firmware only
#    make sim      — run simulation only (firmware must exist)
#    make wave     — open waveform in GTKWave
#    make disasm   — disassemble firmware (useful for debugging)
#    make clean    — remove all build outputs
# =============================================================================
CC      = riscv32-unknown-elf-gcc
OBJCOPY = riscv32-unknown-elf-objcopy
OBJDUMP = riscv32-unknown-elf-objdump
CFLAGS  = -march=rv32i -mabi=ilp32 -nostdlib -O1 -Wall
SRCS     = ./firmware/soc/crt0.S ./firmware/soc/pwm_gpio.c
LDSCRIPT = ./firmware/soc/link.ld
ELF      = ./firmware/soc/firmware.elf
HEX_RAW  = ./firmware/soc/firmware_raw.hex   # objcopy byte-addressed output
HEX      = ./firmware/soc/firmware.hex        # word-addressed for $readmemh
CORE     = ./defines.v ./fifo.v ./uart.v ./cli_decoder.v ./uart_decoder_top.v ./adc.v ./top.v
VTB      =         # thin Verilog shim for Verilator
SIMDIR   = ./simulation
TOP      = top
SIMBIN   = simv                  # compiled simulation binary
VCD      = $(SIMDIR)/waves.vcd
HEX_CONV = ./scripts/hex_convert.py

.PHONY: all firmware sim wave disasm clean

all: clean firmware comp run
sim: clean comp run

# --- Firmware -----------------------------------------------------------

firmware: $(HEX)

$(ELF): $(SRCS) $(LDSCRIPT)
	$(CC) $(CFLAGS) -T $(LDSCRIPT) $(SRCS) -o $(ELF) -g

$(HEX_RAW): $(ELF)
	$(OBJCOPY) -O verilog $(ELF) $(HEX_RAW)

$(HEX): $(HEX_RAW)
	python3 $(HEX_CONV) $(HEX_RAW) $(HEX)

# --- Verilator simulation -----------------------------------------------
#
#  Verilator compiles RTL + a C++ testbench into a native binary.
#  Two-step process:
#    1. verilator  → generates C++ model in obj_dir/
#    2. make       → compiles that model + your C++ TB into $(SIMBIN)

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

disasm: $(ELF)
	$(OBJDUMP) -d $(ELF)

clean:
	rm -f  $(SIMBIN) $(VCD)
	rm -rf $(SIMDIR)/*
	rm -f waves.vcd
	rm -rf firmware/core/*.hex firmware/core/*.elf
	rm -rf firmware/soc/*.hex firmware/soc/*.elf


genfiles:
	rm -rf files
	mkdir files
	cp -r firmware/soc/* tb/tb_soc.v rtl/soc/* Makefile scripts/hex_convert.py files/

