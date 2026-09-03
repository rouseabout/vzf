module uart_rx #(
    parameter int CLK_FREQ     = 27_000_000,
    parameter int BAUD       = 115200
)(
    input  wire      clk,
    input  wire      reset_n,
    input  wire      uart_rx,
    output reg [7:0] rx_byte,
    output reg       rx_strobe
);

    localparam int DIV      = CLK_FREQ / BAUD;

    reg rx_m, rx_s;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) {rx_s, rx_m} <= 2'b11;     // idle line is high
        else          {rx_s, rx_m} <= {rx_m, uart_rx};
    end


    reg [3:0]  rx_state;
    reg [16:0] rx_divcnt;
    reg [7:0]  rx_pattern;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rx_state   <= 4'd0;
            rx_divcnt  <= 17'd0;
            rx_pattern <= 8'd0;
            rx_byte    <= 8'd0;
            rx_strobe  <= 1'b0;
        end else begin
            rx_divcnt <= rx_divcnt + 17'd1;
            rx_strobe <= 1'b0;
            case (rx_state)
                4'd0: begin                              // idle, look for start bit
                    if (!rx_s) rx_state <= 4'd1;
                    rx_divcnt <= 17'd0;
                end
                4'd1: begin                              // center on first data bit
                    if ({rx_divcnt, 1'b0} > DIV) begin   // 2*divcnt > DIV  → divcnt > DIV/2
                        rx_state  <= 4'd2;
                        rx_divcnt <= 17'd0;
                    end
                end
                4'd10: begin                             // stop bit → latch
                    if (rx_divcnt > DIV) begin
                        rx_byte   <= rx_pattern;
                        rx_strobe <= 1'b1;
                        rx_state  <= 4'd0;
                    end
                end
                default: begin                           // states 2..9 sample data bits
                    if (rx_divcnt > DIV) begin
                        rx_pattern <= {rx_s, rx_pattern[7:1]};
                        rx_state   <= rx_state + 4'd1;
                        rx_divcnt  <= 17'd0;
                    end
                end
            endcase
        end
    end

endmodule
