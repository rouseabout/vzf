module membram2 #(
    parameter ADDR_WIDTH = 14,
    parameter MEM_HEX = "",
    parameter MEM_INIT = 0
) (
    input clk,
    input reset_n,
    output reg [7:0] data_out,
    input[7:0] data_in,
    input cs_n,
    input rd_n,
    input wr_n,
    input[ADDR_WIDTH-1:0] addr
);

    wire read_sel = !cs_n & !rd_n & wr_n;
    wire write_sel = !cs_n & rd_n & !wr_n;

    reg [7:0] mem_8 [(1 << ADDR_WIDTH)-1 : 0];
    initial begin
        if( MEM_INIT > 0 ) begin
            $readmemh(MEM_HEX, mem_8, 0, (1 << ADDR_WIDTH)-1);
        end
    end

    always @(posedge clk)
    begin
        if (write_sel) begin
            mem_8[addr] <= data_in;
        end
        if (read_sel) begin
            data_out <= mem_8[addr];
        end
    end

endmodule
