`include "config.vh"

module memdp (douta, doutb, clka, ocea, cea, reseta, wrea, clkb, oceb, ceb, resetb, wreb, ada, dina, adb, dinb);
parameter ADDR_WIDTH = 10;

`ifdef GOWIN
output [7:0] douta;
output [7:0] doutb;
`else
output reg [7:0] douta;
output reg [7:0] doutb;
`endif
input clka;
input ocea;
input cea;
input reseta;
input wrea;
input clkb;
input oceb;
input ceb;
input resetb;
input wreb;
input [ADDR_WIDTH-1:0] ada;
input [7:0] dina;
input [ADDR_WIDTH-1:0] adb;
input [7:0] dinb;

`ifdef GOWIN
wire [7:0] dpb_inst_0_douta_w;
wire [7:0] dpb_inst_0_doutb_w;
wire gw_gnd;

assign gw_gnd = 1'b0;

DPB dpb_inst_0 (
    .DOA({dpb_inst_0_douta_w[7:0],douta[7:0]}),
    .DOB({dpb_inst_0_doutb_w[7:0],doutb[7:0]}),
    .CLKA(clka),
    .OCEA(ocea),
    .CEA(cea),
    .RESETA(reseta),
    .WREA(wrea),
    .CLKB(clkb),
    .OCEB(oceb),
    .CEB(ceb),
    .RESETB(resetb),
    .WREB(wreb),
    .BLKSELA({gw_gnd,gw_gnd,gw_gnd}),
    .BLKSELB({gw_gnd,gw_gnd,gw_gnd}),
    .ADA({gw_gnd,ada[ADDR_WIDTH-1:0],gw_gnd,gw_gnd,gw_gnd}),
    .DIA({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,dina[7:0]}),
    .ADB({gw_gnd,adb[ADDR_WIDTH-1:0],gw_gnd,gw_gnd,gw_gnd}),
    .DIB({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,dinb[7:0]})
);

defparam dpb_inst_0.READ_MODE0 = 1'b0;
defparam dpb_inst_0.READ_MODE1 = 1'b0;
defparam dpb_inst_0.WRITE_MODE0 = 2'b00;
defparam dpb_inst_0.WRITE_MODE1 = 2'b00;
defparam dpb_inst_0.BIT_WIDTH_0 = 8;
defparam dpb_inst_0.BIT_WIDTH_1 = 8;
defparam dpb_inst_0.BLK_SEL_0 = 3'b000;
defparam dpb_inst_0.BLK_SEL_1 = 3'b000;
defparam dpb_inst_0.RESET_MODE = "SYNC";
`else
    /* https://github.com/YosysHQ/yosys/issues/3400 */
    (* ram_style = "block" *) (* no_rw_check *) reg [7:0] mem_8 [0:(1 << ADDR_WIDTH)-1];

`define PORT(x, trace) \
    /*wire read``x  = ce``x &  oce``x & ~wre``x;*/ \
    wire write``x = ce``x & ~oce``x &  wre``x; \
    always @(posedge clk``x) \
    begin \
        if (write``x) begin \
            mem_8[ad``x] <= din``x; \
        end \
	/*if (read``x) begin*/ \
            dout``x <= mem_8[ad``x]; \
        /*end*/ \
    end

    `PORT(a, 0)
    `PORT(b, 0)
`endif //GOWIN

endmodule
