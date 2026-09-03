module hdmi (
	clk_pixel_x5,
	clk_pixel,
	clk_audio,
	pal_mode,
	screen,
	short_frame,
	interlace,
	reset,
	rgb,
	audio_sample_word,
	vsync,
	cx,
	cy,
	frame_width,
	frame_height,
	tmds,
	tmds_clock
);
	reg _sv2v_0;
	parameter [0:0] IT_CONTENT = 1'b1;
	parameter [0:0] DVI_OUTPUT = 1'b0;
	parameter signed [31:0] AUDIO_RATE = 44100;
	parameter signed [31:0] AUDIO_BIT_WIDTH = 16;
	parameter [63:0] VENDOR_NAME = {"Unknown", 8'd0};
	parameter [127:0] PRODUCT_DESCRIPTION = {"FPGA", 96'd0};
	parameter [7:0] SOURCE_DEVICE_INFORMATION = 8'h00;
	input wire clk_pixel_x5;
	input wire clk_pixel;
	input wire clk_audio;
	input wire pal_mode;
	input wire [1:0] screen;
	input wire short_frame;
	input wire interlace;
	input wire reset;
	input wire [23:0] rgb;
	input wire [(2 * AUDIO_BIT_WIDTH) - 1:0] audio_sample_word;
	output reg vsync;
	output reg [10:0] cx;
	output reg [9:0] cy;
	output wire [10:0] frame_width;
	output wire [9:0] frame_height;
	output wire [2:0] tmds;
	output wire tmds_clock;
	localparam signed [31:0] NUM_CHANNELS = 3;
	reg hsync;
	wire [1:0] invert;
	wire [54:0] htiming0n = 55'h000718b400c048;
	wire [54:0] htiming0o = 55'h000718c000c048;
	wire [54:0] htiming0w = 55'h000718d000c030;
	wire [39:0] vtiming0 = 40'h9ca4001405;
	wire [39:0] vtiming1 = 40'h839e001405;
	wire [7:0] cea0 = 8'd17;
	wire [7:0] cea1 = 8'd2;
	wire [54:0] htiming0 = (screen == 2'd2 ? htiming0w : (screen == 2'd1 ? htiming0o : htiming0n));
	wire [102:0] timing = (pal_mode ? {htiming0, vtiming0, cea0} : {htiming0, vtiming1, cea1});
	wire [10:0] start_x = timing[102:92];
	assign frame_width = timing[91:81];
	wire [10:0] screen_width = timing[80:70];
	wire [10:0] hsync_pulse_start = timing[69:59];
	wire [10:0] hsync_pulse_size = timing[58:48];
	assign frame_height = (timing[47:38] - (short_frame ? 10'd2 : 10'd0)) - (interlace ? 10'd1 : 10'd0);
	wire [9:0] screen_height = timing[37:28];
	wire [9:0] vsync_pulse_start = timing[27:18];
	wire [9:0] vsync_pulse_size = timing[17:8];
	wire [7:0] cea = timing[7:0];
	assign invert = 2'b11;
	always @(*) begin
		if (_sv2v_0)
			;
		hsync <= invert[0] ^ ((cx >= (screen_width + hsync_pulse_start)) && (cx < ((screen_width + hsync_pulse_start) + hsync_pulse_size)));
		if (cy == ((screen_height + vsync_pulse_start) - 1))
			vsync <= invert[1] ^ (cx >= (screen_width + hsync_pulse_start));
		else if (cy == (((screen_height + vsync_pulse_start) + vsync_pulse_size) - 1))
			vsync <= invert[1] ^ (cx < (screen_width + hsync_pulse_start));
		else
			vsync <= invert[1] ^ ((cy >= (screen_height + vsync_pulse_start)) && (cy < ((screen_height + vsync_pulse_start) + vsync_pulse_size)));
	end
	localparam real VIDEO_RATE = 32E6;
	always @(posedge clk_pixel)
		if (reset) begin
			cx <= start_x;
			cy <= 10'd0;
		end
		else begin
			cx <= (cx == (frame_width - 1'b1) ? 11'd0 : cx + 1'b1);
			cy <= (cx == (frame_width - 1'b1) ? (cy == (frame_height - 1'b1) ? 10'd0 : cy + 1'b1) : cy);
		end
	reg video_data_period = 0;
	always @(posedge clk_pixel)
		if (reset)
			video_data_period <= 0;
		else
			video_data_period <= (cx < screen_width) && (cy < screen_height);
	reg [2:0] mode = 3'd1;
	reg [23:0] video_data = 24'd0;
	reg [5:0] control_data = 6'd0;
	reg [11:0] data_island_data = 12'd0;
	function automatic signed [4:0] sv2v_cast_5_signed;
		input reg signed [4:0] inp;
		sv2v_cast_5_signed = inp;
	endfunction
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	generate
		if (!DVI_OUTPUT) begin : true_hdmi_output
			reg video_guard = 1;
			reg video_preamble = 0;
			always @(posedge clk_pixel)
				if (reset) begin
					video_guard <= 1;
					video_preamble <= 0;
				end
				else begin
					video_guard <= ((cx >= (frame_width - 2)) && (cx < frame_width)) && ((cy == (frame_height - 1)) || (cy < (screen_height - 1)));
					video_preamble <= ((cx >= (frame_width - 10)) && (cx < (frame_width - 2))) && ((cy == (frame_height - 1)) || (cy < (screen_height - 1)));
				end
			reg signed [31:0] max_num_packets_alongside;
			reg [4:0] num_packets_alongside;
			always @(*) begin
				if (_sv2v_0)
					;
				max_num_packets_alongside = ((frame_width - screen_width) - 30) / 32;
				if (max_num_packets_alongside > 18)
					num_packets_alongside = 5'd18;
				else
					num_packets_alongside = sv2v_cast_5_signed(max_num_packets_alongside);
			end
			wire data_island_period_instantaneous;
			assign data_island_period_instantaneous = ((num_packets_alongside > 0) && (cx >= (screen_width + 14))) && (cx < ((screen_width + 14) + (num_packets_alongside * 32)));
			wire packet_enable;
			assign packet_enable = data_island_period_instantaneous && (sv2v_cast_5((cx + screen_width) + 18) == 5'd0);
			reg data_island_guard = 0;
			reg data_island_preamble = 0;
			reg data_island_period = 0;
			always @(posedge clk_pixel)
				if (reset) begin
					data_island_guard <= 0;
					data_island_preamble <= 0;
					data_island_period <= 0;
				end
				else begin
					data_island_guard <= (num_packets_alongside > 0) && (((cx >= (screen_width + 12)) && (cx < (screen_width + 14))) || ((cx >= ((screen_width + 14) + (num_packets_alongside * 32))) && (cx < (((screen_width + 14) + (num_packets_alongside * 32)) + 2))));
					data_island_preamble <= ((num_packets_alongside > 0) && (cx >= (screen_width + 4))) && (cx < (screen_width + 12));
					data_island_period <= data_island_period_instantaneous;
				end
			wire [23:0] header;
			wire [223:0] sub;
			wire video_field_end;
			assign video_field_end = (cx == (screen_width - 1'b1)) && (cy == (screen_height - 1'b1));
			wire [4:0] packet_pixel_counter;
			packet_picker #(
				.VIDEO_RATE(VIDEO_RATE),
				.IT_CONTENT(IT_CONTENT),
				.AUDIO_RATE(AUDIO_RATE),
				.AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
				.VENDOR_NAME(VENDOR_NAME),
				.PRODUCT_DESCRIPTION(PRODUCT_DESCRIPTION),
				.SOURCE_DEVICE_INFORMATION(SOURCE_DEVICE_INFORMATION)
			) packet_picker(
				.clk_pixel(clk_pixel),
				.clk_audio(clk_audio),
				.reset(reset),
				.cea(cea),
				.video_field_end(video_field_end),
				.packet_enable(packet_enable),
				.packet_pixel_counter(packet_pixel_counter),
				.audio_sample_word(audio_sample_word),
				.header(header),
				.sub(sub)
			);
			wire [8:0] packet_data;
			packet_assembler packet_assembler(
				.clk_pixel(clk_pixel),
				.reset(reset),
				.data_island_period(data_island_period),
				.header(header),
				.sub(sub),
				.packet_data(packet_data),
				.counter(packet_pixel_counter)
			);
			always @(posedge clk_pixel)
				if (reset) begin
					mode <= 3'd2;
					video_data <= 24'd0;
					control_data <= 6'd0;
					data_island_data <= 12'd0;
				end
				else begin
					mode <= (data_island_guard ? 3'd4 : (data_island_period ? 3'd3 : (video_guard ? 3'd2 : (video_data_period ? 3'd1 : 3'd0))));
					video_data <= rgb;
					control_data <= {1'b0, data_island_preamble, 1'b0, video_preamble || data_island_preamble, vsync, hsync};
					data_island_data[11:4] <= packet_data[8:1];
					data_island_data[3] <= cx != 0;
					data_island_data[2] <= packet_data[0];
					data_island_data[1:0] <= {vsync, hsync};
				end
		end
		else begin : genblk1
			always @(posedge clk_pixel)
				if (reset) begin
					mode <= 3'd0;
					video_data <= 24'd0;
					control_data <= 6'd0;
				end
				else begin
					mode <= (video_data_period ? 3'd1 : 3'd0);
					video_data <= rgb;
					control_data <= {4'b0000, vsync, hsync};
				end
		end
	endgenerate
	wire [29:0] tmds_internal;
	genvar _gv_i_5;
	generate
		for (_gv_i_5 = 0; _gv_i_5 < NUM_CHANNELS; _gv_i_5 = _gv_i_5 + 1) begin : tmds_gen
			localparam i = _gv_i_5;
			tmds_channel #(.CN(i)) tmds_channel(
				.clk_pixel(clk_pixel),
				.video_data(video_data[(i * 8) + 7:i * 8]),
				.data_island_data(data_island_data[(i * 4) + 3:i * 4]),
				.control_data(control_data[(i * 2) + 1:i * 2]),
				.mode(mode),
				.tmds(tmds_internal[i * 10+:10])
			);
		end
	endgenerate
	serializer #(.NUM_CHANNELS(NUM_CHANNELS)) serializer(
		.clk_pixel(clk_pixel),
		.clk_pixel_x5(clk_pixel_x5),
		.reset(reset),
		.tmds_internal(tmds_internal),
		.tmds(tmds),
		.tmds_clock(tmds_clock)
	);
	initial _sv2v_0 = 0;
endmodule
