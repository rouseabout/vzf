module timer_22050 (
    input  wire clk,
    input  wire rst_n,
    output reg  pulse
);
    reg [31:0] accumulator;
    localparam [31:0] TUNING_WORD = 32'd3322948; /* =22050*POWER(2,32)/28500000 */

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= 32'd0;
            pulse       <= 1'b0;
        end else begin
            {pulse, accumulator} <= accumulator + TUNING_WORD;
        end
    end
endmodule
