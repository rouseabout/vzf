`define CONFIG_VZ
`define CONFIG_IO

module top #(
    parameter int LEFT_EDGE = 10'd104,
    parameter int TOP_EDGE = 10'd96,
    parameter WIDTH_BITS = 11,
    parameter HEIGHT_BITS = 10,
    parameter int SDRAM_DATA_WIDTH = 32,
    parameter int SDRAM_ADDR_WIDTH = 11
) (
    input clk_pixel,
    input clk_sdram,
    input clk_sdramp,

    input [7:0] key_modifiers,
    input [7:0] key0, key1, key2, key3,
    input game_l, game_r, game_u, game_d, game_a, game_b,
    input reset_n,

    output sd_csn,
    output sd_clk,
    output sd_mosi,
    input sd_miso,

    output wire speaker,

    input uart_rx_i,
    output uart_tx_o,

    input uart_b_rx_i,
    output uart_b_tx_o,

    output flash_spi_cs_n,
    input flash_spi_miso,
    output flash_spi_mosi,
    output flash_spi_clk,
    output flash_spi_wp_n,
    output flash_spi_hold_n,

    output wire O_sdram_clk,
    output wire O_sdram_cke,
    output wire O_sdram_cs_n,
    output wire O_sdram_cas_n,
    output wire O_sdram_ras_n,
    output wire O_sdram_wen_n,
    inout wire [SDRAM_DATA_WIDTH-1:0] IO_sdram_dq,
    output wire [SDRAM_ADDR_WIDTH-1:0] O_sdram_addr,
    output wire [1:0] O_sdram_ba,
    output wire [(SDRAM_DATA_WIDTH/8)-1:0] O_sdram_dqm,

    input fdcemu_en,

    output reg pal_mode,
    input vsync,
    input [WIDTH_BITS-1:0] cx,
    input [HEIGHT_BITS-1:0] cy,
    input [10:0] frame_width,
    input [9:0] frame_height,
    output [23:0] rgb
);
    localparam CLK_FREQ = 28_500_000;

    reg [26:0] top_status_show_counter;

    reg [7:0] last_key;
    reg show_vz;
    reg [1:0] speed;
    reg hear_cassette;
    always @(posedge clk_pixel or negedge reset_n) begin
        if (~reset_n) begin
            last_key <= 8'h00;
`ifdef CONFIG_VZ
            show_vz <= 1;
`else
            show_vz <= 0;
