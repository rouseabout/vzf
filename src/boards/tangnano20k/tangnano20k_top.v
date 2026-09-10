//`define CONFIG_ELVDS

module tangnano20k_top
(
    input clk27_i,
    input button_s2_i,
    input button_s1_i,
    input uart_rx_i,
    input uart_b_rx_i,
    output uart_tx_o,
    output uart_b_tx_o,
    output [5:0] leds,
    output ws2812_o,
    output sdclk,
    output tmds_clk_p,
    output tmds_clk_n,
    output [2:0] tmds_d_p,
    output [2:0] tmds_d_n,
    inout sdcmd,
    inout [3:0] sddat,
    inout usb_dp,
    inout usb_dm,
    inout [12:0] gpio,
    output HP_BCK,
    output HP_WS,
    output HP_DIN,
    output PA_EN,

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
    inout wire [31:0] IO_sdram_dq,
    output wire [10:0] O_sdram_addr,
    output wire [1:0] O_sdram_ba,
    output wire [3:0] O_sdram_dqm
);
    localparam CLK_PIXEL_FREQ = 28_500_000;

    wire reset_n;
    assign reset_n = ~button_s1_i;
    assign leds[5] = 0;

    // clocks
    wire clk_3_5625;
    wire clk_60;
    wire clk_60p;
    wire locked;
    wire clk_tmds;
    wire clk_pixel_x5;
    wire clk_pixel;
    wire video_locked;

    clocks clocks(
        .reset_n(reset_n),
        .clk_27(clk27_i),
        .clk_3_5625(clk_3_5625),
        .clk_60(clk_60),
        .clk_60p(clk_60p),
        .locked(locked),

        .clk_pixel_x5(clk_pixel_x5),
        .clk_pixel(clk_pixel),
        .video_locked(video_locked)
        );

    wire speaker;
    assign gpio[0] = speaker;
    wire [15:0] audio_left = speaker ? 16'h0fff : 16'h0000;
    wire [15:0] audio_right = audio_left;

    // audio/video out
    reg clk_audio;
    reg [8:0] aclk_cnt;
    reg [15:0] audio_reg [2];

    always @(posedge clk_pixel) begin
        if (aclk_cnt < CLK_PIXEL_FREQ / 48000 / 2 -1)
            aclk_cnt <= aclk_cnt + 9'd1;
        else begin
            aclk_cnt <= 9'd0;
            clk_audio <= ~clk_audio;
            // Convert signed two's complement → offset binary:
            // flip sign bit (bit 14).  Bit 15 = 0 (15-bit audio in 16-bit slot).
            audio_reg[0] <= {1'b0, ~audio_left[14],  audio_left[13:0]};
            audio_reg[1] <= {1'b0, ~audio_right[14], audio_right[13:0]};
        end
    end

    wire [2:0] tmds;
    wire tmds_clock;

    wire pal_mode;
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
        .clk_audio(clk_audio),
        .audio_sample_word_0(audio_reg[0]),
        .audio_sample_word_1(audio_reg[1]),
        .tmds(tmds),
        .tmds_clock(tmds_clock),

        .pal_mode(pal_mode),
        .short_frame(1'b0),
        .screen(2'd0),
        .interlace(1'b0),
        .reset(1'b0),

        .cx(cx),
        .cy(cy),
        .frame_width(frame_width),
        .frame_height(frame_height),
        .rgb(rgb)
        );

`ifdef CONFIG_ELVDS
    ELVDS_OBUF tmds_bufds [3:0] (
        .I({tmds_clock, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
        );
`else
    TLVDS_OBUF tmds_bufds [3:0] (
        .I({tmds_clock, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
        );
`endif

    // keyboard/gamepad/joystick
    wire [1:0] usb_type;
    wire usb_report;
    wire connerr;
    wire [7:0] key_modifiers, key0, key1, key2, key3;
    wire game_l, game_r, game_u, game_d, game_a, game_b;
    wire usb_dm_i, usb_dp_i;
    wire usb_dm_o, usb_dp_o;
    wire usb_oe;
    wire [9:0] rom_addr;
    wire [3:0] rom_dout;
    wire rom_en;

    usb_hid_host #(.FULL_SPEED(1)) usb_hid_host0 (
        .clk(clk_60),
        .reset(~reset_n | ~locked),
        .cs(1'b1),

        .usb_dm_i(usb_dm_i), .usb_dp_i(usb_dp_i),
        .usb_dm_o(usb_dm_o), .usb_dp_o(usb_dp_o),
        .usb_oe(usb_oe),

        .typ(usb_type),
        .full_report(usb_report),
        .connerr(connerr),
        .busy(),

        .key_modifiers(key_modifiers),
        .key_0(key0),
        .key_1(key1),
        .key_2(key2),
        .key_3(key3),
        .key_4(),
        .key_5(),

        .mouse_btn(),
        .mouse_dx(),
        .mouse_dy(),

        .game_l(game_l), .game_r(game_r), .game_u(game_u), .game_d(game_d),
        .game_a(game_a), .game_b(game_b), .game_x(), .game_y(),
        .game_sel(), .game_sta(),
        .game_extra(),

        .dbg_hid_report(),
        .dbg_hid_regs(),

        .rom_addr(rom_addr),
        .rom_dout(rom_dout),
        .rom_en(rom_en)
        );

    usb_hid_host_rom rom(
        .clk(clk_60),
        .addr(rom_addr),
        .dout(rom_dout),
        .en(rom_en)
        );

    assign usb_dm_i = usb_dm;
    assign usb_dp_i = usb_dp;
    assign usb_dm = usb_oe ? usb_dm_o : 1'bZ;
    assign usb_dp = usb_oe ? usb_dp_o : 1'bZ;

    // blink whenever there's a usb report
    reg report_toggle;
    always @(posedge clk_60) if (usb_report) report_toggle <= ~report_toggle;
    assign leds[4] = report_toggle;
    assign leds[3] = ~connerr;

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
            if (usb_report) begin
                if (usb_type == 2'd1) begin
                    key_modifiers_w <= key_modifiers;
                    key0_w <= key0;
                    key1_w <= key1;
                    key2_w <= key2;
                    key3_w <= key3;
                end else if (usb_type == 2'd3) begin
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

    top #(.LEFT_EDGE(104), .TOP_EDGE(96)) top(
        .clk_pixel(clk_pixel), .clk_sdram(clk_60), .clk_sdramp(clk_60p),
        .key_modifiers(key_modifiers_r), .key0(key0_r), .key1(key1_r), .key2(key2_r), .key3(key3_r),
        .game_l(game_l_r), .game_r(game_r_r), .game_u(game_u_r), .game_d(game_d_r), .game_a(game_a_r), .game_b(game_b_r),
        .pal_mode(pal_mode),
        .cx(cx), .cy(cy), .frame_width(frame_width), .frame_height(frame_height), .rgb(rgb), .fdcemu_en(1'b1), .reset_n(reset_n & locked & video_locked),
        .sd_clk(sdclk), .sd_mosi(sdcmd), .sd_miso(sddat[0]), .sd_csn(sddat[3]),

        .speaker(speaker),

        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o),

        .uart_b_rx_i(uart_b_rx_i),
        .uart_b_tx_o(uart_b_tx_o),

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

endmodule
