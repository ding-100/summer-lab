`timescale 1ns / 1ps

`include "defines.vh"

module miniRV_SoC(
    input  wire         fpga_clk,
    input  wire         fpga_rst,
    input  wire [15:0]  sw,
    output wire [15:0]  led,
    output wire [ 7:0]  dig_en,
    output wire [ 7:0]  dig_seg,
    output wire [ 7:0]  dig_seg1,
    input  wire         rx,
    output wire         tx
);
`ifdef RUN_TRACE
    wire sys_clk = fpga_clk;
    wire sys_rst = fpga_rst;
`else
    wire pll_clk1;
    wire pll_lock;
    wire sys_clk = pll_clk1;
    reg [1:0] rst_sync;
    wire sys_rst = rst_sync[1];

    always @(posedge sys_clk or negedge fpga_rst) begin
        if (!fpga_rst)
            rst_sync <= 2'b11;
        else
            rst_sync <= {rst_sync[0], !pll_lock};
    end

    clk_wiz_0 U_clkgen (
        .clk_in1(fpga_clk), .locked(pll_lock), .clk_out1(pll_clk1)
    );
`endif

    wire [31:0] cpu_awaddr, cpu_wdata, cpu_araddr, cpu_rdata;
    wire [7:0] cpu_awlen, cpu_arlen;
    wire [2:0] cpu_awsize, cpu_arsize;
    wire [1:0] cpu_awburst, cpu_bresp, cpu_arburst, cpu_rresp;
    wire [3:0] cpu_wstrb;
    wire cpu_awvalid, cpu_awready, cpu_wlast, cpu_wvalid, cpu_wready;
    wire cpu_bready, cpu_bvalid, cpu_arvalid, cpu_arready;
    wire cpu_rready, cpu_rlast, cpu_rvalid;

    cpu_top U_cpu (
        .cpu_clk(sys_clk), .cpu_rst(sys_rst),
        .m_axi_awaddr(cpu_awaddr), .m_axi_awlen(cpu_awlen),
        .m_axi_awsize(cpu_awsize), .m_axi_awburst(cpu_awburst),
        .m_axi_awvalid(cpu_awvalid), .m_axi_awready(cpu_awready),
        .m_axi_wdata(cpu_wdata), .m_axi_wstrb(cpu_wstrb),
        .m_axi_wlast(cpu_wlast), .m_axi_wvalid(cpu_wvalid),
        .m_axi_wready(cpu_wready), .m_axi_bready(cpu_bready),
        .m_axi_bresp(cpu_bresp), .m_axi_bvalid(cpu_bvalid),
        .m_axi_araddr(cpu_araddr), .m_axi_arlen(cpu_arlen),
        .m_axi_arsize(cpu_arsize), .m_axi_arburst(cpu_arburst),
        .m_axi_arvalid(cpu_arvalid), .m_axi_arready(cpu_arready),
        .m_axi_rready(cpu_rready), .m_axi_rdata(cpu_rdata),
        .m_axi_rresp(cpu_rresp), .m_axi_rlast(cpu_rlast),
        .m_axi_rvalid(cpu_rvalid)
    );

    wire [31:0] bram_awaddr, bram_wdata, bram_araddr, bram_rdata;
    wire [7:0] bram_awlen, bram_arlen;
    wire [2:0] bram_awsize, bram_arsize;
    wire [1:0] bram_awburst, bram_bresp, bram_arburst, bram_rresp;
    wire [3:0] bram_wstrb;
    wire bram_awvalid, bram_awready, bram_wlast, bram_wvalid, bram_wready;
    wire bram_bready, bram_bvalid, bram_arvalid, bram_arready;
    wire bram_rready, bram_rlast, bram_rvalid;
    wire [3:0] unused_bid, unused_rid;

`ifdef RUN_TRACE
    // The Trace framework cannot simulate the Vivado peripheral IP.  Bypass
    // the Crossbar and connect the CPU directly to its bram_axi model.
    assign bram_awaddr = cpu_awaddr;
    assign bram_awlen = cpu_awlen;
    assign bram_awsize = cpu_awsize;
    assign bram_awburst = cpu_awburst;
    assign bram_awvalid = cpu_awvalid;
    assign cpu_awready = bram_awready;
    assign bram_wdata = cpu_wdata;
    assign bram_wstrb = cpu_wstrb;
    assign bram_wlast = cpu_wlast;
    assign bram_wvalid = cpu_wvalid;
    assign cpu_wready = bram_wready;
    assign cpu_bresp = bram_bresp;
    assign cpu_bvalid = bram_bvalid;
    assign bram_bready = cpu_bready;
    assign bram_araddr = cpu_araddr;
    assign bram_arlen = cpu_arlen;
    assign bram_arsize = cpu_arsize;
    assign bram_arburst = cpu_arburst;
    assign bram_arvalid = cpu_arvalid;
    assign cpu_arready = bram_arready;
    assign bram_rready = cpu_rready;
    assign cpu_rdata = bram_rdata;
    assign cpu_rresp = bram_rresp;
    assign cpu_rlast = bram_rlast;
    assign cpu_rvalid = bram_rvalid;

    assign led = 16'h0;
    assign dig_en = 8'hff;
    assign dig_seg = 8'hff;
    assign dig_seg1 = 8'hff;
    assign tx = 1'b1;
    wire _unused_trace_inputs = &{1'b0, sw, rx};
`else
    wire [31:0] sw_awaddr, led_awaddr, digled_awaddr, uart_awaddr, tim_awaddr;
    wire [31:0] sw_wdata, led_wdata, digled_wdata, uart_wdata, tim_wdata;
    wire [31:0] sw_araddr, led_araddr, digled_araddr, uart_araddr, tim_araddr;
    wire [31:0] sw_rdata, led_rdata, digled_rdata, uart_rdata, tim_rdata;
    wire [7:0] sw_awlen, led_awlen, digled_awlen, uart_awlen, tim_awlen;
    wire [7:0] sw_arlen, led_arlen, digled_arlen, uart_arlen, tim_arlen;
    wire [2:0] sw_awsize, led_awsize, digled_awsize, uart_awsize, tim_awsize;
    wire [2:0] sw_arsize, led_arsize, digled_arsize, uart_arsize, tim_arsize;
    wire [1:0] sw_awburst, led_awburst, digled_awburst, uart_awburst, tim_awburst;
    wire [1:0] sw_arburst, led_arburst, digled_arburst, uart_arburst, tim_arburst;
    wire [1:0] sw_bresp, led_bresp, digled_bresp, uart_bresp, tim_bresp;
    wire [1:0] sw_rresp, led_rresp, digled_rresp, uart_rresp, tim_rresp;
    wire [3:0] sw_wstrb, led_wstrb, digled_wstrb, uart_wstrb, tim_wstrb;
    wire sw_awvalid, led_awvalid, digled_awvalid, uart_awvalid, tim_awvalid;
    wire sw_awready, led_awready, digled_awready, uart_awready, tim_awready;
    wire sw_wlast, led_wlast, digled_wlast, uart_wlast, tim_wlast;
    wire sw_wvalid, led_wvalid, digled_wvalid, uart_wvalid, tim_wvalid;
    wire sw_wready, led_wready, digled_wready, uart_wready, tim_wready;
    wire sw_bready, led_bready, digled_bready, uart_bready, tim_bready;
    wire sw_bvalid, led_bvalid, digled_bvalid, uart_bvalid, tim_bvalid;
    wire sw_arvalid, led_arvalid, digled_arvalid, uart_arvalid, tim_arvalid;
    wire sw_arready, led_arready, digled_arready, uart_arready, tim_arready;
    wire sw_rready, led_rready, digled_rready, uart_rready, tim_rready;
    wire sw_rlast, led_rlast, digled_rlast, uart_rlast, tim_rlast;
    wire sw_rvalid, led_rvalid, digled_rvalid, uart_rvalid, tim_rvalid;

    axi_crossbar_0 U_bridge (
        .aclk(sys_clk), .aresetn(!sys_rst),
        .s_axi_awaddr(cpu_awaddr), .s_axi_awlen(cpu_awlen),
        .s_axi_awsize(cpu_awsize), .s_axi_awburst(cpu_awburst),
        .s_axi_awvalid(cpu_awvalid), .s_axi_awready(cpu_awready),
        .s_axi_awlock(1'b0), .s_axi_awcache(4'h0),
        .s_axi_awprot(3'h0), .s_axi_awqos(4'h0),
        .s_axi_wdata(cpu_wdata), .s_axi_wstrb(cpu_wstrb),
        .s_axi_wlast(cpu_wlast), .s_axi_wvalid(cpu_wvalid),
        .s_axi_wready(cpu_wready), .s_axi_bresp(cpu_bresp),
        .s_axi_bvalid(cpu_bvalid), .s_axi_bready(cpu_bready),
        .s_axi_araddr(cpu_araddr), .s_axi_arlen(cpu_arlen),
        .s_axi_arsize(cpu_arsize), .s_axi_arburst(cpu_arburst),
        .s_axi_arvalid(cpu_arvalid), .s_axi_arready(cpu_arready),
        .s_axi_arlock(1'b0), .s_axi_arcache(4'h0),
        .s_axi_arprot(3'h0), .s_axi_arqos(4'h0),
        .s_axi_rdata(cpu_rdata), .s_axi_rresp(cpu_rresp),
        .s_axi_rlast(cpu_rlast), .s_axi_rvalid(cpu_rvalid),
        .s_axi_rready(cpu_rready),
        .m_axi_awaddr({tim_awaddr,uart_awaddr,digled_awaddr,led_awaddr,sw_awaddr,bram_awaddr}),
        .m_axi_awlen({tim_awlen,uart_awlen,digled_awlen,led_awlen,sw_awlen,bram_awlen}),
        .m_axi_awsize({tim_awsize,uart_awsize,digled_awsize,led_awsize,sw_awsize,bram_awsize}),
        .m_axi_awburst({tim_awburst,uart_awburst,digled_awburst,led_awburst,sw_awburst,bram_awburst}),
        .m_axi_awvalid({tim_awvalid,uart_awvalid,digled_awvalid,led_awvalid,sw_awvalid,bram_awvalid}),
        .m_axi_awready({tim_awready,uart_awready,digled_awready,led_awready,sw_awready,bram_awready}),
        .m_axi_wdata({tim_wdata,uart_wdata,digled_wdata,led_wdata,sw_wdata,bram_wdata}),
        .m_axi_wstrb({tim_wstrb,uart_wstrb,digled_wstrb,led_wstrb,sw_wstrb,bram_wstrb}),
        .m_axi_wlast({tim_wlast,uart_wlast,digled_wlast,led_wlast,sw_wlast,bram_wlast}),
        .m_axi_wvalid({tim_wvalid,uart_wvalid,digled_wvalid,led_wvalid,sw_wvalid,bram_wvalid}),
        .m_axi_wready({tim_wready,uart_wready,digled_wready,led_wready,sw_wready,bram_wready}),
        .m_axi_bresp({tim_bresp,uart_bresp,digled_bresp,led_bresp,sw_bresp,bram_bresp}),
        .m_axi_bvalid({tim_bvalid,uart_bvalid,digled_bvalid,led_bvalid,sw_bvalid,bram_bvalid}),
        .m_axi_bready({tim_bready,uart_bready,digled_bready,led_bready,sw_bready,bram_bready}),
        .m_axi_araddr({tim_araddr,uart_araddr,digled_araddr,led_araddr,sw_araddr,bram_araddr}),
        .m_axi_arlen({tim_arlen,uart_arlen,digled_arlen,led_arlen,sw_arlen,bram_arlen}),
        .m_axi_arsize({tim_arsize,uart_arsize,digled_arsize,led_arsize,sw_arsize,bram_arsize}),
        .m_axi_arburst({tim_arburst,uart_arburst,digled_arburst,led_arburst,sw_arburst,bram_arburst}),
        .m_axi_arvalid({tim_arvalid,uart_arvalid,digled_arvalid,led_arvalid,sw_arvalid,bram_arvalid}),
        .m_axi_arready({tim_arready,uart_arready,digled_arready,led_arready,sw_arready,bram_arready}),
        .m_axi_rdata({tim_rdata,uart_rdata,digled_rdata,led_rdata,sw_rdata,bram_rdata}),
        .m_axi_rresp({tim_rresp,uart_rresp,digled_rresp,led_rresp,sw_rresp,bram_rresp}),
        .m_axi_rlast({tim_rlast,uart_rlast,digled_rlast,led_rlast,sw_rlast,bram_rlast}),
        .m_axi_rvalid({tim_rvalid,uart_rvalid,digled_rvalid,led_rvalid,sw_rvalid,bram_rvalid}),
        .m_axi_rready({tim_rready,uart_rready,digled_rready,led_rready,sw_rready,bram_rready})
    );

    switch_wrap U_switch (
        .aclk(sys_clk), .aresetn(!sys_rst),
        .s_axi_awaddr(sw_awaddr), .s_axi_awlen(sw_awlen),
        .s_axi_awsize(sw_awsize), .s_axi_awburst(sw_awburst),
        .s_axi_awlock(1'b0), .s_axi_awcache(4'h0),
        .s_axi_awprot(3'h0), .s_axi_awregion(4'h0),
        .s_axi_awqos(4'h0), .s_axi_awvalid(sw_awvalid),
        .s_axi_awready(sw_awready), .s_axi_wdata(sw_wdata),
        .s_axi_wstrb(sw_wstrb), .s_axi_wlast(sw_wlast),
        .s_axi_wvalid(sw_wvalid), .s_axi_wready(sw_wready),
        .s_axi_bresp(sw_bresp), .s_axi_bvalid(sw_bvalid),
        .s_axi_bready(sw_bready), .s_axi_araddr(sw_araddr),
        .s_axi_arlen(sw_arlen), .s_axi_arsize(sw_arsize),
        .s_axi_arburst(sw_arburst), .s_axi_arlock(1'b0),
        .s_axi_arcache(4'h0), .s_axi_arprot(3'h0),
        .s_axi_arregion(4'h0), .s_axi_arqos(4'h0),
        .s_axi_arvalid(sw_arvalid), .s_axi_arready(sw_arready),
        .s_axi_rdata(sw_rdata), .s_axi_rresp(sw_rresp),
        .s_axi_rlast(sw_rlast), .s_axi_rvalid(sw_rvalid),
        .s_axi_rready(sw_rready), .switch(sw)
    );

    led_wrap U_led (
        .aclk(sys_clk), .aresetn(!sys_rst),
        .s_axi_awaddr(led_awaddr), .s_axi_awlen(led_awlen),
        .s_axi_awsize(led_awsize), .s_axi_awburst(led_awburst),
        .s_axi_awlock(1'b0), .s_axi_awcache(4'h0),
        .s_axi_awprot(3'h0), .s_axi_awregion(4'h0),
        .s_axi_awqos(4'h0), .s_axi_awvalid(led_awvalid),
        .s_axi_awready(led_awready), .s_axi_wdata(led_wdata),
        .s_axi_wstrb(led_wstrb), .s_axi_wlast(led_wlast),
        .s_axi_wvalid(led_wvalid), .s_axi_wready(led_wready),
        .s_axi_bresp(led_bresp), .s_axi_bvalid(led_bvalid),
        .s_axi_bready(led_bready), .s_axi_araddr(led_araddr),
        .s_axi_arlen(led_arlen), .s_axi_arsize(led_arsize),
        .s_axi_arburst(led_arburst), .s_axi_arlock(1'b0),
        .s_axi_arcache(4'h0), .s_axi_arprot(3'h0),
        .s_axi_arregion(4'h0), .s_axi_arqos(4'h0),
        .s_axi_arvalid(led_arvalid), .s_axi_arready(led_arready),
        .s_axi_rdata(led_rdata), .s_axi_rresp(led_rresp),
        .s_axi_rlast(led_rlast), .s_axi_rvalid(led_rvalid),
        .s_axi_rready(led_rready), .led_o(led)
    );

    digled_wrap U_digled (
        .aclk(sys_clk), .aresetn(!sys_rst),
        .s_axi_awaddr(digled_awaddr), .s_axi_awlen(digled_awlen),
        .s_axi_awsize(digled_awsize), .s_axi_awburst(digled_awburst),
        .s_axi_awlock(1'b0), .s_axi_awcache(4'h0),
        .s_axi_awprot(3'h0), .s_axi_awregion(4'h0),
        .s_axi_awqos(4'h0), .s_axi_awvalid(digled_awvalid),
        .s_axi_awready(digled_awready), .s_axi_wdata(digled_wdata),
        .s_axi_wstrb(digled_wstrb), .s_axi_wlast(digled_wlast),
        .s_axi_wvalid(digled_wvalid), .s_axi_wready(digled_wready),
        .s_axi_bresp(digled_bresp), .s_axi_bvalid(digled_bvalid),
        .s_axi_bready(digled_bready), .s_axi_araddr(digled_araddr),
        .s_axi_arlen(digled_arlen), .s_axi_arsize(digled_arsize),
        .s_axi_arburst(digled_arburst), .s_axi_arlock(1'b0),
        .s_axi_arcache(4'h0), .s_axi_arprot(3'h0),
        .s_axi_arregion(4'h0), .s_axi_arqos(4'h0),
        .s_axi_arvalid(digled_arvalid), .s_axi_arready(digled_arready),
        .s_axi_rdata(digled_rdata), .s_axi_rresp(digled_rresp),
        .s_axi_rlast(digled_rlast), .s_axi_rvalid(digled_rvalid),
        .s_axi_rready(digled_rready),
        .dig_en(dig_en), .dig_seg(dig_seg), .dig_seg1(dig_seg1)
    );

    uart_wrap U_uart (
        .aclk(sys_clk), .aresetn(!sys_rst),
        .s_axi_awaddr(uart_awaddr), .s_axi_awlen(uart_awlen),
        .s_axi_awsize(uart_awsize), .s_axi_awburst(uart_awburst),
        .s_axi_awlock(1'b0), .s_axi_awcache(4'h0),
        .s_axi_awprot(3'h0), .s_axi_awregion(4'h0),
        .s_axi_awqos(4'h0), .s_axi_awvalid(uart_awvalid),
        .s_axi_awready(uart_awready), .s_axi_wdata(uart_wdata),
        .s_axi_wstrb(uart_wstrb), .s_axi_wlast(uart_wlast),
        .s_axi_wvalid(uart_wvalid), .s_axi_wready(uart_wready),
        .s_axi_bresp(uart_bresp), .s_axi_bvalid(uart_bvalid),
        .s_axi_bready(uart_bready), .s_axi_araddr(uart_araddr),
        .s_axi_arlen(uart_arlen), .s_axi_arsize(uart_arsize),
        .s_axi_arburst(uart_arburst), .s_axi_arlock(1'b0),
        .s_axi_arcache(4'h0), .s_axi_arprot(3'h0),
        .s_axi_arregion(4'h0), .s_axi_arqos(4'h0),
        .s_axi_arvalid(uart_arvalid), .s_axi_arready(uart_arready),
        .s_axi_rdata(uart_rdata), .s_axi_rresp(uart_rresp),
        .s_axi_rlast(uart_rlast), .s_axi_rvalid(uart_rvalid),
        .s_axi_rready(uart_rready),
        .rx(rx), .tx(tx)
    );

    timer_wrap U_timer (
        .aclk(sys_clk), .aresetn(!sys_rst),
        .s_axi_awaddr(tim_awaddr), .s_axi_awlen(tim_awlen),
        .s_axi_awsize(tim_awsize), .s_axi_awburst(tim_awburst),
        .s_axi_awlock(1'b0), .s_axi_awcache(4'h0),
        .s_axi_awprot(3'h0), .s_axi_awregion(4'h0),
        .s_axi_awqos(4'h0), .s_axi_awvalid(tim_awvalid),
        .s_axi_awready(tim_awready), .s_axi_wdata(tim_wdata),
        .s_axi_wstrb(tim_wstrb), .s_axi_wlast(tim_wlast),
        .s_axi_wvalid(tim_wvalid), .s_axi_wready(tim_wready),
        .s_axi_bresp(tim_bresp), .s_axi_bvalid(tim_bvalid),
        .s_axi_bready(tim_bready), .s_axi_araddr(tim_araddr),
        .s_axi_arlen(tim_arlen), .s_axi_arsize(tim_arsize),
        .s_axi_arburst(tim_arburst), .s_axi_arlock(1'b0),
        .s_axi_arcache(4'h0), .s_axi_arprot(3'h0),
        .s_axi_arregion(4'h0), .s_axi_arqos(4'h0),
        .s_axi_arvalid(tim_arvalid), .s_axi_arready(tim_arready),
        .s_axi_rdata(tim_rdata), .s_axi_rresp(tim_rresp),
        .s_axi_rlast(tim_rlast), .s_axi_rvalid(tim_rvalid),
        .s_axi_rready(tim_rready)
    );
`endif

    bram_axi U_bram (
        .s_aclk(sys_clk), .s_aresetn(!sys_rst),
        .s_axi_awid(4'h6), .s_axi_awaddr(bram_awaddr),
        .s_axi_awlen(bram_awlen), .s_axi_awsize(bram_awsize),
        .s_axi_awburst(bram_awburst),
        .s_axi_awvalid(bram_awvalid), .s_axi_awready(bram_awready),
        .s_axi_wdata(bram_wdata), .s_axi_wstrb(bram_wstrb),
        .s_axi_wlast(bram_wlast), .s_axi_wvalid(bram_wvalid),
        .s_axi_wready(bram_wready), .s_axi_bid(unused_bid),
        .s_axi_bresp(bram_bresp), .s_axi_bvalid(bram_bvalid),
        .s_axi_bready(bram_bready), .s_axi_arid(4'h6),
        .s_axi_araddr(bram_araddr), .s_axi_arlen(bram_arlen),
        .s_axi_arsize(bram_arsize), .s_axi_arburst(bram_arburst),
         .s_axi_arvalid(bram_arvalid),
        .s_axi_arready(bram_arready), .s_axi_rid(unused_rid),
        .s_axi_rdata(bram_rdata), .s_axi_rresp(bram_rresp),
        .s_axi_rlast(bram_rlast), .s_axi_rvalid(bram_rvalid),
        .s_axi_rready(bram_rready)
    );
endmodule
