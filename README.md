# VZF

This is a recreation of the VZ-200/VZ-300/LASER 210/LASER 310 color personal computer using a field-programmable gate array (FPGA) and modern peripherals.
Currently the [Icepi Zero](https://github.com/cheyao/icepi-zero) and [Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html) development boards are supported.

Capabilities:

* Cycle accurate Z80 CPU
* 16 KiB ROM, extensions ROMs, and 2/16/32/64 KiB RAM (configurable at synthesis time)
* MC6847 with HDMI output; PAL and NTSC vertical sync rates supported
* USB Keyboard
* USB Gamepad/Joystick
* Floppy Disk Drive emulator; supports .DSK images and .VZ files read from SD card
* Cassette Deck emulator; supports .WAV files
* Speaker
* Printer; text is sent down the the USB programming cable
* RS-232 interface

## Operating instructions

The FPGA hosts two computers, VZ and I/O.
VZ is self explanatory.
I/O emulates the floppy disk drive and cassette deck.
Applying power to the FPGA causes both computers to start.

### Keyboard

Use the USB keyboard like you would the traditional VZ keyboard. There are some special keyboard keys:

|Key |Operation |
|---|---|
|F1 |Select VZ console |
|F2 |Select I/O console |
|F9 |Toggle between VZ-200/VZ-300/TURBO clock speed |
|F10 |Toggle between PAL/NTSC mode |
|F11 |Toggle hear cassette audio |
|CTRL+F12 |Reset VZ |
|ALT+F12 |Reset I/O |

TURBO clock speed is 28.5MHz.
Some programs will behave incorrectly with TURBO clock speed.
It is not possible to load cassette tapes with TURBO clock speed.

### Mounting floppy disks

To mount a floppy disk from SD card, press F2 to select I/O, type `MOUNT FILENAME.EXT`, and then press F1 to return to the VZ.
Use ordinary DOS commands or programs to interact with the disk.
Different media can be mounted including .DSK files (of either 98560 and 99184 byte size), .VZ program files (BASIC and assembly) and data files.

Changes made to the floppy disk are not automatically saved to the SD card.
If you make changes to a floppy disk, and wish to save them, switch back to the I/O console and type `SAVE NEWFILE.DSK`.

### Playing cassette tapes

To play a cassette tape type `PLAY FILENAME.WAV`.
WAV files must be 8-bit PCM, mono, 22050 Hz.

### I/O commands

The following commands are implemented by I/O.
Some commands take arguments.

| Command | Description |
|---|---|
|`CD dirname`|Change directory. |
|`CLS` |Clear screen. |
|`DIR [-L]`|Directory listing. Use -L option to list file sizes and attributes. |
|`DRIVE n`|Select floppy drive, where n is 1 or 2. Future `MOUNT`, `SAVE` and `UNMOUNT` commands will affect the selected floppy drive. |
|`ERA filename` |Erase filename.  |
|`HEXDUMP filename` |Dump contents of file to screen.  |
|`INSPECT filename` |Inspect contents of a floppy disk image. |
|`MOUNT filename` |Mount a floppy disk image (.DSK), program (.VZ) or other data file into the selected floppy drive.  |
|`PLAY filename` |Play .WAV file into cassette input port.  |
|`PWD` |Display current directory. |
|`SAVE filename` |Save contents of the selected floppy drive to filename. |
|`STATUS` |Display floppy drive status. |
|`UNMOUNT` |Unmount the active floppy drive. |

### Printing

Any text sent to the VZ printer port is redirected to the UART attached to the the USB programming cable.
The UART configuration is 115200 baud 8-N-1.

To receive output on Linux, first identify the device file name of the USB programming port. On my computer this always appears as /dev/ttyUSB1. Then type.

```
stty -F /dev/ttyUSB1 115200 cs8
cat /dev/ttyUSB1
```

Then on the VZ, type `LPRINT "HELLO WORLD"`, `LLIST`, etc.

### SD card compatibility

FAT32 is supported.

The `~` character, used in long filenames, is mapped to the `>` character automatically.

## Building and installing

The build process outputs two files, `vzf-firmware.bin` (the I/O firmware image) and `vzf-BOARDNAME.[fs|bit]` (the FPGA gateware image).
Both files are then written to FPGA flash memory.

A unix build environment is assumed.
Both Yosys/nextpnr and GoWin toolchains are supported.
Additionally the following packages are required to build on Debian/Ubuntu:

```
sudo apt-get install make gcc-riscv64-unknown-elf openfpgaloader
```

### ROMs

Before building, ROMs `vtechv20.u12` and `vzdos.rom` must be converted to hex files.
To automatically convert ROMs to hex files, copy the files into the roms/ directory, and use the `make roms` command.

### Icepi Zero (Yoysy/nextpnr)

Commands to build:

```
make vzf-firmware.bin
make vzf-icepi-zero.bit
openFPGALoader -b icepi-zero --write-flash --offset 0x500000 vzf-firmware.bin
openFPGALoader -b icepi-zero --write-flash vzf-icepi-zero.bit
```

These steps can be automated by typing `make install-icepi-zero`.

WARNING: vzf-icepi-zero.bit has the `MASTER_SPI_PORT=DISABLE` flash configuration option.
This means that after flashing the first time, the flash memory can no longer be directly accessed from the USB programming cable.
To reflash the Icepi Zero you must first load a gateware image into SRAM with `MASTER_SPI_PORT=ENABLE`, and only then can you reflash.
Please understand this before flashing.

### Tang Nano 20K (Yosys/nextnpr)

Commands to build:

```
make vzf-firmware.bin
make vzf-tangnano20k.fs
openFPGALoader -b tangnano20k --write-flash --offset 0x500000 vzf-firmware.bin
openFPGALoader -b tangnano20k --write-flash vzf-tangnano20k.fs
```

These steps can be automated by typing `make install-tangnano20k`.

### Tang Nano 20K (Gowin)

Commands to build:

```
make vzf-firmware.bin
make impl/pnr/vzf.fs
openFPGALoader -b tangnano20k --write-flash --offset 0x500000 vzf-firmware.bin
openFPGALoader -b tangnano20k --write-flash impl/pnr/vzf.fs
```

These steps can be automated by typing `make install-tangnano20k-gowin`.

## Peripherals

### Icepi Zero

The Icepi Zero includes a HDMI Port, SD card slot, USB port for programming and two USB ports (1 and 2) for peripherals.
Plug the keyboard into USB 1, plug the gamepad/joystick into USB 2.

Icepi Zero currently has no speaker.

### Tang Nano 20K

The Tang Nano 20K includes an HDMI Port, SD card slot and USB port for programming.
Additional peripherals must be wired manually:

* Keyboard/Gamepad/Joystick USB Port. Follow the instructions here <https://github.com/nand2mario/usb_hid_host/blob/main/doc/usb_hid_host.md> to connect USB data lines to PINs 41 and 42. Plug the keyboard or gamepad/joystick here.
* Speaker. Attach to PIN 29 and GND.
* RS-232 serial port. Attach to PINs 25, 26 and GND. This is only required if using the VZ RS-232 extension ROM.

## Limitations

USB keyboard/gamepads/joysticks must be directly attached to the USB port.
USB hubs are not supported.

The design implements the VZ bus sharing configuration between Z80 and MC6847.
This produces realistic looking snow artifacts, however I still need to do a visual comparison.

FPGA SRAM is used for the VZ ROM, RAM, VRAM, a single track floppy disk buffer and cassette audio buffer.
Building a VZ with 64KiB RAM currently exceeds SRAM capacity of either board.

I/O uses they same keyboard layout as the VZ, therefore some FAT32 filename characters cannot be typed.
For example, the underscore character.

HDMI audio is not implemented yet.

## Credits

Resources used in the development of this project:

* LASER310 FPGA. <https://github.com/zzemu-cn/LASER310_FPGA>. Project inspiration.
* Nano-Z80. <https://github.com/venomix666/nano-z80> Project inspiration.
* TV80. <https://github.com/hutch31/tv80> Z80 CPU design
* PicoRV32. <https://github.com/yosyshq/picorv32> RISC-V CPU design
* `sdram_nestang.v`. <https://github.com/carlosbravoa/atari800_tang_nano20k> SDRAM controller.
* `spi_master.v`. <https://github.com/nandland/spi-master> SPI master.
* `spiflash.v`. <https://github.com/nand2mario/snestang> SPI flash loader.
* `usb_hid_host.v`. <https://github.com/m1nl/usb_hid_host> Low-Speed/High-Speed USB HID host.
* `uart_tx_V2.v`. <https://github.com/nand2mario/usb_hid_host> UART transmitter.
* HDMI. <https://github.com/hdl-util/hdmi> DVI/HDMI output (with modifications from NanoMig <https://github.com/MiSTle-Dev/NanoMig/>).
* FatFS. <https://elm-chan.org/fsw/ff/> Generic FAT Filesystem Module.
* `diskio.c`. <https://github.com/juliannojungle/fs.ll> SD card I/O.
* VzEmulator. <https://github.com/PaulAnderson/VzEmulator> Idea for floppy drive emulator.

## Contact

Peter Ross <pross@xvid.org>

GPG Fingerprint: A907 E02F A6E5 0CD2 34CD 20D2 6760 79C5 AC40 DD6B
