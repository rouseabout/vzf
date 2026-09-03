module clocks (
    input reset_n,
    input clk_27,

    output clk_3_5625,
    output clk_60,
    output clk_60p,
    output locked,

    output clk_pixel_x5,
    output clk_pixel,
    output video_locked
);

    rPLL #(
        .FCLKIN("27.0"),
        .DEVICE("GW2AR-18C"),
        .IDIV_SEL(8),
        .FBDIV_SEL(19),
        .ODIV_SEL(16),
        .PSDA_SEL("1010") //225 degrees
    ) pll_60 (
        .CLKIN(clk_27),
        .CLKFB(1'b0),
        .RESET(~reset_n),
        .RESET_P(1'b0),
        .IDSEL(6'b0),
        .FBDSEL(6'b0),
        .ODSEL(6'b0),
        .PSDA(4'b0),
        .DUTYDA(4'b0),
        .FDLY(4'b0),
        .CLKOUT(clk_60),
        .CLKOUTP(clk_60p),
        .CLKOUTD(),
        .CLKOUTD3(),
        .LOCK(locked)
    );

    rPLL #(
        .FCLKIN("60.0"),
        .DEVICE("GW2AR-18C"),
        .IDIV_SEL(7),
        .FBDIV_SEL(18),
        .ODIV_SEL(8),
        .DYN_SDIV_SEL(40)
    ) pll_142_5 (
        .CLKIN(clk_60),
        .CLKFB(1'b0),
        .RESET(~locked),
        .RESET_P(1'b0),
        .IDSEL(6'b0),
        .FBDSEL(6'b0),
        .ODSEL(6'b0),
        .PSDA(4'b0),
        .DUTYDA(4'b0),
        .FDLY(4'b0),
        .CLKOUT(clk_pixel_x5),
        .CLKOUTP(),
        .CLKOUTD(clk_3_5625),
        .CLKOUTD3(),
        .LOCK(video_locked)
    );

    CLKDIV #(
        .DIV_MODE("5"),
        .GSREN("false")
    ) clkdiv_inst (
        .CLKOUT(clk_pixel),
        .HCLKIN(clk_pixel_x5),
        .RESETN(video_locked),
        .CALIB(1'b0)
    );

endmodule
