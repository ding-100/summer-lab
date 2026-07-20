`timescale 1ns / 1ps
`include "defines.vh"

module ALU (
    input wire rst, 
    input wire clk, 
    input wire [4:0] op,
    input wire [31:0] a, 
    input wire [31:0] b,
    output reg [31:0] c, 
    output reg br, 
    output wire busy
);
    wire mul_start = op==`ALU_MUL || op==`ALU_MULH;
    wire mulu_start = op==`ALU_MULHU;
    wire div_start = op==`ALU_DIV || op==`ALU_REM;
    wire divu_start = op==`ALU_DIVU || op==`ALU_REMU;
    wire [31:0] abs_a = a[31] ? (~a + 1'b1) : a;
    wire [31:0] abs_b = b[31] ? (~b + 1'b1) : b;
    wire [63:0] mul_res;
    wire [65:0] mulu_res;
    wire [31:0] div_quo, div_rem, divu_quo, divu_rem;
    wire mul_busy, mulu_busy, div_busy, divu_busy;
    reg [4:0] op_r;
    reg div_q_neg, div_r_neg, div_by_zero;
    reg [31:0] dividend_r;
    wire [4:0] active_op = (op_r >= `ALU_MUL) ? op_r : op;
    assign busy = mul_busy | mulu_busy | div_busy | divu_busy;

    always @(*) begin
        c=0;
        case(active_op)
            `ALU_ADD: c=a+b; 
            `ALU_SUB: c=a-b; 
            `ALU_AND: c=a&b; 
            `ALU_OR: c=a|b; 
            `ALU_XOR: c=a^b;
            `ALU_SLL: c=a<<b[4:0]; 
            `ALU_SRL: c=a>>b[4:0]; 
            `ALU_SRA: c=$signed(a)>>>b[4:0];
            `ALU_SLT: c={31'h0,$signed(a)<$signed(b)}; 
            `ALU_SLTU: c={31'h0,a<b};
            `ALU_MUL: c=mul_res[31:0]; 
            `ALU_MULH: c=mul_res[63:32]; 
            `ALU_MULHU: c=mulu_res[63:32];
            `ALU_DIV: c=div_by_zero ? 32'hffff_ffff : (div_q_neg ? (~div_quo+1'b1) : div_quo);
            `ALU_DIVU: c=divu_quo;
            `ALU_REM: c=div_by_zero ? dividend_r : (div_r_neg ? (~div_rem+1'b1) : div_rem);
            `ALU_REMU: c=divu_rem;
        endcase
    end
    always @(*) begin
        br=0;
        case(op)
            `ALU_EQ: br=a==b; 
            `ALU_NE: br=a!=b;
            `ALU_LT: br=$signed(a)<$signed(b); 
            `ALU_LTU: br=a<b;
            `ALU_GE: br=$signed(a)>=$signed(b); 
            `ALU_GEU: br=a>=b;
        endcase
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin op_r<=`ALU_ADD; 
            div_q_neg<=0; div_r_neg<=0; div_by_zero<=0; dividend_r<=0; 
            end
        else begin
            if(mul_start|mulu_start|div_start|divu_start) op_r<=op;
            else if(!busy) op_r<=`ALU_ADD;
            if(div_start) begin 
                div_q_neg<=a[31]^b[31]; 
                div_r_neg<=a[31]; 
                div_by_zero<=b==0; 
                dividend_r<=a; 
                end
        end
    end

    multiplier #(32) u_mul(.clk(clk),.rst(rst),.x(a),.y(b),.start(mul_start),.z(mul_res),.busy(mul_busy));
    multiplier #(33) u_mulu(.clk(clk),.rst(rst),.x({1'b0,a}),.y({1'b0,b}),.start(mulu_start),.z(mulu_res),.busy(mulu_busy));
    divider #(32) u_div(.clk(clk),.rst(rst),.x(abs_a),.y(abs_b),.start(div_start),.z(div_quo),.r(div_rem),.busy(div_busy));
    divider #(32) u_divu(.clk(clk),.rst(rst),.x(a),.y(b),.start(divu_start),.z(divu_quo),.r(divu_rem),.busy(divu_busy));
endmodule

