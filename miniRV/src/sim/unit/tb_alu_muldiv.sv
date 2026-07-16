`timescale 1ns/1ps
`include "defines.vh"
module tb_alu_muldiv;
    reg clk=0,rst=1; reg [4:0] op=`ALU_ADD; reg [31:0] a=0,b=0; wire [31:0] c; wire br,busy; integer errors=0;
    always #1 clk=~clk;
    ALU dut(.*);
    task run(input [4:0] iop,input [31:0] ia,input [31:0] ib,input [31:0] expected,input string name);
        begin @(negedge clk);op=iop;a=ia;b=ib;@(negedge clk);op=`ALU_ADD;a=0;b=0;wait(busy);wait(!busy);#0.1;
        if(c!==expected)begin $display("FAIL %s got=%h expected=%h",name,c,expected);errors=errors+1;end
        @(negedge clk); end
    endtask
    initial begin repeat(2)@(negedge clk);rst=0;
        run(`ALU_MUL,-26,5,32'hffffff7e,"MUL signed low");
        run(`ALU_MULH,-26,5,32'hffffffff,"MULH signed high");
        run(`ALU_MULHU,32'hfffffffe,5,4,"MULHU unsigned high");
        run(`ALU_DIV,-26,5,32'hfffffffb,"DIV signed");
        run(`ALU_REM,-26,5,32'hffffffff,"REM signed");
        run(`ALU_DIVU,32'hffffffe6,5,32'h3333332e,"DIVU");
        run(`ALU_REMU,32'hffffffe6,5,0,"REMU");
        run(`ALU_DIV,-26,0,32'hffffffff,"DIV zero");
        run(`ALU_REM,-26,0,32'hffffffe6,"REM zero");
        run(`ALU_DIV,32'h80000000,32'hffffffff,32'h80000000,"DIV overflow");
        run(`ALU_REM,32'h80000000,32'hffffffff,0,"REM overflow");
        if(errors==0)$display("PASS tb_alu_muldiv");else $fatal(1,"%0d failures",errors);$finish;end
endmodule

