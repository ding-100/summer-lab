`timescale 1ns / 1ps

`ifndef RUN_TRACE
module uart_wrap(
    input wire aclk, input wire aresetn,
    input wire [31:0] s_axi_awaddr, input wire [7:0] s_axi_awlen,
    input wire [2:0] s_axi_awsize, input wire [1:0] s_axi_awburst,
    input wire [0:0] s_axi_awlock, input wire [3:0] s_axi_awcache,
    input wire [2:0] s_axi_awprot, input wire [3:0] s_axi_awregion,
    input wire [3:0] s_axi_awqos, input wire s_axi_awvalid,
    output wire s_axi_awready, input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb, input wire s_axi_wlast,
    input wire s_axi_wvalid, output wire s_axi_wready,
    output wire [1:0] s_axi_bresp, output wire s_axi_bvalid,
    input wire s_axi_bready, input wire [31:0] s_axi_araddr,
    input wire [7:0] s_axi_arlen, input wire [2:0] s_axi_arsize,
    input wire [1:0] s_axi_arburst, input wire [0:0] s_axi_arlock,
    input wire [3:0] s_axi_arcache, input wire [2:0] s_axi_arprot,
    input wire [3:0] s_axi_arregion, input wire [3:0] s_axi_arqos,
    input wire s_axi_arvalid, output wire s_axi_arready,
    output wire [31:0] s_axi_rdata, output wire [1:0] s_axi_rresp,
    output wire s_axi_rlast, output wire s_axi_rvalid,
    input wire s_axi_rready, input wire rx, output wire tx
);
    wire [31:0] uart_awaddr, uart_wdata, uart_araddr, uart_rdata;
    wire [3:0] uart_wstrb;
    wire uart_awready, uart_awvalid, uart_wready, uart_wvalid;
    wire uart_bready, uart_bvalid, uart_arready, uart_arvalid;
    wire uart_rready, uart_rvalid;
    wire [1:0] uart_bresp, uart_rresp;
    wire unused_interrupt;

    axi_protocol_converter_0 U_uart_converter (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize), .s_axi_awburst(s_axi_awburst),
        .s_axi_awlock(s_axi_awlock), .s_axi_awcache(s_axi_awcache),
        .s_axi_awprot(s_axi_awprot), .s_axi_awregion(s_axi_awregion),
        .s_axi_awqos(s_axi_awqos), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb), .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen), .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst), .s_axi_arlock(s_axi_arlock),
        .s_axi_arcache(s_axi_arcache), .s_axi_arprot(s_axi_arprot),
        .s_axi_arregion(s_axi_arregion), .s_axi_arqos(s_axi_arqos),
        .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .m_axi_awaddr(uart_awaddr), .m_axi_awvalid(uart_awvalid),
        .m_axi_awready(uart_awready), .m_axi_wdata(uart_wdata),
        .m_axi_wstrb(uart_wstrb), .m_axi_wvalid(uart_wvalid),
        .m_axi_wready(uart_wready), .m_axi_bresp(uart_bresp),
        .m_axi_bvalid(uart_bvalid), .m_axi_bready(uart_bready),
        .m_axi_araddr(uart_araddr), .m_axi_arvalid(uart_arvalid),
        .m_axi_arready(uart_arready), .m_axi_rdata(uart_rdata),
        .m_axi_rresp(uart_rresp), .m_axi_rvalid(uart_rvalid),
        .m_axi_rready(uart_rready)
    );

    // Configure for 115200 baud and the actual CPU clock (50 MHz by default).
    axi_uartlite_0 U_uart (
        .s_axi_aclk(aclk), .s_axi_aresetn(aresetn),
        .s_axi_awaddr(uart_awaddr[3:0]), .s_axi_awvalid(uart_awvalid),
        .s_axi_awready(uart_awready), .s_axi_wdata(uart_wdata),
        .s_axi_wstrb(uart_wstrb), .s_axi_wvalid(uart_wvalid),
        .s_axi_wready(uart_wready), .s_axi_bresp(uart_bresp),
        .s_axi_bvalid(uart_bvalid), .s_axi_bready(uart_bready),
        .s_axi_araddr(uart_araddr[3:0]), .s_axi_arvalid(uart_arvalid),
        .s_axi_arready(uart_arready), .s_axi_rdata(uart_rdata),
        .s_axi_rresp(uart_rresp), .s_axi_rvalid(uart_rvalid),
        .s_axi_rready(uart_rready), .rx(rx), .tx(tx),
        .interrupt(unused_interrupt)
    );
endmodule
`endif
