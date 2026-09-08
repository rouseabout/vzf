all:
	@echo "Use 'make install-icepi-zero' or 'make install-icepi-zero' or 'make install-tangnano20k-gowin'"
	@echo "See README.md for full build instructions."

# ROMs

ROMDIR=roms

roms: src/rom.hex src/vzdos.hex

src/rom.hex: $(ROMDIR)/vtechv20.u12 #vtechv20.u09 vtechv20.u10
	cat $^ | xxd -p -c 1 > $@

src/vzdos.hex: $(ROMDIR)/vzdos.rom #dos_basic_v1.2_patched.rom
	cat $^ | xxd -p -c 1 > $@

src/rs232.hex: $(ROMDIR)/rs232_v16.ic2
	cat $^ | xxd -p -c 1 > $@

src/vzrtty.hex: $(ROMDIR)/vzrtty.ic3
	cat $^ | xxd -p -c 1 > $@

src/wordpro-d000.hex: $(ROMDIR)/wordpro.u3
	cat $^ | xxd -p -c 1 > $@

src/wordpro-e000.hex: $(ROMDIR)/wordpro.u4
	cat $^ | xxd -p -c 1 > $@

src/wordpro-f000.hex: $(ROMDIR)/wordpro.u5
	cat $^ | xxd -p -c 1 > $@

src/invaders-d000.hex: $(ROMDIR)/autostart\ invaders\ d000.bin
	cat "$^" | xxd -p -c 1 > $@

src/demo-4000.hex: $(ROMDIR)/DEMO_CARTRIDGE_8K.bin
	cat $^ | xxd -p -c 1 > $@

src/galaxon-4000.hex: $(ROMDIR)/Galaxon\ loads\ 4000\ cart\ area.vz
	dd if="$^" bs=1 skip=24 | xxd -p -c 1 > $@

src/maser-4000.hex: $(ROMDIR)/maser_rom
	cat $^ | xxd -p -c 1 > $@

# Firmware

CFLAGS=-mno-save-restore -march=rv32i -mabi=ilp32 -fno-builtin -nostartfiles -nostdlib -Os -static -Ifirmware -Ifirmware/ff
LIBS=/usr/lib/gcc/riscv64-unknown-elf/14.2.0/rv32i/ilp32/libgcc.a
CC=riscv64-unknown-elf-gcc
OBJCOPY=riscv64-unknown-elf-objcopy

OBJ_FILES=bsd_string.o DiskIO.o ff/ff.o inspect.o main.o string.o virtual.o
OBJS=$(addprefix firmware/, $(OBJ_FILES))

vzf-firmware.elf: firmware/startup.S $(OBJS)
	$(CC) $(CFLAGS) -Tfirmware/link_cmd.ld -o $@ $^ $(LIBS)

vzf-firmware.bin: vzf-firmware.elf
	$(OBJCOPY) -O binary $< $@

clean::
	rm -f $(OBJS) vzf-firmware.elf vzf-firmware.bin

# Gateware

SRC_COMMON=\
	src/hdmi/audio_clock_regeneration_packet.v \
	src/hdmi/audio_info_frame.v \
	src/hdmi/audio_sample_packet.v \
	src/hdmi/auxiliary_video_information_info_frame.v \
	src/hdmi/hdmi.v \
	src/hdmi/packet_picker.v \
	src/hdmi/packet_assembler.v \
	src/hdmi/source_product_description_info_frame.v \
	src/hdmi/tmds_channel.v \
	\
	src/io.v  \
	\
	src/mc6847.v \
	\
	src/membram2.v \
	src/memdp.v \
	src/memdp_32_8.v \
	src/memdp_32_8_flat.v \
	\
	src/picorv32.v \
	\
	src/top.v \
	\
	src/spiflash.v \
	\
	src/SPI_Master.v \
	\
	src/timer_22050.v \
	\
	src/tv80/tv80s.v \
	src/tv80/tv80_alu.v \
	src/tv80/tv80_reg.v \
	src/tv80/tv80_core.v \
	src/tv80/tv80_mcode.v \
	\
	src/uart_tx_V2.v \
	src/uart_rx.v \
	\
	src/usb_hid_host/usb_hid_host.v \
	src/usb_hid_host/usb_hid_host_rom.v \
	src/usb_hid_host/usb_hid_host_dual_rom.v \
	\
	src/vz.v

clean::
	rm -f yosys.log nextpnr.log

# Icepi Zero (yosys/nextpnr)
#
SRC_ICEPI_ZERO=\
	src/boards/icepi-zero/clock1.v \
	src/boards/icepi-zero/clock2.v \
	src/boards/icepi-zero/icepi_zero_top.v \
	src/hdmi/serializer_lattice.v \
	src/sdram_nestang_ecp5.v \
	$(SRC_COMMON)

src/boards/icepi-zero/clock1.v:
	ecppll -n clock1 --clkin_name clk -i 50 --clkout0_name clk_60 -o 60 --clkout1_name clk_60p --clkout1 60 --phase1 225 -f $@ --reset

