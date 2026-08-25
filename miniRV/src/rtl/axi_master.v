`timescale 1ns / 1ps

`include "defines.vh"

// Cache-to-AXI4 controller.  The read and write paths are independent.  Read
// arbitration is DCache-first; one AXI burst refills one cache line.
module axi_master(
    input  wire         aclk,
    input  wire         areset,

    output wire         ic_dev_rrdy,
    input  wire [ 3:0]  ic_cpu_ren,
    input  wire [31:0]  ic_cpu_raddr,
    output reg          ic_dev_rvalid,
    output reg  [`IC_BLK_SIZE-1:0] ic_dev_rdata,

    output wire         dc_dev_wrdy,
    input  wire [ 3:0]  dc_cpu_wen,
    input  wire [31:0]  dc_cpu_waddr,
    input  wire [31:0]  dc_cpu_wdata,
    output wire         dc_dev_rrdy,
    input  wire [ 3:0]  dc_cpu_ren,
    input  wire [31:0]  dc_cpu_raddr,
    output reg          dc_dev_rvalid,
    output reg  [`DC_BLK_SIZE-1:0] dc_dev_rdata,

    output reg  [31:0]  m_axi_awaddr,
    output reg  [ 7:0]  m_axi_awlen,
    output reg  [ 2:0]  m_axi_awsize,
    output reg  [ 1:0]  m_axi_awburst,
    output reg          m_axi_awvalid,
    input  wire         m_axi_awready,
    output reg  [31:0]  m_axi_wdata,
    output reg  [ 3:0]  m_axi_wstrb,
    output wire         m_axi_wlast,
    output reg          m_axi_wvalid,
    input  wire         m_axi_wready,
    output reg          m_axi_bready,
    input  wire [ 1:0]  m_axi_bresp,
    input  wire         m_axi_bvalid,
    output reg  [31:0]  m_axi_araddr,
    output reg  [ 7:0]  m_axi_arlen,
    output reg  [ 2:0]  m_axi_arsize,
    output reg  [ 1:0]  m_axi_arburst,
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,
    output reg          m_axi_rready,
    input  wire [31:0]  m_axi_rdata,
    input  wire [ 1:0]  m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid
);

    localparam [1:0] R_IDLE = 2'd0;
    localparam [1:0] R_ADDR = 2'd1;
    localparam [1:0] R_DATA = 2'd2;
    localparam [1:0] W_IDLE = 2'd0;
    localparam [1:0] W_SEND = 2'd1;
    localparam [1:0] W_RESP = 2'd2;

    reg [1:0] read_state;
    reg [1:0] write_state;
    reg       read_for_dcache;
    reg [2:0] read_beat;
    reg [127:0] read_buffer;
    reg aw_pending;
    reg w_pending;

    wire dc_uncached = dc_cpu_raddr[31:16] == 16'hffff;

    // dcache 优先
    assign dc_dev_rrdy = read_state == R_IDLE;
    assign ic_dev_rrdy = read_state == R_IDLE && !(|dc_cpu_ren);
    assign dc_dev_wrdy = write_state == W_IDLE;
    assign m_axi_wlast = 1'b1;

    // 依次读取4个32位字
    function [127:0] put_read_beat;
        input [127:0] old_data;
        input [31:0] new_data;
        input [2:0] beat;
        begin
            put_read_beat = old_data;
            case (beat)
                3'd0: put_read_beat[31:0]   = new_data;
                3'd1: put_read_beat[63:32]  = new_data;
                3'd2: put_read_beat[95:64]  = new_data;
                default: put_read_beat[127:96] = new_data;
            endcase
        end
    endfunction

    always @(posedge aclk or posedge areset) begin
        if (areset) begin
            read_state       <= R_IDLE;
            write_state      <= W_IDLE;
            read_for_dcache  <= 1'b0;
            read_beat        <= 3'd0;
            read_buffer      <= 128'h0;
            aw_pending       <= 1'b0;
            w_pending        <= 1'b0;
            ic_dev_rvalid    <= 1'b0;
            ic_dev_rdata     <= {`IC_BLK_SIZE{1'b0}};
            dc_dev_rvalid    <= 1'b0;
            dc_dev_rdata     <= {`DC_BLK_SIZE{1'b0}};
            m_axi_awaddr     <= 32'h0;
            m_axi_awlen      <= 8'h0;
            m_axi_awsize     <= 3'd2;
            m_axi_awburst    <= 2'b01;
            m_axi_awvalid    <= 1'b0;
            m_axi_wdata      <= 32'h0;
            m_axi_wstrb      <= 4'h0;
            m_axi_wvalid     <= 1'b0;
            m_axi_bready     <= 1'b0;
            m_axi_araddr     <= 32'h0;
            m_axi_arlen      <= 8'h0;
            m_axi_arsize     <= 3'd2;
            m_axi_arburst    <= 2'b01;
            m_axi_arvalid    <= 1'b0;
            m_axi_rready     <= 1'b0;
        end else begin
            ic_dev_rvalid <= 1'b0;
            dc_dev_rvalid <= 1'b0;

            case (read_state)
                R_IDLE: begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    read_beat     <= 3'd0;
                    read_buffer   <= 128'h0;
                    if (|dc_cpu_ren) begin
                        read_for_dcache <= 1'b1;
                        m_axi_araddr    <= dc_cpu_raddr;
                        // 读取外设，一次只读一个32位字，将 ar 通道的读取长度设为0
                        m_axi_arlen     <= dc_uncached ? 8'd0 :
                                           (`DC_BLK_LEN - 1);
                        m_axi_arsize    <= 3'd2;
                        m_axi_arburst   <= 2'b01;
                        m_axi_arvalid   <= 1'b1;
                        read_state      <= R_ADDR;
                    end else if (|ic_cpu_ren) begin
                        read_for_dcache <= 1'b0;
                        m_axi_araddr    <= ic_cpu_raddr;
                        m_axi_arlen     <= `IC_BLK_LEN - 1;
                        m_axi_arsize    <= 3'd2;
                        m_axi_arburst   <= 2'b01;
                        m_axi_arvalid   <= 1'b1;
                        read_state      <= R_ADDR;
                    end
                end

                R_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        read_state    <= R_DATA;
                    end
                end

                R_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        read_buffer <= put_read_beat(read_buffer,
                                                     m_axi_rdata,
                                                     read_beat);
                        if (m_axi_rlast) begin
                            // last 表示本次传输结束，读取外设时恒为 1 
                            // Dcache 会自动抽取 line 中的 [31:0] 作为数据，返回到 cpu
                            if (read_for_dcache) begin
                                dc_dev_rdata <= put_read_beat(
                                    read_buffer, m_axi_rdata, read_beat);
                                dc_dev_rvalid <= 1'b1;
                            end else begin
                                ic_dev_rdata <= put_read_beat(
                                    read_buffer, m_axi_rdata, read_beat);
                                ic_dev_rvalid <= 1'b1;
                            end
                            m_axi_rready <= 1'b0;
                            read_state   <= R_IDLE;
                        end else begin
                            read_beat <= read_beat + 3'd1;
                        end
                    end
                end

                default: read_state <= R_IDLE;
            endcase

           case (write_state)
                W_IDLE: begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;

                    if (|dc_cpu_wen) begin
                        m_axi_awaddr  <= dc_cpu_waddr;
                        m_axi_awlen   <= 8'd0;
                        m_axi_awsize  <= 3'd2;
                        m_axi_awburst <= 2'b01;
                        m_axi_awvalid <= 1'b1;

                        m_axi_wdata   <= dc_cpu_wdata;
                        m_axi_wstrb   <= dc_cpu_wen;
                        m_axi_wvalid  <= 1'b1;

                        write_state   <= W_SEND;
                    end
                end

                W_SEND: begin
                    // AW通道独立握手
                    if (m_axi_awvalid && m_axi_awready)
                        m_axi_awvalid <= 1'b0;

                    // W通道独立握手
                    if (m_axi_wvalid && m_axi_wready)
                        m_axi_wvalid <= 1'b0;

                    // VALID=0表示此前已经完成；
                    // VALID=1且READY=1表示本周期完成
                    if ((!m_axi_awvalid ||
                        (m_axi_awvalid && m_axi_awready)) &&
                        (!m_axi_wvalid ||
                        (m_axi_wvalid && m_axi_wready))) begin
                        m_axi_bready <= 1'b1;
                        write_state  <= W_RESP;
                    end
                end

                W_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        write_state  <= W_IDLE;
                    end
                end

                default: write_state <= W_IDLE;
            endcase 
        end
    end

    // Responses are intentionally ignored by this educational core.  The
    // channels are nevertheless consumed according to AXI ready/valid rules.
    wire _unused_ok = &{1'b0, m_axi_bresp, m_axi_rresp};

endmodule