`endif
            speed <= 2'd0;
            pal_mode <= 1;
            hear_cassette <= 1;
        end else begin
            last_key <= key0;
            if (key0 == 8'h3a) begin // F1
                show_vz <= 1;
            end else if (key0 == 8'h3b) begin // F2
                show_vz <= 0;
            end else if (key0 != last_key && key0 == 8'h42) begin // F9
                speed <= speed == 2'd2 ? 2'd0 : speed + 1'b1;
                top_status_show_counter <= 3*CLK_FREQ;
            end else if (key0 != last_key && key0 == 8'h43) begin // F10
                pal_mode <= ~pal_mode;
                top_status_show_counter <= 3*CLK_FREQ;
            end else if (key0 != last_key && key0 == 8'h44) begin // F11
                hear_cassette <= ~hear_cassette;
                top_status_show_counter <= 3*CLK_FREQ;
            end else if (top_status_show_counter > 0) begin
                top_status_show_counter <= top_status_show_counter - 1'b1;
            end
        end
    end

    localparam VRAM_WIDTH = 11;
    wire vdg_rd;
    wire [VRAM_WIDTH-1:0] vdg_addr;
    wire [7:0] vdg_di, vz_vdg_di, ioc_vdg_di;
    wire vdg_ag, vz_vdg_ag;
    wire vdg_css, vz_vdg_css;
    wire vdg_bw;
    wire vdg_show_status, vz_vdg_show_status;
    wire vdg_status2;
    wire [4:0] vdg_status_addr;
    wire [7:0] vdg_status_data, vz_vdg_status_data, ioc_vdg_status_data;
    reg [7:0] top_status_data;

    assign vdg_di          = show_vz ? vz_vdg_di          : ioc_vdg_di;
    assign vdg_ag          = show_vz ? vz_vdg_ag          : 1'b0;
    assign vdg_css         = show_vz ? vz_vdg_css         : 1'b0;
    assign vdg_bw          = show_vz ? 1'b0               : 1'b1;
    assign vdg_show_status = vdg_status2 ? vz_vdg_show_status : (top_status_show_counter > 0);
    assign vdg_status_data = vdg_status2 ? vz_vdg_status_data : top_status_data;

    mc6847 #(.LEFT_EDGE(LEFT_EDGE), .TOP_EDGE(TOP_EDGE)) mc6847(
        .clk(clk_pixel),
        .reset_n(reset_n),
        .pal_mode(pal_mode),
        .rd(vdg_rd),
        .addr(vdg_addr),
        .di(vdg_di),
        .ag(vdg_ag),
        .css(vdg_css),
        .bw(vdg_bw),
        .show_status(vdg_show_status), .status2(vdg_status2), .addr_status(vdg_status_addr), .di_status(vdg_status_data),
        .cx(cx), .cy(cy), .frame_width(frame_width), .frame_height(frame_height), .rgb(rgb));

    wire [10:0] mosi_seek;
    wire [1:0] miso_wprotect;
    wire [11:0] fdc_shmem_addr;
    wire fdc_shmem_rd;
    wire fdc_shmem_wr;
    wire [7:0] fdc_shmem_din;
    wire [7:0] fdc_shmem_dout;

    wire [8:0] cas_mem_addr;
    wire [7:0] cas_mem_dout;

`ifdef CONFIG_VZ
    wire reset_vz = ((key_modifiers[4] | key_modifiers[0]) && key0 == 8'h45); //CTRL+F12
    vz vz(
        .clk(clk_pixel),
        .reset_n(reset_n & ~reset_vz),
        .speed(speed),
        .hear_cassette(hear_cassette),

        .key_modifiers(show_vz ? key_modifiers : 8'h00),
        .key0(show_vz ? key0 : 8'h00),
        .key1(show_vz ? key1 : 8'h00),
        .key2(show_vz ? key2 : 8'h00),
        .key3(show_vz ? key3 : 8'h00),

        .game_l(game_l), .game_r(game_r), .game_u(game_u), .game_d(game_d), .game_a(game_a), .game_b(game_b),

        .vsync(vsync),

        .vdg_rd(show_vz ? vdg_rd : 1'b0),
        .vdg_addr(show_vz ? vdg_addr : VRAM_WIDTH'(0)),
        .vdg_di(vz_vdg_di),
        .vdg_ag(vz_vdg_ag),
        .vdg_css(vz_vdg_css),
        .vdg_show_status(vz_vdg_show_status),
        .vdg_status_addr(vdg_status_addr),
        .vdg_status_data(vz_vdg_status_data),

        .fdcemu_en(fdcemu_en),

        .mosi_seek(mosi_seek),
        .miso_wprotect(miso_wprotect),
        .fdc_shmem_addr(fdc_shmem_addr),
        .fdc_shmem_rd(fdc_shmem_rd),
        .fdc_shmem_wr(fdc_shmem_wr),
        .fdc_shmem_dout(fdc_shmem_dout),
        .fdc_shmem_din(fdc_shmem_din),

        .cas_mem_addr(cas_mem_addr),
        .cas_mem_dout(cas_mem_dout),

        .speaker(speaker),

        .uart_rx_i(uart_rx_i), .uart_tx_o(uart_tx_o),

        .uart_b_rx_i(uart_b_rx_i), .uart_b_tx_o(uart_b_tx_o)
    );
`endif // CONFIG_VZ

`ifdef CONFIG_IO
    wire reset_ioc = ((key_modifiers[6] | key_modifiers[2]) && key0 == 8'h45); //ALT+F12
    io #(.SDRAM_DATA_WIDTH(SDRAM_DATA_WIDTH), .SDRAM_ADDR_WIDTH(SDRAM_ADDR_WIDTH)) io(
        .clk(clk_pixel),
        .clk_sdram(clk_sdram),
        .clk_sdramp(clk_sdramp),
        .reset_n(reset_n & ~reset_ioc),

        .key_modifiers(show_vz ? 8'h00 : key_modifiers),
        .key0(show_vz ? 8'h00 : key0),
         
        .vsync(vsync),

        .vdg_rd(show_vz ? 1'b0 : vdg_rd),
        .vdg_addr(show_vz ? 9'b0 : vdg_addr[8:0]),
        .vdg_di(ioc_vdg_di),
        .vdg_status_addr(vdg_status_addr),
        .vdg_status_data(ioc_vdg_status_data),

        .mosi_seek(mosi_seek),
        .miso_wprotect(miso_wprotect),
        .fdc_shmem_addr(fdc_shmem_addr),
        .fdc_shmem_rd(fdc_shmem_rd),
        .fdc_shmem_wr(fdc_shmem_wr),
        .fdc_shmem_dout(fdc_shmem_dout),
        .fdc_shmem_din(fdc_shmem_din),

        .cas_mem_addr(cas_mem_addr),
        .cas_mem_dout(cas_mem_dout),

        .sd_csn(sd_csn), .sd_clk(sd_clk), .sd_mosi(sd_mosi), .sd_miso(sd_miso),

        .flash_spi_cs_n(flash_spi_cs_n),
        .flash_spi_miso(flash_spi_miso),
        .flash_spi_mosi(flash_spi_mosi),
        .flash_spi_clk(flash_spi_clk),
        .flash_spi_wp_n(flash_spi_wp_n),
        .flash_spi_hold_n(flash_spi_hold_n),

        .O_sdram_clk(O_sdram_clk),
        .O_sdram_cke(O_sdram_cke),
        .O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_ras_n(O_sdram_ras_n),
        .O_sdram_wen_n(O_sdram_wen_n),
        .IO_sdram_dq(IO_sdram_dq),
        .O_sdram_addr(O_sdram_addr),
        .O_sdram_ba(O_sdram_ba),
        .O_sdram_dqm(O_sdram_dqm)
        );
`endif // CONFIG_IO

    always @(posedge clk_pixel or negedge reset_n) begin
        if (~reset_n) begin
            top_status_data <= 8'h00;
        end else begin
            case(vdg_status_addr)
            5'd0: top_status_data <= speed == 2'd0 ? 8'h16 : speed == 2'd1 ? 8'h16 : 8'h14; // VZ-200 / VZ-300 / TURBO
            5'd1: top_status_data <= speed == 2'd0 ? 8'h1a : speed == 2'd1 ? 8'h1a : 8'h15;
            5'd2: top_status_data <= speed == 2'd0 ? 8'h2d : speed == 2'd1 ? 8'h2d : 8'h12;
            5'd3: top_status_data <= speed == 2'd0 ? 8'h32 : speed == 2'd1 ? 8'h33 : 8'h02;
            5'd4: top_status_data <= speed == 2'd0 ? 8'h30 : speed == 2'd1 ? 8'h30 : 8'h0f;
            5'd5: top_status_data <= speed == 2'd0 ? 8'h30 : speed == 2'd1 ? 8'h30 : 8'h20;

            5'd14: top_status_data <= pal_mode ? 8'h10 : 8'h0e; // PAL / NTSC
            5'd15: top_status_data <= pal_mode ? 8'h01 : 8'h14;
            5'd16: top_status_data <= pal_mode ? 8'h0c : 8'h13;
            5'd17: top_status_data <= pal_mode ? 8'h20 : 8'h03;

            5'd23: top_status_data <= hear_cassette ? 8'h08 : 8'h20; // HEAR CASS
            5'd24: top_status_data <= hear_cassette ? 8'h05 : 8'h20;
            5'd25: top_status_data <= hear_cassette ? 8'h01 : 8'h20;
            5'd26: top_status_data <= hear_cassette ? 8'h12 : 8'h20;

            5'd28: top_status_data <= hear_cassette ? 8'h03 : 8'h20;
            5'd29: top_status_data <= hear_cassette ? 8'h01 : 8'h20;
            5'd30: top_status_data <= hear_cassette ? 8'h13 : 8'h20;
            5'd31: top_status_data <= hear_cassette ? 8'h13 : 8'h20;

            default: top_status_data <= 8'h20;
            endcase
        end
    end

endmodule
