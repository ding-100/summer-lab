`timescale 1ns / 1ps

`include "defines.vh"

module cpu_top(
    input  wire         cpu_clk,
    input  wire         cpu_rst,

    output wire [31:0]  m_axi_awaddr,
    output wire [ 7:0]  m_axi_awlen,
    output wire [ 2:0]  m_axi_awsize,
    output wire [ 1:0]  m_axi_awburst,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,
    output wire [31:0]  m_axi_wdata,
    output wire [ 3:0]  m_axi_wstrb,
    output wire         m_axi_wlast,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,
    output wire         m_axi_bready,
    input  wire [ 1:0]  m_axi_bresp,
    input  wire         m_axi_bvalid,
    output wire [31:0]  m_axi_araddr,
    output wire [ 7:0]  m_axi_arlen,
    output wire [ 2:0]  m_axi_arsize,
    output wire [ 1:0]  m_axi_arburst,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    output wire         m_axi_rready,
    input  wire [31:0]  m_axi_rdata,
    input  wire [ 1:0]  m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid
);

    // 适配层，防止上一条指令返回的同一周期内发出下一条取指请求，可能丢失顺序取指
    wire        cpu2ic_rreq;
    wire [31:0] cpu2ic_addr;
    wire        ic2cpu_valid;
    wire [31:0] ic2cpu_inst;
    reg         cache_inst_rreq;
    reg  [31:0] cache_inst_addr;
    wire        cache_inst_valid;
    wire [31:0] cache_inst_out;
    reg         cache_fetch_busy;
    reg         cache_fetch_pending;
    reg  [31:0] cache_fetch_pending_addr;
    reg         cache_drop_response;

    wire [ 3:0] cpu2dc_ren;
    wire [31:0] cpu2dc_addr;
    wire        dc2cpu_valid;
    wire [31:0] dc2cpu_rdata;
    wire [ 3:0] cpu2dc_wen;
    wire [31:0] cpu2dc_wdata;
    wire        dc2cpu_wresp;

    wire                       ic_dev_rrdy;
    wire [3:0]                 ic_cpu_ren;
    wire [31:0]                ic_cpu_raddr;
    wire                       ic_dev_rvalid;
    wire [`IC_BLK_SIZE-1:0]    ic_dev_rdata;

    wire                       dc_dev_wrdy;
    wire [3:0]                 dc_cpu_wen;
    wire [31:0]                dc_cpu_waddr;
    wire [31:0]                dc_cpu_wdata;
    wire                       dc_dev_rrdy;
    wire [3:0]                 dc_cpu_ren;
    wire [31:0]                dc_cpu_raddr;
    wire                       dc_dev_rvalid;
    wire [`DC_BLK_SIZE-1:0]    dc_dev_rdata;

    cpu_core U_core (
        .cpu_clk        (cpu_clk),
        .cpu_rst        (cpu_rst),
        .ifetch_req     (cpu2ic_rreq),
        .ifetch_addr    (cpu2ic_addr),
        .ifetch_valid   (ic2cpu_valid),
        .ifetch_inst    (ic2cpu_inst),
        .daccess_ren    (cpu2dc_ren),
        .daccess_addr   (cpu2dc_addr),
        .daccess_rvalid (dc2cpu_valid),
        .daccess_rdata  (dc2cpu_rdata),
        .daccess_wen    (cpu2dc_wen),
        .daccess_wdata  (cpu2dc_wdata),
        .daccess_wresp  (dc2cpu_wresp)
    );

    // 带 2 的输入CPU，不带 2 的是 cache 的真实响应
    // 带 pending 的缓存上一条指令
    assign ic2cpu_valid = cache_inst_valid && !cache_drop_response;
    assign ic2cpu_inst  = cache_inst_out;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cache_inst_rreq        <= 1'b0;
            cache_inst_addr        <= 32'h0;
            cache_fetch_busy       <= 1'b0;
            cache_fetch_pending    <= 1'b0;
            cache_fetch_pending_addr <= 32'h0;
            cache_drop_response    <= 1'b0;
        end else begin
            cache_inst_rreq <= 1'b0;

            if (cache_inst_valid) begin
                cache_fetch_busy    <= 1'b0;
                cache_drop_response <= 1'b0;
            end

            if (cpu2ic_rreq) begin
                if (!cache_fetch_busy) begin
                    cache_inst_rreq     <= 1'b1;
                    cache_inst_addr     <= cpu2ic_addr;
                    cache_fetch_busy    <= 1'b1;
                    cache_fetch_pending <= 1'b0;
                end else begin
                    cache_fetch_pending      <= 1'b1;
                    cache_fetch_pending_addr <= cpu2ic_addr;
                    if (!cache_inst_valid)
                        cache_drop_response <= 1'b1;
                end
            end else if (!cache_fetch_busy && cache_fetch_pending) begin
                cache_inst_rreq     <= 1'b1;
                cache_inst_addr     <= cache_fetch_pending_addr;
                cache_fetch_busy    <= 1'b1;
                cache_fetch_pending <= 1'b0;
            end
        end
    end

    ICache U_icache (
        .cpu_clk        (cpu_clk),
        .cpu_rst        (cpu_rst),
        .inst_rreq      (cache_inst_rreq),
        .inst_addr      (cache_inst_addr),
        .inst_valid     (cache_inst_valid),
        .inst_out       (cache_inst_out),
        .dev_rrdy       (ic_dev_rrdy),
        .cpu_ren        (ic_cpu_ren),
        .cpu_raddr      (ic_cpu_raddr),
        .dev_rvalid     (ic_dev_rvalid),
        .dev_rdata      (ic_dev_rdata)
    );

    DCache U_dcache (
        .cpu_clk        (cpu_clk),
        .cpu_rst        (cpu_rst),
        .data_ren       (cpu2dc_ren),
        .data_addr      (cpu2dc_addr),
        .data_valid     (dc2cpu_valid),
        .data_rdata     (dc2cpu_rdata),
        .data_wen       (cpu2dc_wen),
        .data_wdata     (cpu2dc_wdata),
        .data_wresp     (dc2cpu_wresp),
        .dev_wrdy       (dc_dev_wrdy),
        .cpu_wen        (dc_cpu_wen),
        .cpu_waddr      (dc_cpu_waddr),
        .cpu_wdata      (dc_cpu_wdata),
        .dev_rrdy       (dc_dev_rrdy),
        .cpu_ren        (dc_cpu_ren),
        .cpu_raddr      (dc_cpu_raddr),
        .dev_rvalid     (dc_dev_rvalid),
        .dev_rdata      (dc_dev_rdata)
    );

    axi_master U_aximaster (
        .aclk           (cpu_clk),
        .areset         (cpu_rst),
        .ic_dev_rrdy    (ic_dev_rrdy),
        .ic_cpu_ren     (ic_cpu_ren),
        .ic_cpu_raddr   (ic_cpu_raddr),
        .ic_dev_rvalid  (ic_dev_rvalid),
        .ic_dev_rdata   (ic_dev_rdata),
        .dc_dev_wrdy    (dc_dev_wrdy),
        .dc_cpu_wen     (dc_cpu_wen),
        .dc_cpu_waddr   (dc_cpu_waddr),
        .dc_cpu_wdata   (dc_cpu_wdata),
        .dc_dev_rrdy    (dc_dev_rrdy),
        .dc_cpu_ren     (dc_cpu_ren),
        .dc_cpu_raddr   (dc_cpu_raddr),
        .dc_dev_rvalid  (dc_dev_rvalid),
        .dc_dev_rdata   (dc_dev_rdata),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bready   (m_axi_bready),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_rready   (m_axi_rready),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid)
    );

endmodule
