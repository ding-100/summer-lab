`timescale 1ns/1ps
module tb_divider;
    reg clk=0,rst=1,start=0; reg [31:0] x,y; wire [31:0] z,r; wire busy; integer errors=0;
    always #1 clk=~clk;
    divider #(32) dut(.*);
    task run(input [31:0] a,input [31:0] b,input [31:0] eq,input [31:0] er,input string name);
        begin x=a;y=b;@(negedge clk);start=1;@(negedge clk);start=0;wait(busy);wait(!busy);#1;
        if(z!==eq||r!==er)begin $display("FAIL %s q=%h r=%h",name,z,r);errors=errors+1;end end
    endtask
    initial begin repeat(2)@(negedge clk);rst=0;
        run(100,7,14,2,"100/7"); run(32'hffffffff,16,32'h0fffffff,15,"unsigned max"); run(123,0,32'hffffffff,123,"divide zero");
        if(errors==0)$display("PASS tb_divider");else $fatal(1,"%0d failures",errors);$finish;end
endmodule

