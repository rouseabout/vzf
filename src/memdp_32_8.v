module memdp_32_8 #(
    parameter ADDR_WIDTH = 12
) (
    input clka,
    input reseta,
    input cea,
    input [3:0] wstrba,
    output [31:0] douta,
    input [31:0] dina,
    input [ADDR_WIDTH-3:0] ada,

    input clkb,
    input resetb,
    input ceb,
    input oceb,
    input wreb,
    output [7:0] doutb,
    input [7:0] dinb,
    input [ADDR_WIDTH-1:0] adb
);

    wire [7:0] doutb_0, doutb_1, doutb_2, doutb_3;
    assign doutb =
        adb[1:0]==2'b00 ? doutb_0 :
        adb[1:0]==2'b01 ? doutb_1 :
        adb[1:0]==2'b10 ? doutb_2 :
                          doutb_3 ;

`define BANK(idx) \
    memdp #(.ADDR_WIDTH(ADDR_WIDTH-2)) bank_``idx ( \
        .clka(clka), \
        .reseta(reseta), \
        .cea(cea), \
        .ocea(wstrba==4'b000), \
        .wrea(wstrba[idx]), \
        .douta(douta[(idx + 1)*8-1: idx * 8]), \
        .dina(dina[(idx + 1)*8-1: idx * 8]), \
        .ada(ada[ADDR_WIDTH-3:0]), \
        \
        .clkb(clkb), \
        .resetb(resetb), \
        .ceb(ceb & adb[1:0]==idx), \
        .oceb(oceb), \
        .wreb(wreb), \
        .doutb(doutb_``idx), \
        .dinb(dinb), \
        .adb(adb[ADDR_WIDTH-1:2]) \
    );

    `BANK(0)
    `BANK(1)
    `BANK(2)
    `BANK(3)

endmodule
