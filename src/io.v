`include "config.vh"

`ifdef VERILATOR
`define CONFIG_SDCARD_SIM
`define CONFIG_SRAM
`else
`define CONFIG_SD
//`define CONFIG_SRAM
//`define SDRAM_START 32'h1000_0000
`define SDRAM_START 32'h0000_0000
`define CONFIG_SDRAM
`define CONFIG_SDRAM_LOAD
`endif

module io
#(
    parameter int SDRAM_DATA_WIDTH = 32,
    parameter int SDRAM_ADDR_WIDTH = 11
) (
    input clk,
    input clk_sdram,
    input clk_sdramp,
    input reset_n,

    input [7:0] key_modifiers,
    input [7:0] key0,

    input vsync,

    input vdg_rd,
    input [VRAM_WIDTH-1:0] vdg_addr,
    output [7:0] vdg_di,
    input [4:0] vdg_status_addr,
    output reg [7:0] vdg_status_data,

    input [10:0] mosi_seek, /* dirty(1), track_x2(8), drive(2) */
    output reg [1:0] miso_wprotect, /* wprotect(2) */
    input [11:0] fdc_shmem_addr,
    input fdc_shmem_rd,
    input fdc_shmem_wr,
    input [7:0] fdc_shmem_din,
    output wire [7:0] fdc_shmem_dout,

    input [8:0] cas_mem_addr,
    output wire [7:0] cas_mem_dout,

    output reg sd_csn,
    output sd_clk,
    output sd_mosi,
    input sd_miso,

    output flash_spi_cs_n,
    input flash_spi_miso,
    output flash_spi_mosi,
    output flash_spi_clk,
    output flash_spi_wp_n,
    output flash_spi_hold_n,

    output wire O_sdram_clk,
    output wire O_sdram_cke,
    output wire O_sdram_cs_n,
    output wire O_sdram_cas_n,
    output wire O_sdram_ras_n,
    output wire O_sdram_wen_n,
    inout wire [SDRAM_DATA_WIDTH-1:0] IO_sdram_dq,
    output wire [SDRAM_ADDR_WIDTH-1:0] O_sdram_addr,
    output wire [1:0] O_sdram_ba,
    output wire [(SDRAM_DATA_WIDTH/8)-1:0] O_sdram_dqm
);
    localparam integer SRAM_WIDTH = 15;
    localparam integer SRAM_BYTES = (1 << SRAM_WIDTH);

    localparam integer SDRAM_BYTES = 1048576;

    localparam integer VRAM_WIDTH = 9; /* 512 bytes */

    wire mem_valid;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [31:0] mem_rdata;
    wire [3:0] mem_wstrb;
    wire mem_ready;
    wire mem_instr;
    wire [31:0] eoi;

`ifdef CONFIG_SRAM
    wire cs_sram_n, sram_ready;
    wire [31:0] sram_data_o;
`endif

`ifdef CONFIG_SDRAM
    wire cs_sdram_n, sdram_ready;
    wire [31:0] sdram_data_o;
`endif

    wire cs_vram_n, vram_ready;
    wire [31:0] data_miso_vram_cpu;

    wire cs_spicntl_n, spicntl_ready;
    wire cs_spixfer_n, spixfer_ready;

    wire cs_kb_n, kb_ready;

    wire cs_ioseek_n, cs_iowrite_n;
    wire ioseek_ready, iowrite_ready;

    wire cs_shmem_n, shmem_ready;
    wire [31:0] shmem_data_o;

    wire cs_cas_n, cas_ready;
    wire [31:0] cas_data_o;

