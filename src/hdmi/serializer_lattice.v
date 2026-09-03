module serializer (
	clk_pixel,
	clk_pixel_x5,
	reset,
	tmds_internal,
	tmds,
	tmds_clock
);
	parameter signed [31:0] NUM_CHANNELS = 3;
	parameter signed [31:0] VIDEO_RATE = 32000000;
	input wire clk_pixel;
	input wire clk_pixel_x5;
	input wire reset;
	input wire [(NUM_CHANNELS * 10) - 1:0] tmds_internal;
	output wire [2:0] tmds;
	output wire tmds_clock;
	reg [2:0] bit_cnt;
	always @(posedge clk_pixel_x5)
		if (reset)
			bit_cnt <= 3'd0;
		else
			bit_cnt <= (bit_cnt == 3'd4 ? 3'd0 : bit_cnt + 3'd1);
	genvar _gv_i_1;
	generate
		for (_gv_i_1 = 0; _gv_i_1 < NUM_CHANNELS; _gv_i_1 = _gv_i_1 + 1) begin : g_ser
			localparam i = _gv_i_1;
			reg [9:0] shift;
			always @(posedge clk_pixel_x5)
				if (reset)
					shift <= 10'b0000000000;
				else if (bit_cnt == 3'd4)
					shift <= tmds_internal[i * 10+:10];
				else
					shift <= {2'b00, shift[9:2]};
			ODDRX1F u_oddr(
				.Q(tmds[i]),
				.D0(shift[0]),
				.D1(shift[1]),
				.SCLK(clk_pixel_x5),
				.RST(reset)
			);
		end
	endgenerate
	reg [9:0] clk_shift;
	always @(posedge clk_pixel_x5)
		if (reset)
			clk_shift <= 10'b0000000000;
		else if (bit_cnt == 3'd4)
			clk_shift <= 10'b0000011111;
		else
			clk_shift <= {2'b00, clk_shift[9:2]};
	ODDRX1F u_clk(
		.Q(tmds_clock),
		.D0(clk_shift[0]),
		.D1(clk_shift[1]),
		.SCLK(clk_pixel_x5),
		.RST(reset)
	);
endmodule
