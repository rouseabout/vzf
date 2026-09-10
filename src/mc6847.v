module mc6847
#(
    parameter int LEFT_EDGE = 10'd104,
    parameter int TOP_EDGE = 10'd96
)
(
    input clk,
    input reset_n,
    input pal_mode,
    output rd,
    output [10:0] addr,
    input [7:0] di,
    output status2,
    output [4:0] addr_status,
    input [7:0] di_status,
    input show_status,
    input ag,
    input css,
    input bw, /* black & white mode */
    input [10:0] cx,
    input [9:0] cy,
    input [10:0] frame_width,
    input [9:0] frame_height,
    output reg vsync,
    output reg [23:0] rgb
);

    wire [9:0] screen_width      = 720;
    wire [9:0] hsync_pulse_start = 24;
    wire [9:0] hsync_pulse_size  = 72;
    wire [9:0] screen_height     = pal_mode ? (48 + 48 + 384 + 48) : (48 + 384 + 48);
    wire [9:0] vsync_pulse_start = 0;
    wire [9:0] vsync_pulse_size  = 12;

    always @(*) begin
        if (cy == screen_height + vsync_pulse_start - 1)
            vsync <= ~(cx >= screen_width + hsync_pulse_start);
        else if (cy == screen_height + vsync_pulse_start + vsync_pulse_size - 1)
            vsync <= ~(cx < screen_width + hsync_pulse_start);
        else
            vsync <= ~(cy >= screen_height + vsync_pulse_start && cy < screen_height + vsync_pulse_start + vsync_pulse_size);
    end

    reg [6:0] cy6; // cy / 6
    reg [2:0] cy6_frac;
    reg [4:0] cy24;
    reg [4:0] cy24_frac; // cy % 24

    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            cy6 <= 7'd0;
            cy6_frac <= 3'd0;
            cy24 <= 5'd0;
            cy24_frac <= 5'd0;
        end else begin
            if (cx == frame_width-1'b1 & cy == frame_height-1'b1) begin
                cy6 <= 7'd0;
                cy6_frac <= 3'd0;
                cy24 <= 5'd0;
                cy24_frac <= 5'd0;
            end else begin
                if (cx == frame_width-1'b1) begin
                    cy6_frac <= cy6_frac + 1'b1;
                    if (cy6_frac == 6-1) begin
                        cy6_frac <= 0;
                        cy6 <= cy6 + 1'b1;
                    end else begin
                        cy6_frac <= cy6_frac + 1'b1;
                    end
                    cy24_frac <= cy24_frac + 1'b1;
                    if (cy24_frac == 24-1) begin
                        cy24_frac <= 0;
                        cy24 <= cy24 + 1'b1;
                    end else begin
                        cy24_frac <= cy24_frac + 1'b1;
                    end
                end
            end
        end
    end

    reg [0:0] rom[80*8*16:0];

    initial begin
        $readmemh("charrom.hex", rom);
    end

    wire [6:0] top_edge = pal_mode ? TOP_EDGE : TOP_EDGE / 2;

    wire [10:0] lx = 11'(cx - LEFT_EDGE);
    wire [6:0] ly6 = cy6 - (pal_mode ? TOP_EDGE/6 : TOP_EDGE/6/2);
    wire visible_x = (cx >= LEFT_EDGE) & (cx < LEFT_EDGE + 512);
    wire visible_y = (cy >= 10'(top_edge))  & (cy < 10'(top_edge) + 384);
    wire status_y1 = (cy >= 10'(top_edge) - 48) & (cy < 10'(top_edge) - 24);
    wire status_y2 = (cy >= 10'(top_edge) + 384 + 24) & (cy < 10'(top_edge) + 384 + 48);
    wire status_y = show_status && (status_y1 | status_y2);

    assign rd = visible_x & visible_y;

    assign addr = 11'(char_row * 32 + char_column);
    wire [10:0] char_column = lx / 16;
    wire [9:0] char_row    = ag ? ly6 : ly6[5:2]; // cy divided by 6 or 24

    assign status2 = status_y2;
    assign addr_status = char_column;

    // text/character mode and status bar

    wire [2:0] g_x = lx[3:1];
    wire [3:0] g_y = cy24_frac >> 1;

    wire [3:0] txtbcolor = (status_y || bw) ?  8 /* black */ : 9; /* dark green */
    wire [3:0] txtfcolor = (status_y || bw) ?  4 /* buff */  : css ? 10 /* bright orange */ : 0 /* green */;

    wire [7:0] di2 = status_y ? di_status : di;

    wire [3:0] forecolor = (di2 < 64) ? txtfcolor : (di2 < 128) ? txtbcolor   : 4'((di2-8'd128)>>4);
    wire [3:0] backcolor = (di2 < 64) ? txtbcolor : (di2 < 128) ? txtfcolor   : txtbcolor;
    wire [7:0] ch        = (di2 < 64) ? di2       : (di2 < 128) ? di2 - 8'd64 : di2 - (8'd64 + 8'd16*forecolor);

    reg char_pixel;
    reg [3:0] forecolor1, backcolor1;

    always @(posedge clk) begin
        char_pixel <= rom[14'(ch << 7) + 14'(g_y << 3) + 14'(g_x)];
        forecolor1 <= forecolor; // rom lookup incurs 1 pixel delay, so also delay foreground/background colors
        backcolor1 <= backcolor;
    end

    wire [3:0] char_pixel_color = char_pixel ? forecolor1 : backcolor1;

    // graphics mode

    wire [1:0] g2_x = lx[3:2];

    wire [3:0] graph_background_color = (4'(css)<<2);
    reg [3:0] graph_pixel_color;
    always @(posedge clk) begin // match text/character mode delay
        graph_pixel_color <= 4'(2'(di >> 2*(3 - g2_x))) + graph_background_color;
    end

    // output

    wire [3:0] bordercolor = (ag && !(visible_x & status_y)) ? graph_background_color : 8 /* black */;
    wire [3:0] pixel_color = (ag && !(visible_x & status_y)) ? graph_pixel_color      : char_pixel_color;

    function [23:0] pal_to_rgb;
        input [3:0] pal;
        begin
            case(pal)
            4'd0: pal_to_rgb = 24'h00ff00; // GREEN
            4'd1: pal_to_rgb = 24'hffff00; // YELLOW
            4'd2: pal_to_rgb = 24'h0000ff; // BLUE
            4'd3: pal_to_rgb = 24'hff0000; // RED
            4'd4: pal_to_rgb = 24'hffffff; // BUFF
            4'd5: pal_to_rgb = 24'h00ffff; // CYAN
            4'd6: pal_to_rgb = 24'hff00ff; // MAGENTA
            4'd7: pal_to_rgb = 24'hff8000; // ORANGE
            4'd8: pal_to_rgb = 24'h000000; // BLACK
            4'd9: pal_to_rgb = 24'h004000; // DARK GREEN
            4'd10: pal_to_rgb = 24'hffc418; // BRIGHT ORANGE
            endcase
        end
    endfunction

    wire [9:0] cx1 = 10'(cx - 1); // compensate for pixel delay
    wire visible_x1 = (cx1 >= LEFT_EDGE) & (cx1 < LEFT_EDGE + 512);

    always @(posedge clk) begin
        if (~reset_n) begin
            rgb <= 24'h000000;
        end else if (visible_x1 & (visible_y || status_y)) begin
            rgb <= pal_to_rgb(pixel_color);
        end else if (pal_mode & (cy < 48 | cy >= 48 + 48 + 384 + 48)) begin
            rgb <= 24'h000000;
        end else begin
            rgb <= (cx < screen_width) & (cy < screen_height) ? pal_to_rgb(bordercolor) : 24'h000000;
        end
    end
endmodule
