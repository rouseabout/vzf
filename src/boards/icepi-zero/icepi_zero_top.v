module icepi_zero_top
(
    input clk,
    input [1:0] button,
    output [4:0] led,

    input usb_rx,
    output usb_tx,

    output [3:0] gpdi_dp,

    output [1:0] usb_pull_dp,
    output [1:0] usb_pull_dn,
    inout [1:0] usb_dp,
    inout [1:0] usb_dn,

    output sd_csn,
    output sd_clk,
    output sd_mosi,
    input sd_miso,

    output flash_csn,
    output flash_mosi,
    output flash_wpn,
    output flash_resetn,
    input flash_miso,

    output [12:0] sdram_a,
    inout [15:0] sdram_dq,
    output [1:0] sdram_ba,
    output [1:0] sdram_dqm,
    output sdram_wen,
    output sdram_casn,
    output sdram_rasn,
    output sdram_csn,
    output sdram_cke,
    output sdram_clk,
);
    wire reset_n;
    assign reset_n = button[0];

    //clocks
    wire clk_60, clk_60p, locked;
    clock1 clock1(
        .reset(~reset_n),
        .clk(clk),
        .clk_60(clk_60),
        .clk_60p(clk_60p),
        .locked(locked)
       );

    wire clk_pixel_x5, clk_pixel, video_locked;
    clock2 clock2(
        .reset(~locked),
        .clk_60(clk_60),
        .clk_pixel_x5(clk_pixel_x5),
        .clk_pixel(clk_pixel),
        .locked(video_locked)
       );

    // audio/video out
    wire [2:0] tmds;
    wire tmds_clock;

    wire pal_mode;
    wire vsync;
    wire [10:0] cx;
    wire [9:0] cy;
    wire [10:0] frame_width;
    wire [9:0] frame_height;
    wire [23:0] rgb;

    hdmi #(
        .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16),
        .VENDOR_NAME( { "VTECH", 24'd0} ),
        .PRODUCT_DESCRIPTION( {"VZ-FPGA", 72'd0} )
    ) hdmi (
        .clk_pixel_x5(clk_pixel_x5),
        .clk_pixel(clk_pixel),
        //.clk_audio(clk_audio),
        //.audio_sample_en(),
        //.audio_sample_word_0(audio_reg),
        //.audio_sample_word_1(audio_reg),
        .tmds(tmds),
        .tmds_clock(tmds_clock),

        .pal_mode(pal_mode),
        .short_frame(1'b0),
        .screen(2'd0),
        .interlace(1'b0),
        .reset(1'b0),

        .vsync(vsync),
        .cx(cx),
        .cy(cy),
        .frame_width(frame_width),
        .frame_height(frame_height),
        .rgb(rgb)
        );

    assign gpdi_dp[0] = tmds[0];
    assign gpdi_dp[1] = tmds[1];
    assign gpdi_dp[2] = tmds[2];
    assign gpdi_dp[3] = tmds_clock;

    // keyboard/gamepad/joystick
    assign usb_pull_dp = 2'b0;
    assign usb_pull_dn = 2'b0;

    wire usb0_dm_i, usb0_dp_i;
    wire usb0_dm_o, usb0_dp_o;
    wire usb0_oe;
    wire [9:0] usb0_rom_addr;
    wire [3:0] usb0_rom_dout;
    wire usb0_rom_en;
    wire [1:0] usb0_type;
    wire usb0_report;

    wire usb1_dm_i, usb1_dp_i;
    wire usb1_dm_o, usb1_dp_o;
    wire usb1_oe;
    wire [9:0] usb1_rom_addr;
    wire [3:0] usb1_rom_dout;
    wire usb1_rom_en;
    wire [1:0] usb1_type;
    wire usb1_report;

    wire [7:0] key_modifiers, key0, key1, key2, key3;
    wire game_l, game_r, game_u, game_d, game_a, game_b;

    usb_hid_host #(.FULL_SPEED(1)) usb_hid_host0 (
        .clk(clk_60),
        .reset(~reset_n | ~locked),
        .cs(1'b1),

        .usb_dm_i(usb0_dm_i), .usb_dp_i(usb0_dp_i),
        .usb_dm_o(usb0_dm_o), .usb_dp_o(usb0_dp_o),
        .usb_oe(usb0_oe),

        .typ(usb0_type),
        .full_report(usb0_report),
        .connerr(),
        .busy(),

        .key_modifiers(key_modifiers),
        .key_0(key0),
        .key_1(key1),
        .key_2(key2),
        .key_3(key3),
        .key_4(),
        .key_5(),

        .rom_addr(usb0_rom_addr),
        .rom_dout(usb0_rom_dout),
        .rom_en(usb0_rom_en)
        );

    assign usb0_dm_i = usb_dn[0];
    assign usb0_dp_i = usb_dp[0];
    assign usb_dn[0] = usb0_oe ? usb0_dm_o : 1'bZ;
    assign usb_dp[0] = usb0_oe ? usb0_dp_o : 1'bZ;

    usb_hid_host #(.FULL_SPEED(1)) usb_hid_host1 (
        .clk(clk_60),
        .reset(~reset_n | ~locked),
        .cs(1'b1),

        .usb_dm_i(usb1_dm_i), .usb_dp_i(usb1_dp_i),
        .usb_dm_o(usb1_dm_o), .usb_dp_o(usb1_dp_o),
        .usb_oe(usb1_oe),

        .typ(usb1_type),
        .full_report(usb1_report),
        .connerr(),
        .busy(),

        .game_l(game_l), .game_r(game_r), .game_u(game_u), .game_d(game_d),
        .game_a(game_a), .game_b(game_b), .game_x(), .game_y(),
        .game_sel(), .game_sta(),
        .game_extra(),

        .rom_addr(usb1_rom_addr),
        .rom_dout(usb1_rom_dout),
        .rom_en(usb1_rom_en)
        );

    assign usb1_dm_i = usb_dn[1];
    assign usb1_dp_i = usb_dp[1];
    assign usb_dn[1] = usb1_oe ? usb1_dm_o : 1'bZ;
    assign usb_dp[1] = usb1_oe ? usb1_dp_o : 1'bZ;

    usb_hid_host_dual_rom usb_rom (
        .clk(clk_60),

        .addra(usb0_rom_addr),
        .douta(usb0_rom_dout),
        .ena(usb0_rom_en),

        .addrb(usb1_rom_addr),
        .doutb(usb1_rom_dout),
        .enb(usb1_rom_en)
        );

    reg [0:7] key_modifiers_w, key0_w, key1_w, key2_w, key3_w;
    reg game_l_w, game_r_w, game_u_w, game_d_w, game_a_w, game_b_w;
    always @(posedge clk_60 or negedge reset_n) begin
        if (~reset_n) begin
            key_modifiers_w <= 0;
            key0_w <= 0;
            key1_w <= 0;
            key2_w <= 0;
            key3_w <= 0;
            game_l_w <= 0;
            game_r_w <= 0;
            game_u_w <= 0;
            game_d_w <= 0;
            game_a_w <= 0;
            game_b_w <= 0;
        end else begin
            if (usb0_report) begin
                if (usb0_type == 2'd1) begin
                    key_modifiers_w <= key_modifiers;
                    key0_w <= key0;
                    key1_w <= key1;
                    key2_w <= key2;
                    key3_w <= key3;
                end
            end
            if (usb1_report) begin
                if (usb1_type == 2'd3) begin
                    game_l_w <= game_l;
                    game_r_w <= game_r;
                    game_u_w <= game_u;
                    game_d_w <= game_d;
                    game_a_w <= game_a;
                    game_b_w <= game_b;
                end
            end
        end
    end

    reg [0:7] key_modifiers_r, key0_r, key1_r, key2_r, key3_r;
    reg game_l_r, game_r_r, game_u_r, game_d_r, game_a_r, game_b_r;
    always @(posedge clk_pixel or negedge reset_n) begin
        if (~reset_n) begin
            key_modifiers_r <= 0;
            key0_r <= 0;
            key1_r <= 0;
            key2_r <= 0;
            key3_r <= 0;
            game_l_r <= 0;
            game_r_r <= 0;
            game_u_r <= 0;
            game_d_r <= 0;
            game_a_r <= 0;
            game_b_r <= 0;
        end else begin
            key_modifiers_r <= key_modifiers_w;
            key0_r <= key0_w;
            key1_r <= key1_w;
            key2_r <= key2_w;
            key3_r <= key3_w;
            game_l_r <= game_l_w;
            game_r_r <= game_r_w;
            game_u_r <= game_u_w;
            game_d_r <= game_d_w;
            game_a_r <= game_a_w;
            game_b_r <= game_b_r;
        end
    end

    wire flash_sck;
    wire tristate = 1'b0;
    USRMCLK u1 (.USRMCLKI(flash_sck), .USRMCLKTS(tristate));

    top #(
        .LEFT_EDGE(104), .TOP_EDGE(96),
        .SDRAM_DATA_WIDTH(16), .SDRAM_ADDR_WIDTH(13)
    ) top (
        .clk_pixel(clk_pixel), .clk_sdram(clk_60), .clk_sdramp(clk_60p),
        .key_modifiers(key_modifiers_r), .key0(key0_r), .key1(key1_r), .key2(key2_r), .key3(key3_r),
        .game_l(game_l_r), .game_r(game_r_r), .game_u(game_u_r), .game_d(game_d_r), .game_a(game_a_r), .game_b(game_b_r),
        .pal_mode(pal_mode),
        .vsync(vsync), .cx(cx), .cy(cy), .frame_width(frame_width), .frame_height(frame_height), .rgb(rgb), .fdcemu_en(1'b1), .reset_n(reset_n & locked & video_locked),

        .sd_csn(sd_csn), .sd_clk(sd_clk), .sd_mosi(sd_mosi), .sd_miso(sd_miso),

        // .speaker(gpio[0]),

        .uart_rx_i(usb_rx),
        .uart_tx_o(usb_tx),

        // .uart_b_rx_i(uart_b_rx_i),
        // .uart_b_tx_o(uart_b_tx_o),

        .flash_spi_cs_n(flash_csn),
        .flash_spi_miso(flash_miso),
        .flash_spi_mosi(flash_mosi),
        .flash_spi_clk(flash_sck),
        .flash_spi_wp_n(flash_wpn),
        .flash_spi_hold_n(),

        .O_sdram_clk(sdram_clk),
        .O_sdram_cke(sdram_cke),
        .O_sdram_cs_n(sdram_csn),
        .O_sdram_cas_n(sdram_casn),
        .O_sdram_ras_n(sdram_rasn),
        .O_sdram_wen_n(sdram_wen),
        .IO_sdram_dq(sdram_dq),
        .O_sdram_addr(sdram_a),
        .O_sdram_ba(sdram_ba),
        .O_sdram_dqm(sdram_dqm)
        );

endmodule
