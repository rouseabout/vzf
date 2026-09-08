// Behavioral SD card model (SPI mode, mode 0, MSB first) — simulation only.
//
// Models just enough of the SD SPI protocol to bring up AruviOS's `sd.rs`:
//   CMD0  (0x40) GO_IDLE_STATE   -> R1 = 0x01 (idle)
//   CMD8  (0x48) SEND_IF_COND    -> R7: 01 00 00 01 AA  (SDv2, echoes 0x1AA)
//   CMD55 (0x77) APP_CMD         -> R1 = 0x01
//   CMD41 (0x69) ACMD41          -> R1 = 0x00 (ready — init completes at once)
//   CMD58 (0x7A) READ_OCR        -> R3: 00 C0 FF 80 00  (CCS=1 -> SDHC, block addr)
//   CMD17 (0x51) READ_SINGLE_BLK -> R1=0x00, token 0xFE, 512 data bytes, 2 CRC
// Any other command returns R1 = 0x05 (illegal). Card contents come from
// INIT_FILE ($readmemh, one hex byte per line); CMD17 reads block `arg` (SDHC
// block addressing) from mem[arg*512 ..].
//
// SPI timing (mode 0): sample MOSI on the rising edge, drive MISO on the falling
// edge — identical to spi_flash_model.v (which is verified against the master).

`timescale 1ns/1ps

module spi_sd_model #(
    parameter         INIT_FILE = "",
    parameter integer BLOCKS    = 8            // 8 * 512 B = 4 KB model
) (
    input  wire cs_n,
    input  wire sclk,
    input  wire mosi,
    output wire miso
);
    localparam integer SIZE = BLOCKS * 512;
    reg [7:0] mem [0:SIZE-1];
    integer   k;
    initial begin
        for (k = 0; k < SIZE; k = k + 1) mem[k] = 8'h00;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    // Response stream buffer (largest is CMD17: R1 + token + 512 + 2 CRC = 516).
    reg [7:0]  resp [0:519];
    integer    resp_len, resp_ptr;

    reg [7:0]  cmdbuf [0:5];
    integer    cmd_idx;
    reg        in_cmd;         // currently collecting a 6-byte command
    reg        in_cmd24;
    integer    cmd24_base;
    reg [2:0]  bitcnt;
    reg [7:0]  inbyte;
    reg [7:0]  outbyte;
    reg        miso_reg;

    assign miso = cs_n ? 1'b1 : miso_reg;   // idles high

    // CS deassert resets the transaction (but keeps card memory).
    always @(posedge cs_n) begin
        in_cmd   <= 1'b0;
        cmd_idx  <= 0;
        in_cmd24 <= 0;
        cmd24_base <= 0;
        bitcnt   <= 3'd0;
        resp_ptr <= 0;
        resp_len <= 0;
        outbyte  <= 8'hFF;
        miso_reg <= 1'b1;
    end

    // Sample MOSI on the rising edge; assemble bytes.
    always @(posedge sclk) begin
        if (!cs_n) begin
            inbyte <= {inbyte[6:0], mosi};
            if (bitcnt == 3'd7) begin
                bitcnt <= 3'd0;
                handle_byte({inbyte[6:0], mosi});
            end else begin
                bitcnt <= bitcnt + 3'd1;
            end
        end
    end

    // Drive the next MISO bit on the falling edge.
    always @(negedge sclk) begin
        if (!cs_n) begin
            miso_reg <= outbyte[7];
            outbyte  <= {outbyte[6:0], 1'b1};   // shift, filling with idle-high
        end
    end

    // Consume a completed MOSI byte, advance the command/response state, and
    // preload `outbyte` for the byte the host will clock next.
    task handle_byte(input [7:0] b);
        begin
            if (in_cmd) begin
                cmdbuf[cmd_idx] = b;
                if (cmd_idx == 5) begin
                    decode_command();
                    in_cmd  = 1'b0;
                    outbyte = resp[0];      // R1 appears on the next byte
                    resp_ptr = 1;
                end else begin
                    cmd_idx = cmd_idx + 1;
                    outbyte = 8'hFF;
                end
            end else if (resp_ptr < resp_len) begin
                if (in_cmd24) begin
                    if (resp_ptr >= 3 && resp_ptr < 3+512) begin
                        mem[cmd24_base + resp_ptr - 3] = b;
                    end
                end
                outbyte  = resp[resp_ptr]; // keep streaming the response
                resp_ptr = resp_ptr + 1;
            end else if (b[7:6] == 2'b01) begin
                cmdbuf[0] = b;             // start of a new 6-byte command
                cmd_idx   = 1;
                in_cmd    = 1'b1;
                in_cmd24  = 0;
                outbyte   = 8'hFF;
            end else begin
                outbyte = 8'hFF;
            end
        end
    endtask

    integer i;
    task decode_command;
        reg [5:0]  cmd;
        reg [31:0] arg;
        integer    base;
        begin
            cmd = cmdbuf[0][5:0];
            arg = {cmdbuf[1], cmdbuf[2], cmdbuf[3], cmdbuf[4]};
            resp_ptr = 0;
            case (cmd)
                6'd0:  begin resp[0]=8'h01; resp_len=1; end                     // CMD0
                6'd8:  begin resp[0]=8'h01; resp[1]=8'h00; resp[2]=8'h00;       // CMD8 R7
                             resp[3]=8'h01; resp[4]=8'hAA; resp_len=5; end
                6'd55: begin resp[0]=8'h01; resp_len=1; end                     // CMD55
                6'd41: begin resp[0]=8'h00; resp_len=1; end                     // ACMD41
                6'd58: begin resp[0]=8'h00; resp[1]=8'hC0; resp[2]=8'hFF;       // CMD58 R3
                             resp[3]=8'h80; resp[4]=8'h00; resp_len=5; end
                6'd17: begin                                                    // CMD17
                    resp[0] = 8'h00;       // R1 ok
                    resp[1] = 8'hFE;       // data start token
                    base = (arg % BLOCKS) * 512;
                    for (i = 0; i < 512; i = i + 1) resp[2+i] = mem[base + i];
                    resp[514] = 8'h00;     // CRC (ignored in SPI mode)
                    resp[515] = 8'h00;
                    resp_len = 516;
                end
                6'd24: begin                                                    // CMD24
                    in_cmd24 = 1;
                    cmd24_base = (arg % BLOCKS) * 512;
                    resp[516] = 8'h05;
                    resp_len = 517;
                end
                default: begin resp[0]=8'h05; resp_len=1; end                   // illegal
            endcase
        end
    endtask
endmodule
