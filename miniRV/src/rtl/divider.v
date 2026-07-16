`timescale 1ns / 1ps

module divider #(parameter WIDTH = 32)(
    input wire clk, input wire rst,
    input wire [WIDTH-1:0] x, input wire [WIDTH-1:0] y,
    input wire start, output reg [WIDTH-1:0] z, output reg [WIDTH-1:0] r,
    output reg busy
);
    localparam COUNT_W = $clog2(WIDTH + 1);
    reg [WIDTH-1:0] dividend, divisor, quotient, remainder;
    reg [COUNT_W-1:0] count;
    wire [WIDTH:0] shifted_rem = {remainder, dividend[WIDTH-1]};
    wire ge_divisor = shifted_rem >= {1'b0, divisor};
    wire [WIDTH-1:0] next_rem = ge_divisor ? shifted_rem[WIDTH-1:0] - divisor : shifted_rem[WIDTH-1:0];
    wire [WIDTH-1:0] next_quot = {quotient[WIDTH-2:0], ge_divisor};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            z<=0; r<=0; busy<=0; dividend<=0; divisor<=0; quotient<=0; remainder<=0; count<=0;
        end else if (start && !busy) begin
            if (y == 0) begin z<={WIDTH{1'b1}}; r<=x; busy<=1; count<=WIDTH; end
            else begin dividend<=x; divisor<=y; quotient<=0; remainder<=0; count<=0; busy<=1; end
        end else if (busy) begin
            if (count == WIDTH) busy <= 0;
            else begin
                dividend <= dividend << 1; quotient <= next_quot; remainder <= next_rem;
                if (count == WIDTH-1) begin z<=next_quot; r<=next_rem; busy<=0; end
                count <= count + 1'b1;
            end
        end
    end
endmodule

