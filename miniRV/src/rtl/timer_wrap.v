`timescale 1ns / 1ps

`ifndef RUN_TRACE
module timer_wrap(
    input  wire         aclk,
    input  wire         aresetn,
    input  wire [31:0]  s_axi_awaddr,
    input  wire [ 7:0]  s_axi_awlen,
    input  wire [ 2:0]  s_axi_awsize,
    input  wire [ 1:0]  s_axi_awburst,
    input  wire [ 0:0]  s_axi_awlock,
    input  wire [ 3:0]  s_axi_awcache,
    input  wire [ 2:0]  s_axi_awprot,
    input  wire [ 3:0]  s_axi_awregion,
    input  wire [ 3:0]  s_axi_awqos,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [ 3:0]  s_axi_wstrb,
    input  wire         s_axi_wlast,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [ 1:0]  s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [31:0]  s_axi_araddr,
    input  wire [ 7:0]  s_axi_arlen,
    input  wire [ 2:0]  s_axi_arsize,
    input  wire [ 1:0]  s_axi_arburst,
    input  wire [ 0:0]  s_axi_arlock,
    input  wire [ 3:0]  s_axi_arcache,
    input  wire [ 2:0]  s_axi_arprot,
    input  wire [ 3:0]  s_axi_arregion,
    input  wire [ 3:0]  s_axi_arqos,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [31:0]  s_axi_rdata,
    output wire [ 1:0]  s_axi_rresp,
    output wire         s_axi_rlast,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready
);
    reg [63:0] timer;
    always @(posedge aclk or negedge aresetn) begin
        timer <= !aresetn ? 64'h0 : timer + 64'h1;
    end

    wire [31:0] timer_awaddr, timer_wdata, timer_araddr, timer_rdata;
    wire [3:0]  timer_wstrb;
    wire timer_awready, timer_awvalid, timer_wready, timer_wvalid;
    wire timer_bready, timer_bvalid, timer_arready, timer_arvalid;
    wire timer_rready, timer_rvalid;
    wire [1:0] timer_bresp, timer_rresp;

    axi_protocol_converter_0 U_timer_converter (
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
        .m_axi_awaddr(timer_awaddr), .m_axi_awvalid(timer_awvalid),
        .m_axi_awready(timer_awready), .m_axi_wdata(timer_wdata),
        .m_axi_wstrb(timer_wstrb), .m_axi_wvalid(timer_wvalid),
        .m_axi_wready(timer_wready), .m_axi_bresp(timer_bresp),
        .m_axi_bvalid(timer_bvalid), .m_axi_bready(timer_bready),
        .m_axi_araddr(timer_araddr), .m_axi_arvalid(timer_arvalid),
        .m_axi_arready(timer_arready), .m_axi_rdata(timer_rdata),
        .m_axi_rresp(timer_rresp), .m_axi_rvalid(timer_rvalid),
        .m_axi_rready(timer_rready)
    );

    // Configure axi_gpio_0 as dual-channel, 32-bit, all-input GPIO.
    axi_gpio_0 U_timer (
        .s_axi_aclk(aclk), .s_axi_aresetn(aresetn),
        .s_axi_awaddr(timer_awaddr[8:0]), .s_axi_awready(timer_awready),
        .s_axi_awvalid(timer_awvalid), .s_axi_wdata(timer_wdata),
        .s_axi_wready(timer_wready), .s_axi_wstrb(timer_wstrb),
        .s_axi_wvalid(timer_wvalid), .s_axi_bready(timer_bready),
        .s_axi_bresp(timer_bresp), .s_axi_bvalid(timer_bvalid),
        .s_axi_araddr(timer_araddr[8:0]), .s_axi_arready(timer_arready),
        .s_axi_arvalid(timer_arvalid), .s_axi_rdata(timer_rdata),
        .s_axi_rready(timer_rready), .s_axi_rresp(timer_rresp),
        .s_axi_rvalid(timer_rvalid),
        .gpio2_io_i(timer[63:32]), .gpio_io_i(timer[31:0])
    );
endmodule
`endif