src/boards/icepi-zero/clock2.v:
	ecppll -n clock2 --clkin_name clk_60 -i 60 --clkout0_name clk_pixel_x5 -o 142.5 --clkout1_name clk_pixel --clkout1 28.5 -f $@ --reset

vzf-icepi-zero-synth.json: $(SRC_ICEPI_ZERO)
	yosys -p 'read_verilog -Isrc/boards/icepi-zero -sv $^; synth_ecp5 -top icepi_zero_top -json $@' > yosys.log

vzf-icepi-zero.config: vzf-icepi-zero-synth.json src/boards/icepi-zero/icepi-zero.lpf
	nextpnr-ecp5 --25k --package CABGA256 --lpf src/boards/icepi-zero/icepi-zero.lpf --json $< --textcfg $@ --timing-allow-fail 2> nextpnr.log

vzf-icepi-zero.bit: vzf-icepi-zero.config
	ecppack --compress $< $@

debug-icepi-zero: vzf-icepi-zero.bit
	openFPGALoader -b icepi-zero $<

install-icepi-zero: vzf-firmware.bin vzf-icepi-zero.bit
	openFPGALoader -b icepi-zero --write-flash --offset 0x500000 vzf-firmware.bin
	#openFPGALoader -b icepi-zero --write-flash vzf-icepi-zero.bit

clean::
	rm -f vzf-icepi-zero-synth.json vzf-icepi-zero.config vzf-icepi-zero.bit

# Tang Nano 20K (yosys/nextpnr)

SRC_TANGNANO20K=\
	src/boards/tangnano20k/clocks.v \
	src/boards/tangnano20k/tangnano20k_top.v \
	src/hdmi/serializer_gowin.v \
	src/sdram_nestang.v \
	$(SRC_COMMON)

vzf-tangnano20k-synth.json: $(SRC_TANGNANO20K)
	yosys -p 'read_verilog -Isrc/boards/tangnano20k -sv $^; synth_gowin -top tangnano20k_top -json $@ -family gw2a' > yosys.log

vzf-tangnano20k.json: vzf-tangnano20k-synth.json src/boards/tangnano20k/tangnano20k.cst
	nextpnr-himbaechel --json $< --write $@ --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C --vopt cst=src/boards/tangnano20k/tangnano20k.cst 2> nextpnr.log

vzf-tangnano20k.fs: vzf-tangnano20k.json
	gowin_pack -c -d GW2A-18C --sspi_as_gpio --mspi_as_gpio -o $@ $^

debug-tangnano20k: vzf-tangnano20k.fs
	openFPGALoader -b tangnano20k $<

install-tangnano20k: vzf-firmware.bin vzf-tangnano20k.fs
	openFPGALoader -b tangnano20k --write-flash --offset 0x500000 vzf-firmware.bin
	openFPGALoader -b tangnano20k --write-flash $<

clean::
	rm -f vzf-tangnano20k-synth.json vzf-tangnano20k.json vzf-tangnano20k.fs

# Tang Nano 20K (gowin)

impl/pnr/vzf.fs: build.tcl
	rm -f $@
	./build.tcl | grep --color -E 'WARN|ERROR|$$'
	test -e $@

debug-tangnano20k-gowin: impl/pnr/vzf.fs
	openFPGALoader -b tangnano20k impl/pnr/vzf.fs

install-tangnano20k-gowin: vzf-firmware.bin impl/pnr/vzf.fs
	openFPGALoader -b tangnano20k --write-flash --offset 0x500000 vzf-firmware.bin
	openFPGALoader -b tangnano20k --write-flash impl/pnr/vzf.fs

clean::
	rm -rf impl/

## Simulation

src/firmware-0.bin: vzf-firmware.bin
	objcopy -I binary -O binary --interleave=4 --interleave-width=1 -b 0 $< $@
src/firmware-1.bin: vzf-firmware.bin
	objcopy -I binary -O binary --interleave=4 --interleave-width=1 -b 1 $< $@
src/firmware-2.bin: vzf-firmware.bin
	objcopy -I binary -O binary --interleave=4 --interleave-width=1 -b 2 $< $@
src/firmware-3.bin: vzf-firmware.bin
	objcopy -I binary -O binary --interleave=4 --interleave-width=1 -b 3 $< $@
%.hex: %.bin
	xxd -p -c 1 $< > $@
sim: sim.cpp src/firmware-0.hex src/firmware-1.hex src/firmware-2.hex src/firmware-3.hex
	verilator -Isrc -Isrc/boards/sim -Isrc/tv80 -Wno-fatal --trace -cc top.v --exe -CFLAGS "`sdl2-config --cflags`" -LDFLAGS "`sdl2-config --libs`" $<
	make -C obj_dir -j 8 -f Vtop.mk Vtop
	cd src && ../obj_dir/Vtop
clean::
	rm -f src/firmware-0.bin src/firmware-1.bin src/firmware-2.bin src/firmware-3.bin
	rm -f src/firmware-0.hex src/firmware-1.hex src/firmware-2.hex src/firmware-3.hex
	rm -rf obj_dir/
