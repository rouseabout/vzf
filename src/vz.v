//`define CONFIG_16KB
`define CONFIG_32KB
//`define CONFIG_64KB

`define CONFIG_DOS
//`define CONFIG_RS232
//`define CONFIG_RTTY
//`define CONFIG_DEMO
//`define CONFIG_MASER
//`define CONFIG_GALAXON

//`define CONFIG_WORDPRO
//`define CONFIG_INVADERS

module vz (
    input clk,
    input reset_n,
    input [1:0] speed,
    input hear_cassette,

    input [7:0] key_modifiers,
    input [7:0] key0, key1, key2, key3,
    input game_l, game_r, game_u, game_d, game_a, game_b,

    input vsync,

    input vdg_rd,
    input [VRAM_WIDTH-1:0] vdg_addr,
    output [7:0] vdg_di,
    output vdg_ag,
    output vdg_css,
    output vdg_show_status,
    input [4:0] vdg_status_addr,
    output reg [7:0] vdg_status_data,

    input fdcemu_en,

    output reg [10:0] mosi_seek,
    input [1:0] miso_wprotect,

    output [11:0] fdc_shmem_addr,
    output reg fdc_shmem_rd,
    output reg fdc_shmem_wr,
    output reg [7:0] fdc_shmem_din,
    input [7:0] fdc_shmem_dout,

    output reg [8:0] cas_mem_addr,
    input [7:0] cas_mem_dout,

    output wire speaker,

    input uart_rx_i,
    output uart_tx_o,

    input uart_b_rx_i,
    output uart_b_tx_o
);
    localparam CLK_FREQ = 28_500_000;

    localparam ROM_WIDTH = 14; /* 16k (0000-3fff) */
`ifdef CONFIG_16KB
    localparam RAM1_WIDTH = 14; /* 16k (7800-b7ff) */
`endif
`ifdef CONFIG_32KB
    localparam RAM1_WIDTH = 15; /* 32k (7800-f7ff) */
`endif
`ifdef CONFIG_64KB
    localparam RAM1_WIDTH = 11; /* 2k (7800-7fff) */
    localparam RAM2_WIDTH = 14; /* 16k (8000-bfff) */
    localparam RAM3_WIDTH = 14; /* 16k (c000-ffff) */
`endif

`ifdef CONFIG_DOS
`define CARTRIDGE1_ENABLE
`define CARTRIDGE1_FILENAME "vzdos.hex"
    localparam CARTRIDGE1_WIDTH = 13; /* 8k (4000-5fff) */
`endif

`ifdef CONFIG_RS232
`define CARTRIDGE1_ENABLE
`define CARTRIDGE1_FILENAME "rs232.hex"
    localparam CARTRIDGE1_WIDTH = 11; /* 2k (4000-47ff) */
`endif

`ifdef CONFIG_RTTY
`define CARTRIDGE1_ENABLE
`define CARTRIDGE1_FILENAME "vzrtty.hex"
    localparam CARTRIDGE1_WIDTH = 12; /* 4k (4000-4fff) */
`endif

`ifdef CONFIG_DEMO
`define CARTRIDGE1_ENABLE
`define CARTRIDGE1_FILENAME "demo-4000.hex"
    localparam CARTRIDGE1_WIDTH = 13; /* 8k (4000-5fff) */
`endif

`ifdef CONFIG_MASER
`define CARTRIDGE1_ENABLE
`define CARTRIDGE1_FILENAME "maser-4000.hex"
    localparam CARTRIDGE1_WIDTH = 13; /* 8k (4000-5fff) */
`endif

`ifdef CONFIG_GALAXON
`define CARTRIDGE1_ENABLE
`define CARTRIDGE1_FILENAME "galaxon-4000.hex"
    localparam CARTRIDGE1_WIDTH = 13; /* 8k (4000-5fff) */
`endif

`ifdef CONFIG_WORDPRO
`define CARTRIDGE2_ENABLE
`define CARTRIDGE2D_FILENAME "wordpro-d000.hex"
`define CARTRIDGE2E_FILENAME "wordpro-e000.hex"
`define CARTRIDGE2F_FILENAME "wordpro-f000.hex"
`endif

`ifdef CONFIG_INVADERS
`define CARTRIDGE2_ENABLE
`define CARTRIDGE2D_FILENAME "invaders-d000.hex"
`define CARTRIDGE2E_FILENAME ""
`define CARTRIDGE2F_FILENAME ""
`endif

    localparam VRAM_WIDTH = 11; /* 2k (7000-77ff) */
    localparam VRAM_LOC = 16'h7000;
    localparam RAM_LOC = 16'h7800;

    localparam ROM_SIZE = (1 << ROM_WIDTH);
