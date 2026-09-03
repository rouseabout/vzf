#!/bin/env gw_sh

set_device GW2AR-LV18QN88C8/I7 -device_version C

add_file -type cst src/boards/tangnano20k/tangnano20k.cst

add_file -type sdc src/boards/tangnano20k/tangnano20k.sdc

add_file -type verilog src/boards/tangnano20k/clocks.v
add_file -type verilog src/boards/tangnano20k/tangnano20k_top.v

add_file -type verilog src/hdmi/audio_clock_regeneration_packet.sv
add_file -type verilog src/hdmi/audio_info_frame.sv
add_file -type verilog src/hdmi/audio_sample_packet.sv
add_file -type verilog src/hdmi/auxiliary_video_information_info_frame.sv
add_file -type verilog src/hdmi/hdmi.sv
add_file -type verilog src/hdmi/packet_picker.sv
add_file -type verilog src/hdmi/packet_assembler.sv
add_file -type verilog src/hdmi/serializer.sv
add_file -type verilog src/hdmi/source_product_description_info_frame.sv
add_file -type verilog src/hdmi/tmds_channel.sv

add_file -type verilog src/io.v

add_file -type verilog src/mc6847.v

add_file -type verilog src/membram2.v
add_file -type verilog src/memdp.v
add_file -type verilog src/memdp_32_8.v

add_file -type verilog src/picorv32.v

add_file -type verilog src/sdram_nestang.v

add_file -type verilog src/spiflash.v

add_file -type verilog src/SPI_Master.v

add_file -type verilog src/top.v

add_file -type verilog src/tv80/tv80_alu.v
add_file -type verilog src/tv80/tv80_core.v
add_file -type verilog src/tv80/tv80_mcode.v
add_file -type verilog src/tv80/tv80_reg.v
add_file -type verilog src/tv80/tv80s.v

add_file -type verilog src/timer_22050.v

add_file -type verilog src/uart_tx_V2.v
add_file -type verilog src/uart_rx.v

add_file -type verilog src/usb_hid_host/usb_hid_host.v
add_file -type verilog src/usb_hid_host/usb_hid_host_rom.v

add_file -type verilog src/vz.v

# 'set_option -use_mspi_as_gpio' is required to access spi flash pins
# 'set_option -use_sspi_as_gpio' is required to access gpio[4], HP_DIN, HP_WS, HP_BCK pins

set_option -include_path src/boards/tangnano20k
set_option -output_base_name vzf
set_option -synthesis_tool gowinsynthesis
set_option -top_module tangnano20k_top
set_option -verilog_std sysv2017
#set_option -rw_check_on_ram 1
set_option -use_mspi_as_gpio 1
#set_option -use_ready_as_gpio 1
#set_option -use_done_as_gpio 1
#set_option -use_i2c_as_gpio 1
#set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1
#set_option -multi_boot 1
#set_option -place_option 2

run all
