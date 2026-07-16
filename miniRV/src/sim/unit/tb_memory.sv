`timescale 1ns/1ps
`include "defines.vh"

module tb_memory;
    reg [31:0] ram_addr, ram_wdata, din;
    reg [2:0] ram_rop, op;
    reg [3:0] ram_wop;
    reg [1:0] byte_offs;
    wire [3:0] da_ren, da_wen;
    wire [31:0] da_addr, da_wdata, ext;
    integer errors=0;
    MREQ req(.*);
    MEXT mext(.op(op),.din(din),.byte_offs(byte_offs),.ext(ext));
    task check(input bit ok,input string name); if(!ok) begin $display("FAIL %s",name); errors=errors+1; end endtask
    initial begin
        ram_wdata=32'h11223344; ram_rop=`RAM_EXT_N;
        ram_wop=`RAM_WE_B; ram_addr=2; #1; check(da_wen==4'b0100 && da_wdata==32'h33440000,"SB offset2");
        ram_wdata=32'hffffffaa; ram_addr=0; #1; check(da_wen==4'b0001 && da_wdata==32'hffffffaa,"SB preserves source for trace");
        ram_wdata=32'h11223344;
        ram_wop=`RAM_WE_H; ram_addr=2; #1; check(da_wen==4'b1100 && da_wdata==32'h33440000,"SH offset2");
        ram_addr=1; #1; check(da_wen==0,"SH unaligned");
        ram_wop=`RAM_WE_W; ram_addr=0; #1; check(da_wen==4'hf && da_wdata==ram_wdata,"SW aligned");
        ram_addr=2; #1; check(da_wen==0,"SW unaligned");

        ram_wop=`RAM_WE_N; ram_rop=`RAM_EXT_B; ram_addr=3; #1; check(da_ren==4'hf,"LB any offset");
        ram_rop=`RAM_EXT_H; ram_addr=1; #1; check(da_ren==0,"LH unaligned");
        ram_addr=2; #1; check(da_ren==4'hf,"LH aligned");
        ram_rop=`RAM_EXT_W; ram_addr=2; #1; check(da_ren==0,"LW unaligned");

        din=32'h80ff7f01;
        op=`RAM_EXT_B; byte_offs=3; #1; check(ext==32'hffffff80,"LB sign");
        op=`RAM_EXT_BU; #1; check(ext==32'h80,"LBU zero");
        op=`RAM_EXT_H; byte_offs=2; #1; check(ext==32'hffff80ff,"LH sign");
        op=`RAM_EXT_HU; #1; check(ext==32'h80ff,"LHU zero");
        op=`RAM_EXT_W; byte_offs=0; #1; check(ext==din,"LW");
        if(errors==0) $display("PASS tb_memory"); else $fatal(1,"%0d failures",errors);
    end
endmodule
