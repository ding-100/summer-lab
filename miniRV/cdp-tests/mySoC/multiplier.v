`timescale 1ns / 1ps

module multiplier #(
    parameter WIDTH = 32,
    parameter O_WID = 2 * WIDTH
)(
    input wire clk, input wire rst,
    input wire [WIDTH-1:0] x, input wire [WIDTH-1:0] y,
    input wire start, output reg [O_WID-1:0] z, output reg busy
);
    localparam COUNT_W = $clog2(WIDTH + 1);
    reg [O_WID-1:0] acc, multiplicand;
    reg [WIDTH-1:0] multiplier_mag;
    reg [COUNT_W-1:0] count;
    reg negative;
    wire [WIDTH-1:0] x_mag = x[WIDTH-1] ? (~x + 1'b1) : x;
    wire [WIDTH-1:0] y_mag = y[WIDTH-1] ? (~y + 1'b1) : y;
    wire [O_WID-1:0] acc_next = acc + (multiplier_mag[0] ? multiplicand : {O_WID{1'b0}});

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            z<=0; busy<=0; acc<=0; multiplicand<=0; multiplier_mag<=0; count<=0; negative<=0;
        end else if (start && !busy) begin
            acc<=0; multiplicand<={{WIDTH{1'b0}},x_mag}; multiplier_mag<=y_mag;
            count<=0; negative<=x[WIDTH-1]^y[WIDTH-1]; busy<=1;
        end else if (busy) begin
            if (count == WIDTH-1) begin
                z <= negative ? (~acc_next + 1'b1) : acc_next;
                busy <= 0;
            end else begin
                acc <= acc_next;
                multiplicand <= multiplicand << 1;
                multiplier_mag <= multiplier_mag >> 1;
                count <= count + 1'b1;
            end
        end
    end
endmodule