`ifdef CARTRIDGE1_ENABLE
    localparam CARTRIDGE1_SIZE = (1 << CARTRIDGE1_WIDTH);
`endif
    localparam VRAM_SIZE = (1 << VRAM_WIDTH);
    localparam RAM1_SIZE = (1 << RAM1_WIDTH);

    wire vz200_xtal = 1;

 //   wire cpu_ce = 1;
    reg cpu_ce;
    reg [31:0] accumulator;
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            accumulator <= 32'd0;
            cpu_ce <= 1'b0;
        end else begin
            if (speed == 2'd2) begin
                cpu_ce <= 1;
            end else begin                                    /* 3.579500 MHz / 3.546894 MHz */
                {cpu_ce, accumulator} <= accumulator + (~speed[0] ? 539432822 : 534519078);
            end
        end
    end

    /* cpu inputs */
    reg wait_n;
    reg int_n;
    reg nmi_n;
    reg busrq_n;
    wire [7:0] data_miso;

    /* cpu outputs */
    wire m1_n;
    wire mreq_n;
    wire iorq_n;
    wire rd_n;
    wire wr_n;
    wire rfsh_n;
    wire halt_n;
    wire busak_n;
    wire [15:0] addr;
    wire [7:0] data_mosi;

`ifdef CONFIG_64KB
    reg [2:0] active_bank;
`endif

    wire ram1_cs_n;
    wire prn_cs_n, fdc_cs_n, joystick_cs_n, bank_cs_n, rom_cs_n;
`ifdef CARTRIDGE1_ENABLE
    wire cartridge1_cs_n;
`endif
`ifdef CARTRIDGE2_ENABLE
    wire cartridge26_cs_n;
`endif
    wire io_cs_n, vram_cs_n;
`ifdef CARTRIDGE2_ENABLE
    wire cartridge2d_cs_n, cartridge2e_cs_n, cartridge2f_cs_n;
`endif
`ifdef CONFIG_64KB
    wire ram2_cs_n;
    wire ram3_cs_n;
`endif

    reg [7:0] data_miso_fdc;
    wire [7:0] data_miso_joystick;
    wire [7:0] data_miso_rom;
`ifdef CARTRIDGE1_ENABLE
    wire [7:0] data_miso_cartridge1;
`endif
`ifdef CONFIG_RS232
    wire [7:0] data_miso_rs232;
`endif
    wire [7:0] data_miso_vram_cpu;
    wire [7:0] data_miso_ram1;
`ifdef CARTRIDGE2_ENABLE
    wire [7:0] data_miso_cartridge2d, data_miso_cartridge2e, data_miso_cartridge2f;
`endif
`ifdef CONFIG_64KB
    wire [7:0] data_miso_ram2;
    wire [7:0] data_miso_ram3_1, data_miso_ram3_2, data_miso_ram3_3;
`endif

    assign data_miso =
        ~prn_cs_n ? 8'hfe :
        ~fdc_cs_n ? data_miso_fdc :
        ~joystick_cs_n ? data_miso_joystick :
        ~rom_cs_n ? data_miso_rom :
`ifdef CARTRIDGE1_ENABLE
        ~cartridge1_cs_n ? data_miso_cartridge1 :
`endif
`ifdef CONFIG_RS232
        ~rs232rx_cs_n ? data_miso_rs232 :
`endif
`ifdef CARTRIDGE2_ENABLE
        ~cartridge26_cs_n ? data_miso_cartridge2d :
`endif
        ~io_cs_n ? KEY_DATA :
        ~vram_cs_n ? data_miso_vram_cpu :
        ~ram1_cs_n ? data_miso_ram1 :
`ifdef CARTRIDGE2_ENABLE
        ~cartridge2d_cs_n ? data_miso_cartridge2d :
        ~cartridge2e_cs_n ? data_miso_cartridge2e :
        ~cartridge2f_cs_n ? data_miso_cartridge2f :
`endif
`ifdef CONFIG_64KB
        ~ram2_cs_n ? data_miso_ram2 :
        ~ram3_cs_n & active_bank <= 1 ? data_miso_ram3_1 :
        ~ram3_cs_n & active_bank == 2 ? data_miso_ram3_2 :
        ~ram3_cs_n & active_bank == 3 ? data_miso_ram3_3 :
`endif
        8'h00;

    assign prn_cs_n = ~(!iorq_n & m1_n & (addr[7:4] == 4'h0));
    assign fdc_cs_n = ~(!iorq_n & m1_n & (addr[7:4] == 4'h1));
    assign joystick_cs_n = ~(!iorq_n & m1_n & (addr[7:4] == 4'h2));
    assign bank_cs_n = ~(!iorq_n & m1_n & (addr[7:4] == 4'h7));
    assign rom_cs_n = ~(!mreq_n & (addr < ROM_SIZE));
`ifdef CARTRIDGE1_ENABLE
    assign cartridge1_cs_n = ~(!mreq_n & (addr >= ROM_SIZE) & (addr < ROM_SIZE + CARTRIDGE1_SIZE));
`endif
`ifdef CONFIG_RS232
    assign rs232rx_cs_n = ~(!mreq_n & (addr >= 16'h5000) & (addr < 16'h5800));
    assign rs232tx_cs_n = ~(!mreq_n & (addr >= 16'h5800) & (addr < 16'h6000));
`endif
`ifdef CARTRIDGE2_ENABLE
    assign cartridge26_cs_n = ~(!mreq_n & (addr >= 16'h6000) & (addr < 16'h6800));
`endif
    assign io_cs_n = ~(!mreq_n & (addr >= 16'h6800) & (addr < VRAM_LOC));
    assign vram_cs_n = ~(!mreq_n & (addr >= VRAM_LOC) & (addr < (VRAM_LOC+VRAM_SIZE)));
    assign ram1_cs_n = ~(!mreq_n & (addr >= RAM_LOC) & (addr < (RAM_LOC+RAM1_SIZE)));
`ifdef CARTRIDGE2_ENABLE
    assign cartridge2d_cs_n = ~(!mreq_n & (addr >= 16'hd000) & (addr < 16'he000));
    assign cartridge2e_cs_n = ~(!mreq_n & (addr >= 16'he000) & (addr < 16'hf000));
    assign cartridge2f_cs_n = ~(!mreq_n & (addr >= 16'he000));
`endif
`ifdef CONFIG_64KB
    assign ram2_cs_n = ~(!mreq_n & (addr >= 16'h8000) & (addr < 16'hc000));
    assign ram3_cs_n = ~(!mreq_n & (addr >= 16'hc000));
`endif

    reg last_vsync;
    always @(posedge clk or negedge reset_n) begin
        if( reset_n == 1'b0 ) begin
            wait_n <= 1'b1;
            int_n <= 1'b1;
            nmi_n <= 1'b1;
            busrq_n <= 1'b1;

            last_vsync <= 1'b0;
        end else if (cpu_ce) begin
            last_vsync <= vsync;
            if (int_n & last_vsync & ~vsync) begin
                int_n <= 0;
            end else if (!m1_n && !iorq_n) begin
                int_n <= 1;
            end
        end
    end

    tv80s #(
        .Mode(0), // 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
        .T2Write(1), // 0 => wr_n active in T3, /=0 => wr_n active in T2
        .IOWait(1) // 0 => Single cycle I/O, 1 => Std I/O cycle
    ) cpu (
        .m1_n(m1_n),
        .mreq_n(mreq_n),
        .iorq_n(iorq_n),
        .rd_n(rd_n),
        .wr_n(wr_n),
        .rfsh_n(rfsh_n),
        .halt_n(halt_n),
        .busak_n(busak_n),
        .A(addr[15:0]),
        .dout(data_mosi),
        .reset_n(reset_n),
        .clk(clk),
        .cen(cpu_ce),
        .wait_n(wait_n),
        .int_n(int_n),
        .nmi_n(nmi_n),
        .busrq_n(busrq_n),
        .di(data_miso)
    );

    membram2 #(ROM_WIDTH, "rom.hex", 1) rom (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(data_miso_rom),
        .data_in('h0),
        .cs_n(rom_cs_n),
        .rd_n(rd_n),
        .wr_n(1'b1),
        .addr(addr[ROM_WIDTH-1:0])
    );

`ifdef CARTRIDGE1_ENABLE
    membram2 #(CARTRIDGE1_WIDTH, `CARTRIDGE1_FILENAME, 1) cartridge1 (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(data_miso_cartridge1),
        .data_in('h0),
        .cs_n(cartridge1_cs_n),
        .rd_n(rd_n),
        .wr_n(1'b1),
        .addr(addr[CARTRIDGE1_WIDTH-1:0])
    );
`endif

    membram2 #(RAM1_WIDTH, "", 0) ram1 (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(data_miso_ram1),
        .data_in(data_mosi),
        .cs_n(ram1_cs_n),
        .rd_n(rd_n),
        .wr_n(wr_n),
        .addr(addr[RAM1_WIDTH-1:0])
    );

`ifdef CARTRIDGE2_ENABLE
    membram2 #(12, `CARTRIDGE2D_FILENAME, 1) cartridge2_d (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(data_miso_cartridge2d),
        .data_in(data_mosi),
        .cs_n(cartridge26_cs_n & cartridge2d_cs_n),
        .rd_n(rd_n),
        .wr_n(1'b1),
        .addr(addr[12-1:0])
    );
    membram2 #(12, `CARTRIDGE2E_FILENAME, 1) cartridge2_e (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(data_miso_cartridge2e),
        .data_in(data_mosi),
        .cs_n(cartridge2e_cs_n),
        .rd_n(rd_n),
        .wr_n(1'b1),
        .addr(addr[12-1:0])
    );
    membram2 #(12, `CARTRIDGE2F_FILENAME, 1) cartridge2_f (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(data_miso_cartridge2f),
        .data_in(data_mosi),
        .cs_n(cartridge2f_cs_n),
        .rd_n(rd_n),
        .wr_n(1'b1),
        .addr(addr[12-1:0])
    );
`endif

`ifdef CONFIG_64KB
    membram2 #(RAM2_WIDTH) ram2 (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(data_miso_ram2),
        .data_in(data_mosi),
        .cs_n(ram2_cs_n),
        .rd_n(rd_n),
        .wr_n(wr_n),
        .addr(addr[RAM2_WIDTH-1:0])
    );
    membram2 #(RAM3_WIDTH) ram3_1 (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(data_miso_ram3_1),
        .data_in(data_mosi),
        .cs_n(ram3_cs_n | ~(active_bank <= 1)),
        .rd_n(rd_n),
        .wr_n(wr_n),
        .addr(addr[RAM3_WIDTH-1:0])
    );
    membram2 #(RAM3_WIDTH) ram3_2 (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(data_miso_ram3_2),
        .data_in(data_mosi),
        .cs_n(ram3_cs_n | ~(active_bank == 2)),
        .rd_n(rd_n),
        .wr_n(wr_n),
        .addr(addr[RAM3_WIDTH-1:0])
    );
    membram2 #(RAM3_WIDTH) ram3_3 (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(data_miso_ram3_3),
        .data_in(data_mosi),
        .cs_n(ram3_cs_n | ~(active_bank == 3)),
        .rd_n(rd_n),
        .wr_n(wr_n),
        .addr(addr[RAM3_WIDTH-1:0])
    );
`endif

    wire [7:0] data_miso_vram_vdg;

    memdp #(.ADDR_WIDTH(VRAM_WIDTH)) vram(
        .clka(~clk),
        .reseta(~reset_n),
        .cea(~vram_cs_n),
        .ocea(~rd_n),
        .wrea(~wr_n),
        .douta(data_miso_vram_cpu),
        .dina(data_mosi),
        .ada(addr[VRAM_WIDTH-1:0]),

        .clkb(~clk),
        .resetb(~reset_n),
        .ceb(vdg_rd /*& vram_cs_n*/),
        .oceb(vdg_rd),
        .wreb(1'b0),
        .doutb(data_miso_vram_vdg),
        .dinb(8'h00),
        .adb(vdg_addr[VRAM_WIDTH-1:0])
    );
    assign vdg_di = vram_cs_n ? data_miso_vram_vdg : data_miso_vram_cpu;

    // keyboard

    reg serialkb_valid;
    wire [7:0] serialkb_byte;

`define KEY(name, code, ascii) \
    wire key_``name = ~(key0 == code || key1 == code || key2 == code || key3 == code || (serialkb_valid & |ascii & serialkb_byte == ascii));

`define KEY2(name, code, ascii1, ascii2) \
    wire key_``name = ~(key0 == code || key1 == code || key2 == code || key3 == code || (serialkb_valid & ((|ascii1 & serialkb_byte == ascii1) | (|ascii2 & serialkb_byte == ascii2))));

    // 68FE
    `KEY(t, 8'h17, "T") // T
    `KEY(w, 8'h1a, "W") // W
    `KEY(e, 8'h08, "E") // E
    `KEY(q, 8'h14, "Q") // Q
    `KEY(r, 8'h15, "R") // R

    // 68FD
    `KEY(g, 8'h0a, "G") // G
    `KEY(s, 8'h16, "S") // S
    wire key_ctrl = ~(key_modifiers[4] | key_modifiers[0]);
    `KEY(d, 8'h07, "D") // D
    `KEY(a, 8'h04, "A") // A
    `KEY(f, 8'h09, "F") // F

    // 68FB
    `KEY(b, 8'h05, "B") // B
    `KEY(x, 8'h1b, "X") // X
    wire key_shift = ~(key_modifiers[5] | key_modifiers[1] | (serialkb_valid & (
          serialkb_byte == "!"
        | serialkb_byte == "\""
        | serialkb_byte == "#"
        | serialkb_byte == "$"
        | serialkb_byte == "%"
        | serialkb_byte == "&"
        | serialkb_byte == "'"
        | serialkb_byte == "("
        | serialkb_byte == ")"
        | serialkb_byte == "@"
        | serialkb_byte == "="
        | serialkb_byte == "["
        | serialkb_byte == "]"
        | serialkb_byte == "/"
        | serialkb_byte == "?"
        | serialkb_byte == "+"
        | serialkb_byte == "*"
        | serialkb_byte == "\\"
        | serialkb_byte == "<"
        | serialkb_byte == ">"
        )));
    `KEY(c, 8'h06, "C") // C
    `KEY(z, 8'h1d, "Z") // Z
    `KEY(v, 8'h19, "V") // V

    // 68F7
    `KEY2(5, 8'h22, "5", "%") // 5 %
    `KEY2(2, 8'h1f, "2", "\"") // 2 @
    `KEY2(3, 8'h20, "3", "#") // 3 #
    `KEY2(1, 8'h1e, "1", "!") // 1 !
    `KEY2(4, 8'h21, "4", "$") // 4 $

    // 68EF
    `KEY(n, 8'h11, "N") // N
    `KEY2(period, 8'h37, ".", ">") // . >
    `KEY2(comma, 8'h36, ",", "<") // , <
    `KEY(space, 8'h2c, " ") // SPACE
    `KEY2(m, 8'h10, "M", "\\") // M

    // 68DF
    `KEY2(6, 8'h23, "6", "&") // 6 ^
    `KEY2(9, 8'h26, "9", ")") // 9 (
    `KEY2(minus, 8'h2d, "-", "=") // - _
    `KEY2(8, 8'h25, "8", "(") // 8 *
    `KEY2(0, 8'h27, "0", "@") // 0 )
    `KEY2(7, 8'h24, "7", "'") // 7 ^

    // 68BF
    `KEY(y, 8'h1c, "Y") // // Y
    `KEY2(o, 8'h12, "O", "[") // O
    `KEY(return, 8'h28, 8'h0d) // RETURN
    `KEY(i, 8'h0c, "I") // I
    `KEY2(p, 8'h13, "P", "]") // P
    `KEY(u, 8'h18, "U") // U

    // 687F
    `KEY(h, 8'h0b, "H") // H
    `KEY2(l, 8'h0f, "L", "?") // L
    `KEY2(apostrophe, 8'h34, ":", "*") // ' "
    `KEY2(k, 8'h0e, "K", "/") // K
    `KEY2(semicolon, 8'h33, ";", "+") // ; :
    `KEY(j, 8'h0d, "J") // J

    // additional mappings
    `KEY(backspace, 8'h2a, 8'h08) // BACKSPACE
    `KEY(insert, 8'h49, 8'b0) // INSERT
    `KEY(delete, 8'h4c, 8'b0) // DELETE
    `KEY(right, 8'h4f, 8'b0) // RIGHT
    `KEY(left, 8'h50, 8'b0) // LEFT
    `KEY(down, 8'h51, 8'b0) // DOWN
    `KEY(up, 8'h52, 8'b0) // UP

    wire key_ctrl2 = key_ctrl & key_backspace & key_insert & key_delete & key_left & key_right & key_up & key_down;

    reg [7:0] cassette_miso;
    wire cassette_miso_bit = cassette_miso > 8'hb5 ? 1'b0 : 1'b1;

    wire KEY_DATA_BIT7 = vsync;
    wire KEY_DATA_BIT6 = cassette_miso_bit;
    wire KEY_DATA_BIT5 = (addr[7:0]|{key_j,                      key_u,      key_7,     key_m & key_left & key_backspace, key_4, key_v,     key_f,     key_r})==8'hff;
    wire KEY_DATA_BIT4 = (addr[7:0]|{key_semicolon & key_delete, key_p,      key_0,     key_space & key_down,             key_1, key_z,     key_a,     key_q})==8'hff;
    wire KEY_DATA_BIT3 = (addr[7:0]|{key_k,                      key_i,      key_8,     key_comma & key_right,            key_3, key_c,     key_d,     key_e})==8'hff;
    wire KEY_DATA_BIT2 = (addr[7:0]|{key_apostrophe,             key_return, key_minus, 1'b1,                             1'b1,  key_shift, key_ctrl2, 1'b1 })==8'hff;
    wire KEY_DATA_BIT1 = (addr[7:0]|{key_l & key_insert,         key_o,      key_9,     key_period & key_up,              key_2, key_x,     key_s,     key_w})==8'hff;
    wire KEY_DATA_BIT0 = (addr[7:0]|{key_h,                      key_y,      key_6,     key_n,                            key_5, key_b,     key_g,     key_t})==8'hff;

wire [7:0] KEY_DATA = { KEY_DATA_BIT7, KEY_DATA_BIT6, KEY_DATA_BIT5, KEY_DATA_BIT4, KEY_DATA_BIT3, KEY_DATA_BIT2, KEY_DATA_BIT1, KEY_DATA_BIT0 };

    // output register
    // bit 0: speaker a
    // bit 1: cassette output (lsb)
    // bit 2: cassette output (msb)
    // bit 3: vdg ag / display mode
    // bit 4: vdg css / background color
    // bit 5: speaker b
    reg[7:0] output_register;

    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            output_register <= 8'b00000000;
        end else begin
            if ({mreq_n,rd_n,wr_n,io_cs_n}==4'b0100) begin
                output_register <= data_mosi;
            end
        end
    end

    assign speaker = output_register[0] ^ (hear_cassette ? cassette_miso_bit ^ output_register[2] : 1'b0);
    assign vdg_ag = output_register[3];
    assign vdg_css = output_register[4];

    // floppy drive

    reg [1:0] fdc_drive;
    reg [15:0] fdc_wdata;
    reg [4:0] fdc_bits_available;
    reg [7:0] fdc_track_x2[0:1];
    reg [7:0] fdc_last_latch;

    reg [23:0] fdc_cycles, fdc_last_poll_cycles;
    reg [14:0] fdc_location_on_track;
    reg fdc_last_poll_value;

    assign fdc_shmem_addr = fdc_location_on_track[14:3];

    task drive_seek(input drive);
        begin
            $display("drive %d get track %d", drive, fdc_track_x2[drive]/2);
        end
    endtask

    reg iorq_n_last;

    reg fdc_write_first_bit;
    reg fdc_dirty;

    wire fdc_iorq_pulse = fdcemu_en & iorq_n_last & ~iorq_n & addr[7:4] == 4'h1;

    wire [1:0] drive = data_mosi[4] ? 0 : data_mosi[7] ? 1 : 3;
    reg seek_pulse;
    reg write_pulse;

    wire period_elapsed = (fdc_cycles - fdc_last_poll_cycles) > 35;
    wire next_poll_value = period_elapsed ? ~fdc_last_poll_value : fdc_last_poll_value;

    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            fdc_drive <= 2'd3;
            fdc_wdata <= 16'b0;
            fdc_bits_available <= 5'd0;
            fdc_track_x2[0] <= 8'd0;
            fdc_track_x2[1] <= 8'd0;
            fdc_last_latch <= 8'b0;
            fdc_cycles <= 24'd0;
            fdc_last_poll_cycles <= 24'd0;
            fdc_location_on_track <= 15'd0;
            fdc_last_poll_value <= 1'b0;
            iorq_n_last <= 1'b0;
            fdc_write_first_bit <= 1'b0;
            fdc_dirty <= 1'b0;
            seek_pulse <= 0;
            write_pulse <= 0;
        end else begin
            fdc_cycles <= fdc_cycles + 1'b1;
            iorq_n_last <= iorq_n;
            fdc_shmem_wr <= 0;
            fdc_shmem_rd <= 1; /* read by default */
            seek_pulse <= 0;
            write_pulse <= 0;
            if (fdc_iorq_pulse & ~wr_n & addr[3:0] == 4'h0) begin
                if (drive != fdc_drive) begin
                    seek_pulse <= 1;
                    fdc_drive <= drive;
                end
                if (drive < 2) begin
                    if (  (data_mosi[0] & ~(data_mosi[1] | data_mosi[2] | data_mosi[3]) & fdc_last_latch[1])
                        | (data_mosi[1] & ~(data_mosi[0] | data_mosi[2] | data_mosi[3]) & fdc_last_latch[2])
                        | (data_mosi[2] & ~(data_mosi[0] | data_mosi[1] | data_mosi[3]) & fdc_last_latch[3])
                        | (data_mosi[3] & ~(data_mosi[0] | data_mosi[1] | data_mosi[2]) & fdc_last_latch[0]) ) begin
                        if (fdc_track_x2[drive[0]] > 0)
                            fdc_track_x2[drive[0]] <= fdc_track_x2[drive[0]] - 1;
                        seek_pulse <= 1;
                    end
                    if (  (data_mosi[0] & ~(data_mosi[1] | data_mosi[2] | data_mosi[3]) & fdc_last_latch[3])
                        | (data_mosi[1] & ~(data_mosi[0] | data_mosi[2] | data_mosi[3]) & fdc_last_latch[0])
                        | (data_mosi[2] & ~(data_mosi[0] | data_mosi[1] | data_mosi[3]) & fdc_last_latch[1])
                        | (data_mosi[3] & ~(data_mosi[0] | data_mosi[1] | data_mosi[2]) & fdc_last_latch[2]) ) begin
                        if (fdc_track_x2[drive[0]] < 2*40)
                            fdc_track_x2[drive[0]] <= fdc_track_x2[drive[0]] + 1;
                        seek_pulse <= 1;
                    end
                    if (~data_mosi[6]) begin //this ctrl is write
                        if (fdc_last_latch[6]) begin //last ctrl was not-write, ignore first write bit
                            fdc_location_on_track <= ((fdc_location_on_track / 8) + 1) * 8;
                            fdc_wdata <= 0;
                            fdc_bits_available <= 0;
                        end else begin
                            if (~fdc_bits_available[0]) begin
                                fdc_write_first_bit <= data_mosi[5];
                            end else begin
                                if (fdc_write_first_bit ^ data_mosi[5]) begin
                                    fdc_wdata[7 - fdc_bits_available / 2] <= 1;
                                end
                            end
                            if (fdc_bits_available == 15) begin
                                fdc_bits_available <= 0;
                                write_pulse <= 1;
                            end else begin
                                fdc_bits_available <= fdc_bits_available + 1;
                            end
                        end
                    end
                end
                fdc_last_latch <= data_mosi;
            end

            if (seek_pulse) begin
                mosi_seek <= {fdc_dirty,fdc_track_x2[fdc_drive[0]],fdc_drive};
                fdc_dirty <= 0;
            end

            if (write_pulse) begin
                fdc_shmem_wr <= 1;
                fdc_shmem_rd <= 0;
                fdc_shmem_din <= fdc_wdata;
                if (fdc_location_on_track < 2480*8 - 8) begin
                    fdc_location_on_track <= fdc_location_on_track + 8;
                end else begin
                    fdc_location_on_track <= 0;
                end
                fdc_wdata <= 0;
                fdc_dirty <= 1;
            end

            if (fdc_iorq_pulse & ~rd_n & addr[3:0] == 4'h1) begin
                data_miso_fdc <= fdc_shmem_dout;
            end

            if (fdc_iorq_pulse & ~rd_n & addr[3:0] == 4'h2) begin
                if (period_elapsed) begin
                    fdc_last_poll_cycles <= fdc_cycles;
                    fdc_last_poll_value <= ~fdc_last_poll_value;
                    if (next_poll_value && fdc_last_latch[6]) begin // if inverter value == 0x80 and not writing
                        if (fdc_location_on_track < 2480*8) begin
                            fdc_location_on_track <= fdc_location_on_track + 1;
                        end else begin
                            fdc_location_on_track <= 0;
                        end
                    end
                end
                data_miso_fdc <= {next_poll_value,7'b0000000};
            end

            if (fdc_iorq_pulse & ~rd_n & addr[3:0] == 4'h3) begin
                data_miso_fdc[7] <= fdc_drive < 2 ? miso_wprotect[fdc_drive[0]] : 1'b1;
            end
        end
    end

    // printer
    reg [7:0] uart_byte;
    reg uart_wr_en;
    uart_tx_V2 #(.clk_freq(CLK_FREQ)) uart_tx(.clk(clk), .din(uart_byte), .wr_en(uart_wr_en), .tx_busy(), .tx_p(uart_tx_o));

    wire prn_io_data = (~iorq_n) & (~wr_n) & addr[7:4] == 4'h0;
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            uart_wr_en <= 0;
        end else begin
            uart_wr_en <= 0;
            if (prn_io_data & (addr[3:0]==4'h0 | addr[3:0]==4'he)) begin
                uart_wr_en <= 1;
                uart_byte <= data_mosi;
                $display("printer port %h data %h", addr[7:0], data_mosi);
            end
        end
    end

    // serial port based keyboard emulator

    wire serialkb_strobe;
    uart_rx #(.CLK_FREQ(CLK_FREQ)) uart_rx(.clk(clk), .reset_n(reset_n), .uart_rx(uart_rx_i), .rx_byte(serialkb_byte), .rx_strobe(serialkb_strobe));

    localparam int MS_TICKS = CLK_FREQ / 1000;
    reg [20:0] serial_press_counter;
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            serialkb_valid <= 0;
            serial_press_counter <= 0;
        end else begin
            if (serialkb_strobe) begin
                serialkb_valid <= 1;
                serial_press_counter <= 0;
            end else begin
                serial_press_counter <= serial_press_counter + 1'b1;
                if (serial_press_counter > 20*MS_TICKS) begin
                    serialkb_valid <= 0;
                end
            end
        end
    end

`ifdef CONFIG_64KB
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            active_bank <= 1;
        end else begin
            if (~bank_cs_n & ~wr_n) begin
                $display("bank port request %h, value %h\n", addr[7:0], data_mosi);
                active_bank <= data_mosi[2:0];
            end
        end
    end
`endif

`ifdef CONFIG_RS232
    reg rs232_tx;
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            rs232_tx <= 1;
        end else begin
            if (~rs232tx_cs_n & ~wr_n) begin
                rs232_tx <= ~data_mosi[7];
            end
        end
    end
    assign uart_b_tx_o = rs232_tx;
    assign data_miso_rs232 = {uart_b_rx_i,7'b1111111};
`endif

    // map keyboard keypad keys as joystick 2
`KEY(kp2, 8'h5a, 8'b0) // KEYPAD 2 / DOWN
`KEY(kp4, 8'h5c, 8'b0) // KEYPAD 4 / LEFT
`KEY(kp6, 8'h5e, 8'b0) // KEYPAD 6 / RIGHT
`KEY(kp8, 8'h60, 8'b0) // KEYPAD 8 / UP
`KEY(kp0, 8'h62, 8'b0) // KEYPAD 0 / INSERT
`KEY(kp_dot, 8'h63, 8'b0) // KEYPAD . / DELETE
    wire game2_l = ~key_kp4;
    wire game2_r = ~key_kp6;
    wire game2_u = ~key_kp8;
    wire game2_d = ~key_kp2;
    wire game2_a = ~key_kp0;
    wire game2_b = ~key_kp_dot;

    // joystick
    wire [7:0] data_miso_joystick_27;
    wire [7:0] data_miso_joystick_2b;
    wire [7:0] data_miso_joystick_2d;
    wire [7:0] data_miso_joystick_2e;

    assign data_miso_joystick_27 = {3'b111,~game2_b,4'b1111}; //joy2
    assign data_miso_joystick_2b = {3'b111,~game2_a,~game2_r,~game2_l,~game2_d,~game2_u}; // joy2
    assign data_miso_joystick_2d = {3'b111,~game_b,4'b1111}; //joy1
    assign data_miso_joystick_2e = {3'b111,~game_a,~game_r,~game_l,~game_d,~game_u}; // joy1

    assign data_miso_joystick = addr[3:0]==4'h7 ? data_miso_joystick_27 :
                                addr[3:0]==4'hb ? data_miso_joystick_2b :
                                addr[3:0]==4'hd ? data_miso_joystick_2d :
                                addr[3:0]==4'he ? data_miso_joystick_2e : 8'h01;


    //cassette audio
    wire audio_pulse;
    timer_22050 timer_22050(.clk(clk), .rst_n(reset_n), .pulse(audio_pulse));

    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            cassette_miso <= 8'h00;
            cas_mem_addr <= 0;
        end else begin
            if (audio_pulse) begin
                cassette_miso <= cas_mem_dout;
                cas_mem_addr <= cas_mem_addr + 1'b1;
            end
        end
    end

    // status bar
    function [7:0] hex_to_ascii;
        input [3:0] nibble;
        begin
            if (nibble < 4'hA)
                hex_to_ascii = 8'h30 + nibble;
            else
                hex_to_ascii = 8'h01 + (nibble - 4'hA);
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            vdg_status_data <= 8'h00;
        end else begin
            case(vdg_status_addr)
            5'd1: vdg_status_data <= 8'h04; //'D'
            5'd2: vdg_status_data <= 8'h09; //'I'
            5'd3: vdg_status_data <= 8'h13; //'S'
            5'd4: vdg_status_data <= 8'h0b; //'K'

            5'd6: vdg_status_data <= 8'h04; //'D'
            5'd7: vdg_status_data <= 8'h12; //'R'
            5'd8: vdg_status_data <= 8'h09; //'I'
            5'd9: vdg_status_data <= 8'h16; //'V'
            5'd10: vdg_status_data <= 8'h05; //'E'

            5'd12: vdg_status_data <= 8'h31 + fdc_drive[0];

            5'd14: vdg_status_data <= 8'h14; //'T'
            5'd15: vdg_status_data <= 8'h12; //'R'
            5'd16: vdg_status_data <= 8'h01; //'A'
            5'd17: vdg_status_data <= 8'h03; //'C'
            5'd18: vdg_status_data <= 8'h0b; //'K'

            5'd20: vdg_status_data <= hex_to_ascii({1'b0,fdc_track_x2[fdc_drive[0]][7:5]});
            5'd21: vdg_status_data <= hex_to_ascii(fdc_track_x2[fdc_drive[0]][4:1]);

            5'd23: vdg_status_data <= 8'h13; //'S'
            5'd24: vdg_status_data <= 8'h05; //'E'
            5'd25: vdg_status_data <= 8'h03; //'C'
            5'd26: vdg_status_data <= 8'h14; //'T'
            5'd27: vdg_status_data <= 8'h0f; //'O'
            5'd28: vdg_status_data <= 8'h12; //'R'

            5'd30: vdg_status_data <= hex_to_ascii(fdc_location_on_track[14:3] / 155);

            default: vdg_status_data <= 8'h20;
            endcase
        end
    end
    assign vdg_show_status = fdc_drive < 2;

endmodule
