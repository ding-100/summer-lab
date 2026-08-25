`timescale 1ns / 1ps

`ifndef RUN_TRACE
module led_wrap(
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
    input wire s_axi_rready, output wire [15:0] led_o
);
    wire [31:0] gpio_awaddr, gpio_wdata, gpio_araddr, gpio_rdata;
    wire [3:0] gpio_wstrb;
    wire gpio_awready, gpio_awvalid, gpio_wready, gpio_wvalid;
    wire gpio_bready, gpio_bvalid, gpio_arready, gpio_arvalid;
    wire gpio_rready, gpio_rvalid;
    wire [1:0] gpio_bresp, gpio_rresp;

    axi_protocol_converter_0 U_led_converter (
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
        .m_axi_awaddr(gpio_awaddr), .m_axi_awvalid(gpio_awvalid),
        .m_axi_awready(gpio_awready), .m_axi_wdata(gpio_wdata),
        .m_axi_wstrb(gpio_wstrb), .m_axi_wvalid(gpio_wvalid),
        .m_axi_wready(gpio_wready), .m_axi_bresp(gpio_bresp),
        .m_axi_bvalid(gpio_bvalid), .m_axi_bready(gpio_bready),
        .m_axi_araddr(gpio_araddr), .m_axi_arvalid(gpio_arvalid),
        .m_axi_arready(gpio_arready), .m_axi_rdata(gpio_rdata),
        .m_axi_rresp(gpio_rresp), .m_axi_rvalid(gpio_rvalid),
        .m_axi_rready(gpio_rready)
    );

    // Configure axi_gpio_2 as 16-bit, all-output GPIO.
    axi_gpio_2 U_led (
        .s_axi_aclk(aclk), .s_axi_aresetn(aresetn),
        .s_axi_awaddr(gpio_awaddr[8:0]), .s_axi_awready(gpio_awready),
        .s_axi_awvalid(gpio_awvalid), .s_axi_wdata(gpio_wdata),
        .s_axi_wready(gpio_wready), .s_axi_wstrb(gpio_wstrb),
        .s_axi_wvalid(gpio_wvalid), .s_axi_bready(gpio_bready),
        .s_axi_bresp(gpio_bresp), .s_axi_bvalid(gpio_bvalid),
        .s_axi_araddr(gpio_araddr[8:0]), .s_axi_arready(gpio_arready),
        .s_axi_arvalid(gpio_arvalid), .s_axi_rdata(gpio_rdata),
        .s_axi_rready(gpio_rready), .s_axi_rresp(gpio_rresp),
        .s_axi_rvalid(gpio_rvalid), .gpio_io_o(led_o)
    );
endmodule
`endif
