`timescale 1ns / 1ps

// Behavioral/synthesizable replacement for the 64-line cache SRAM IP.
// The Trace framework provides its own module with this name, so exclude this
// definition there.
`ifndef RUN_TRACE
module blk_mem_gen_1 #(
    parameter ADDR_BITS = 6,
    parameter DATA_BITS = 151
)(
    input  wire         clka,
    input  wire         wea,
    input  wire [ADDR_BITS-1:0] addra,
    input  wire [DATA_BITS-1:0] dina,
    output reg  [DATA_BITS-1:0] douta
);
    reg [DATA_BITS-1:0] mem [0:(1 << ADDR_BITS)-1];
    integer i;

    initial begin
        douta = {DATA_BITS{1'b0}};
        for (i = 0; i < (1 << ADDR_BITS); i = i + 1)
            mem[i] = {DATA_BITS{1'b0}};
    end

    always @(posedge clka) begin
        if (wea)
            mem[addra] <= dina;
        douta <= wea ? dina : mem[addra];
    end
endmodule
`endif
