module memdp_32_8_flat #(
    parameter ADDR_WIDTH = 12
) (
    input clka,
    input reseta,
    input cea,
    input [3:0] wstrba,
    output reg [31:0] douta,
    input [31:0] dina,
    input [ADDR_WIDTH-3:0] ada,

    input clkb,
    input resetb,
    input ceb,
    input wreb,
    output [7:0] doutb,
    input [7:0] dinb,
    input [ADDR_WIDTH-1:0] adb
);

(* ram_style = "block" *) reg [31:0] combined_mem [0:(1 << (ADDR_WIDTH-2))-1];

always @(posedge clka) begin
    if (cea) begin
        if (wstrba[0]) combined_mem[ada[ADDR_WIDTH-3:0]][7:0]   <= dina[7:0];
        if (wstrba[1]) combined_mem[ada[ADDR_WIDTH-3:0]][15:8]  <= dina[15:8];
        if (wstrba[2]) combined_mem[ada[ADDR_WIDTH-3:0]][23:16] <= dina[23:16];
        if (wstrba[3]) combined_mem[ada[ADDR_WIDTH-3:0]][31:24] <= dina[ 31:24];
        douta <= combined_mem[ada[ADDR_WIDTH-3:0]];
    end
end

reg [31:0] raw_doutb;
always @(posedge clkb) begin
    if (ceb) begin
        if (wreb) begin
            combined_mem[adb[ADDR_WIDTH-1:2]] <= dinb;
        end
        raw_doutb <= combined_mem[adb[ADDR_WIDTH-1:2]];
    end
end

assign doutb = (adb[1:0] == 2'b00) ? raw_doutb[7:0]   :
               (adb[1:0] == 2'b01) ? raw_doutb[15:8]  :
               (adb[1:0] == 2'b10) ? raw_doutb[23:16] :
                                     raw_doutb[31:24];

endmodule