`ifdef CONFIG_SRAM
    assign cs_sram_n = ~(mem_valid && (mem_addr < SRAM_BYTES));
`endif
`ifdef CONFIG_SDRAM
    assign cs_sdram_n = ~(mem_valid && (mem_addr >= `SDRAM_START) && (mem_addr < `SDRAM_START + SDRAM_BYTES));
`endif
    assign cs_vram_n = ~(mem_valid && (mem_addr >= 32'h80000000) && (mem_addr < 32'h80000800));

    assign cs_spicntl_n = ~(mem_valid && mem_addr == 32'h90000000);
    assign cs_spixfer_n = ~(mem_valid && mem_addr == 32'h90000004);

    assign cs_kb_n = ~(mem_valid && mem_addr == 32'h90000020);

    assign cs_ioseek_n = ~(mem_valid && mem_addr == 32'h90000040);
    assign cs_iowrite_n = ~(mem_valid && mem_addr == 32'h90000048);

    assign cs_shmem_n = ~(mem_valid && (mem_addr >= 32'ha0000000 && mem_addr < 32'ha0001000));
    assign cs_cas_n = ~(mem_valid && (mem_addr >= 32'hb0000000 && mem_addr < 32'hb0000200));

    assign mem_ready = mem_valid & (0
`ifdef CONFIG_SRAM
        | sram_ready
`endif
`ifdef CONFIG_SDRAM
        | sdram_ready
`endif
        | vram_ready
        | spicntl_ready | spixfer_ready
        | kb_ready
        | ioseek_ready | iowrite_ready |
        | shmem_ready
        | cas_ready
        );

    assign mem_rdata =
`ifdef CONFIG_SRAM
        ~cs_sram_n ? sram_data_o :
`endif
`ifdef CONFIG_SDRAM
        ~cs_sdram_n ? sdram_data_o :
`endif
        ~cs_vram_n ? data_miso_vram_cpu :
        ~cs_spixfer_n ? {24'b0, sd_spi_rx_data_reg} :
        ~cs_kb_n ? kb_miso :
        ~cs_ioseek_n ? {21'b0,mosi_seek} :
        ~cs_shmem_n ? shmem_data_o :
        ~cs_cas_n ? cas_data_o :
        32'h0;

    reg flash_loaded;

    reg [8:0] cas_mem_addr_last;
    reg audio_a, audio_b;
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            cas_mem_addr_last <= 1'b0;
            audio_a <= 1'b0;
            audio_b <= 1'b0;
        end else begin
            cas_mem_addr_last <= cas_mem_addr;
            audio_a <= (cas_mem_addr_last != cas_mem_addr) & cas_mem_addr == 256;
            audio_b <= (cas_mem_addr_last != cas_mem_addr) & cas_mem_addr == 0;
        end
    end

    reg [31:0] irq;
    reg last_vsync;
    reg last_audio_a, last_audio_b;
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            irq <= 32'h00000000;
            last_vsync <= 1'b0;
            last_audio_a <= 1'b0;
            last_audio_b <= 1'b0;
        end else begin
            last_vsync <= vsync;
            last_audio_a <= audio_a;
            last_audio_b <= audio_b;
            irq[0] <= last_vsync & ~vsync;
            irq[1] <= ~last_audio_a & audio_a;
            irq[2] <= ~last_audio_b & audio_b;
        end
    end

    /* verilator lint_off PINMISSING */
    picorv32 #(
       .BARREL_SHIFTER(0),
       .COMPRESSED_ISA(0),
       .ENABLE_MUL(0),
       .ENABLE_DIV(0),
       .ENABLE_FAST_MUL(0),
       .ENABLE_IRQ(1),
       .ENABLE_IRQ_QREGS(1)
    ) cpu (
        .clk(clk),
        .resetn(reset_n & flash_loaded),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .irq(irq),
        .eoi(eoi)
    );

`ifdef CONFIG_SRAM
    membram2 #(SRAM_WIDTH-2, "firmware-0.hex", 1) rom0 (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(sram_data_o[7:0]),
        .data_in(mem_wdata[7:0]),
        .cs_n(cs_sram_n),
        .rd_n(mem_wstrb[0]),
        .wr_n(~mem_wstrb[0]),
        .addr(mem_addr[SRAM_WIDTH-1:2])
    );
    membram2 #(SRAM_WIDTH-2, "firmware-1.hex", 1) rom1 (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(sram_data_o[15:8]),
        .data_in(mem_wdata[15:8]),
        .cs_n(cs_sram_n),
        .rd_n(mem_wstrb[1]),
        .wr_n(~mem_wstrb[1]),
        .addr(mem_addr[SRAM_WIDTH-1:2])
    );
    membram2 #(SRAM_WIDTH-2, "firmware-2.hex", 1) rom2 (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(sram_data_o[23:16]),
        .data_in(mem_wdata[23:16]),
        .cs_n(cs_sram_n),
        .rd_n(mem_wstrb[2]),
        .wr_n(~mem_wstrb[2]),
        .addr(mem_addr[SRAM_WIDTH-1:2])
    );
    membram2 #(SRAM_WIDTH-2, "firmware-3.hex", 1) rom3 (
        .clk(~clk),
        .reset_n(reset_n),
        .data_out(sram_data_o[31:24]),
        .data_in(mem_wdata[31:24]),
        .cs_n(cs_sram_n),
        .rd_n(mem_wstrb[3]),
        .wr_n(~mem_wstrb[3]),
        .addr(mem_addr[SRAM_WIDTH-1:2])
    );
    assign sram_ready = ~cs_sram_n;
`endif //CONFIG_SRAM

`ifdef GOWIN
    memdp_32_8
`else
    memdp_32_8_flat
`endif
        #(.ADDR_WIDTH(VRAM_WIDTH)) vram (
        .clka(~clk),
        .reseta(~reset_n),
        .cea(~cs_vram_n),
        .wstrba(mem_wstrb),
        .douta(data_miso_vram_cpu),
        .dina(mem_wdata),
        .ada(mem_addr[VRAM_WIDTH-1:2]),

        .clkb(~clk),
        .resetb(~reset_n),
        .ceb(vdg_rd),
`ifdef GOWIN
        .oceb(vdg_rd),
`endif
        .wreb(1'b0),
        .doutb(vdg_di),
        .dinb(8'h00),
        .adb(vdg_addr[VRAM_WIDTH-1:0])
    );
    assign vram_ready = ~cs_vram_n;

  // sdcard (spi)

    assign spicntl_ready = ~cs_spicntl_n;

`ifdef CONFIG_SD
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            sd_csn <= 1'b1;
        end else if (~cs_spicntl_n && |mem_wstrb) begin
            sd_csn <= mem_wdata[0];
        end
    end
`endif

    reg [1:0] spi_state;
    localparam STATE_SPI_IDLE     = 2'd0;
    localparam STATE_SPI_TRANSFER = 2'd1;
    localparam STATE_SPI_DONE     = 2'd2;

    reg [7:0] sd_spi_rx_data_reg;
    reg spixfer_ready_reg;

    assign spixfer_ready = (~cs_spixfer_n && ~|mem_wstrb) || spixfer_ready_reg;

    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            spi_state <= STATE_SPI_IDLE;
            sd_spi_tx_dv <= 1'b0;
            sd_spi_tx_byte <= 8'h00;
            sd_spi_rx_data_reg <= 8'h00;
            spixfer_ready_reg <= 1'b0;
        end else begin
            sd_spi_tx_dv <= 1'b0;
            spixfer_ready_reg <= 1'b0;

            case (spi_state)
                STATE_SPI_IDLE: begin
                    if (mem_valid && ~cs_spixfer_n) begin
                        if (|mem_wstrb) begin
                            sd_spi_tx_byte <= mem_wdata[7:0];
                            sd_spi_tx_dv <= 1'b1;
                            spi_state <= STATE_SPI_TRANSFER;
                        end else begin
                            spixfer_ready_reg <= 1'b1;
                        end
                    end
                end

                STATE_SPI_TRANSFER: begin
                    if (sd_spi_rx_dv) begin
                        sd_spi_rx_data_reg <= sd_spi_rx_byte;
                        spixfer_ready_reg <= 1'b1;
                        spi_state <= STATE_SPI_DONE;
                    end
                end

                STATE_SPI_DONE: begin
                    if (~mem_valid || cs_spixfer_n) begin
                        spi_state <= STATE_SPI_IDLE;
                    end else begin
                        spixfer_ready_reg <= 1'b1;
                    end
                end

                default: spi_state <= STATE_SPI_IDLE;
            endcase
        end
    end

    reg [7:0] sd_spi_tx_byte;
    reg sd_spi_tx_dv;
    wire sd_spi_tx_ready;
    wire sd_spi_rx_dv;
    wire [7:0] sd_spi_rx_byte;

    SPI_Master sd_spi_master(
        .i_Rst_L(reset_n),
        .i_Clk(clk),

        .i_TX_Byte(sd_spi_tx_byte),
        .i_TX_DV(sd_spi_tx_dv),
        .o_TX_Ready(sd_spi_tx_ready),

        .o_RX_DV(sd_spi_rx_dv),
        .o_RX_Byte(sd_spi_rx_byte),

`ifdef CONFIG_SDCARD_SIM
        .o_SPI_Clk(spi_sclk),
        .i_SPI_MISO(spi_miso),
        .o_SPI_MOSI(spi_mosi)
`else
        .o_SPI_Clk(sd_clk),
        .i_SPI_MISO(sd_miso),
        .o_SPI_MOSI(sd_mosi)
`endif
    );

`ifdef CONFIG_SDCARD_SIM
    reg spi_cs_n;
    reg spi_sclk;
    reg spi_mosi;
    wire spi_miso;

    spi_sd_model #(.INIT_FILE("sdcard.hex"), .BLOCKS(2048)) sdcard (
        .cs_n(spi_cs_n), .sclk(spi_sclk), .mosi(spi_mosi), .miso(spi_miso)
    );
`endif

    // keyboard
    assign kb_ready = ~cs_kb_n;
    wire [15:0] kb_miso;
    assign kb_miso = {key_modifiers,key0};

    // fdc controller
    assign ioseek_ready = ~cs_ioseek_n;
    assign iowrite_ready = ~cs_iowrite_n;
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            miso_wprotect <= 2'b00;
        end else if (~cs_iowrite_n & mem_wstrb[0]) begin
            miso_wprotect <= mem_wdata[1:0];
        end
    end

`ifdef CONFIG_SDRAM
    wire rv_valid;
    wire [22:0] rv_addr;
    wire [31:0] rv_wdata;
    wire [3:0] rv_wstrb;
    wire [31:0] rv_rdata;

    // SDRAM Logic side and controller signals
    wire [31:0] dout32;
    wire data_ready;
    wire busy;

    reg sdram_rd;
    reg sdram_wr;
    reg sdram_refresh;

    reg [11:0] refresh_cnt;
    reg refresh_req;

    reg [2:0] state;
    localparam STATE_IDLE    = 3'd0;
    localparam STATE_READ    = 3'd1;
    localparam STATE_WRITE   = 3'd2;
    localparam STATE_REFRESH = 3'd3;

    reg [31:0] mem_rdata_reg;
    reg sdram_ack;

    // 4-Phase CDC Handshake and Bridge Logic

    // 1. Clock Domain Crossing: clk (28.5MHz) -> clk_sdram (60MHz)
    reg sdram_req;
    reg [2:0] sdram_req_sync_reg = 3'b0;
    always @(posedge clk_sdram or negedge reset_n) begin
        if (~reset_n) begin
            sdram_req_sync_reg <= 3'b0;
        end else begin
            sdram_req_sync_reg <= {sdram_req_sync_reg[1:0], sdram_req};
        end
    end
    wire sdram_req_sync = sdram_req_sync_reg[2];

    // 2. Clock Domain Crossing: clk_sdram (60MHz) -> clk (28.5MHz)
    reg [2:0] sdram_ack_sync_reg = 3'b0;
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            sdram_ack_sync_reg <= 3'b0;
        end else begin
            sdram_ack_sync_reg <= {sdram_ack_sync_reg[1:0], sdram_ack};
        end
    end
    wire sdram_ack_sync = sdram_ack_sync_reg[2];

    // 3. clk (28.5MHz) domain state machine to manage the handshake and read-data stability
    reg [1:0] clk_state = 2'd0;
    localparam CLK_STATE_IDLE     = 2'd0;
    localparam CLK_STATE_REQ      = 2'd1;
    localparam CLK_STATE_ACK      = 2'd2;
    localparam CLK_STATE_WAIT_LOW = 2'd3;

    reg sdram_ready_reg;
    reg [31:0] sdram_data_reg;

    assign sdram_ready = sdram_ready_reg;
    assign sdram_data_o = sdram_data_reg;

    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            clk_state <= CLK_STATE_IDLE;
            sdram_req <= 0;
            sdram_ready_reg <= 0;
            sdram_data_reg <= 32'b0;
        end else begin
            sdram_ready_reg <= 0;

            case (clk_state)
            CLK_STATE_IDLE: begin
                if (rv_valid) begin
                    sdram_req <= 1;
                    clk_state <= CLK_STATE_REQ;
                end
            end

            CLK_STATE_REQ: begin
                if (sdram_ack_sync) begin
                    sdram_data_reg <= mem_rdata_reg;
                    sdram_ready_reg <= 1;
                    clk_state <= CLK_STATE_ACK;
                end
            end

            CLK_STATE_ACK: begin
                sdram_ready_reg <= 1;
                if (~rv_valid) begin
                    sdram_req <= 0;
                    sdram_ready_reg <= 0;
                    clk_state <= CLK_STATE_WAIT_LOW;
                end
            end

            CLK_STATE_WAIT_LOW: begin
                if (~sdram_ack_sync) begin
                    clk_state <= CLK_STATE_IDLE;
                end
            end
            endcase
        end
    end

    // SDRAM needs 4096 refreshes every 64ms (64ms / 4096 = 15.625 us)
    // At 60MHz, 15.625 us is 937.5 clock cycles
    always @(posedge clk_sdram or negedge reset_n) begin
        if (~reset_n) begin
            refresh_cnt <= 0;
            refresh_req <= 0;
        end else begin
            if (refresh_cnt == 12'd900) begin
                refresh_cnt <= 0;
                refresh_req <= 1;
            end else begin
                refresh_cnt <= refresh_cnt + 1;
            end

            if (state == STATE_IDLE && ~busy && refresh_req) begin
                refresh_req <= 0;
            end
        end
    end

    // CPU Memory Interface to SDRAM Controller Bridge State Machine
    always @(posedge clk_sdram or negedge reset_n) begin
        if (~reset_n) begin
            state <= STATE_IDLE;
            sdram_rd <= 0;
            sdram_wr <= 0;
            sdram_refresh <= 0;
            sdram_ack <= 0;
            mem_rdata_reg <= 32'b0;
        end else begin
            sdram_rd <= 0;
            sdram_wr <= 0;
            sdram_refresh <= 0;
            case (state)
            STATE_IDLE: begin
                if (sdram_ack) begin
                    if (~sdram_req_sync) begin
                        sdram_ack <= 0;
                    end
                    if (~busy && refresh_req) begin
                        sdram_refresh <= 1;
                        state <= STATE_REFRESH;
                    end
                end else if (~busy) begin
                    if (refresh_req) begin
                        sdram_refresh <= 1;
                        state <= STATE_REFRESH;
                    end else if (sdram_req_sync) begin
                        if (|rv_wstrb) begin
                            sdram_wr <= 1;
                            state <= STATE_WRITE;
                        end else begin
                            sdram_rd <= 1;
                            state <= STATE_READ;
                        end
                    end
                end
            end

            STATE_READ: begin
                if (data_ready) begin
                    mem_rdata_reg <= dout32;
                    sdram_ack <= 1;
                    state <= STATE_IDLE;
                end
            end

            STATE_WRITE: begin
                if (~busy) begin
                    sdram_ack <= 1;
                    state <= STATE_IDLE;
                end
            end

            STATE_REFRESH: begin
                if (~busy) begin
                    state <= STATE_IDLE;
                end
            end

            default: state <= STATE_IDLE;
            endcase
        end
    end

    sdram_nestang #(
        .FREQ(60_000_000)
    ) sdram_ctrl (
        .SDRAM_DQ(IO_sdram_dq),
        .SDRAM_A(O_sdram_addr),
        .SDRAM_BA(O_sdram_ba),
        .SDRAM_nCS(O_sdram_cs_n),
        .SDRAM_nWE(O_sdram_wen_n),
        .SDRAM_nRAS(O_sdram_ras_n),
        .SDRAM_nCAS(O_sdram_cas_n),
        .SDRAM_CLK(O_sdram_clk),
        .SDRAM_CKE(O_sdram_cke),
        .SDRAM_DQM(O_sdram_dqm),

        .clk(clk_sdram),
        .clk_sdram(clk_sdramp),
        .resetn(reset_n),
        .rd(sdram_rd),
        .wr(sdram_wr),
        .burst(1'b0),
        .refresh(sdram_refresh),
        .addr(rv_addr[22:0]),
        .din(rv_wdata),
        .wmask(rv_wstrb),
        .dout32(dout32),
        .burst_dout(),
        .data_ready(data_ready),
        .busy(busy)
    );

    localparam FIRMWARE_SIZE = 512*1024;

    reg flash_loading;
    reg [20:0] flash_addr;

    reg flash_start;
    wire [7:0] flash_dout;
    wire flash_out_strb;
    assign flash_spi_hold_n = 1;
    assign flash_spi_wp_n = 0;
    reg [7:0] flash_d;
    reg [3:0] flash_wstrb;

    reg flash_wr_req; // Replaces flash_wr to hold the request high

`ifdef CONFIG_SDRAM_LOAD
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            flash_loaded <= 0;
            flash_loading <= 0;
            flash_addr <= 21'd0;
            flash_wr_req <= 0;
            flash_start <= 0;
        end else begin
            flash_start <= 0;

            if (~flash_loaded && ~flash_loading && ~busy) begin
                flash_start <= 1;
                flash_loading <= 1;
                flash_addr <= 21'd0;
            end

            if (flash_loading) begin
                if (flash_out_strb) begin
                    flash_d <= flash_dout;
                    flash_wr_req <= 1;

                    case (flash_addr[1:0])
                    2'b00: flash_wstrb <= 4'b0001;
                    2'b01: flash_wstrb <= 4'b0010;
                    2'b10: flash_wstrb <= 4'b0100;
                    2'b11: flash_wstrb <= 4'b1000;
                    endcase
                end

                if (flash_wr_req && sdram_ready) begin
                    flash_wr_req <= 0;

                    if (flash_addr == FIRMWARE_SIZE-1) begin
                        flash_loading <= 0;
                        flash_loaded <= 1;
                    end else begin
                        flash_addr <= flash_addr + 1;
                    end
                end
            end
        end
    end

    spiflash #(.ADDR(24'h500000), .LEN(FIRMWARE_SIZE)) flash (
        .clk(clk), .resetn(reset_n),
        .ncs(flash_spi_cs_n), .miso(flash_spi_miso), .mosi(flash_spi_mosi),
        .sck(flash_spi_clk),

        .start(flash_start), .dout(flash_dout), .dout_strb(flash_out_strb), .busy(),

        .reg_byte_we(1'b0),
        .reg_word_we(1'b0),
        .reg_ctrl_we(1'b0),
        .reg_di(), .reg_do(), .reg_wait()
    );
`else
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            flash_loading <= 0;
            flash_loaded <= 1;
        end
    end
`endif //CONFIG_SDRAM_LOAD

    assign rv_addr = flash_loading ? {2'b0,flash_addr} : mem_addr[22:0];
    assign rv_wdata = flash_loading ? {flash_d, flash_d, flash_d, flash_d} : mem_wdata;
    assign rv_wstrb = flash_loading ? flash_wstrb : mem_wstrb;
    assign rv_valid = flash_loading ? flash_wr_req : ~cs_sdram_n;

`else
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            flash_loaded <= 1;
        end
    end
`endif // CONFIG_SDRAM

    memdp_32_8 #(.ADDR_WIDTH(12)) dsk (
        .clka(~clk),
        .reseta(~reset_n),
        .cea(~cs_shmem_n),
        .wstrba(mem_wstrb),
        .douta(shmem_data_o),
        .dina(mem_wdata),
        .ada(mem_addr[11:2]),

        .clkb(~clk),
        .resetb(~reset_n),
        .ceb(1'b1),
        .oceb(fdc_shmem_rd),
        .wreb(fdc_shmem_wr),
        .doutb(fdc_shmem_dout),
        .dinb(fdc_shmem_din),
        .adb(fdc_shmem_addr)
    );
    assign shmem_ready = ~cs_shmem_n;

`ifdef GOWIN
    memdp_32_8
`else
    memdp_32_8_flat
`endif
    #(.ADDR_WIDTH(9)) cas (
        .clka(~clk),
        .reseta(~reset_n),
        .cea(~cs_cas_n),
        .wstrba(mem_wstrb),
        .douta(cas_data_o),
        .dina(mem_wdata),
        .ada(mem_addr[11:2]),

        .clkb(~clk),
        .resetb(~reset_n),
        .ceb(1'b1),
`ifdef GOWIN
        .oceb(1'b1),
`endif
        .wreb(1'b0),
        .doutb(cas_mem_dout),
        .dinb(8'h00),
        .adb(cas_mem_addr)
    );
    assign cas_ready = ~cs_cas_n;

    /* status bar */
    function [7:0] hex_to_ascii; 
        input [3:0] nibble;
        begin
            if (nibble < 4'hA)
                hex_to_ascii = 8'h30 + nibble;
            else
                hex_to_ascii = 8'h01 + (nibble - 4'hA);
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            vdg_status_data <= 8'h00;
        end else begin
            case(vdg_status_addr)
            default: vdg_status_data <= 8'h20;
            endcase
        end
    end

endmodule
