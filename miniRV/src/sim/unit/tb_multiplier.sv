`timescale 1ns/1ps
module tb_multiplier;
    reg clk=0,rst=1,start=0; reg [31:0] x,y; wire [63:0] z; wire busy; integer errors=0;
    always #1 clk=~clk;
    multiplier #(32) dut(.*);
    task run(input [31:0] a,input [31:0] b,input [63:0] expected,input string name);
        begin x=a;y=b;@(negedge clk);start=1;@(negedge clk);start=0; wait(busy); wait(!busy); #1;
        if(z!==expected) begin $display("FAIL %s got=%h expected=%h",name,z,expected);errors=errors+1;end end
    endtask
    initial begin repeat(2) @(negedge clk);rst=0;
        run(7,9,64'd63,"positive"); run(-26,5,-64'sd130,"negative"); run(32'h80000000,2,64'hffffffff00000000,"minint");
        if(errors==0)$display("PASS tb_multiplier");else $fatal(1,"%0d failures",errors);$finish;end
endmodule

