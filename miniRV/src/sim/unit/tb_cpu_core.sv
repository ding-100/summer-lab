`timescale 1ns/1ps
module tb_cpu_core;
    reg cpu_clk=0,cpu_rst=1;
    wire ifetch_req; wire [31:0] ifetch_addr; reg ifetch_valid=0; reg [31:0] ifetch_inst=0;
    wire [3:0] daccess_ren,daccess_wen; wire [31:0] daccess_addr,daccess_wdata;
    reg daccess_rvalid=0,daccess_wresp=0; reg [31:0] daccess_rdata=0;
    reg [31:0] imem[0:15]; reg [31:0] dmem[0:15]; integer errors=0, cycles=0, i;
    always #1 cpu_clk=~cpu_clk;
    cpu_core dut(.*);

    function automatic [31:0] enc_r(input [6:0] f7,input [4:0] rs2,input [4:0] rs1,input [2:0] f3,input [4:0] rd);
        enc_r={f7,rs2,rs1,f3,rd,7'b0110011};
    endfunction
    function automatic [31:0] enc_i(input integer imm,input [4:0] rs1,input [2:0] f3,input [4:0] rd,input [6:0] opc);
        enc_i={imm[11:0],rs1,f3,rd,opc};
    endfunction
    function automatic [31:0] enc_s(input integer imm,input [4:0] rs2,input [4:0] rs1,input [2:0] f3);
        enc_s={imm[11:5],rs2,rs1,f3,imm[4:0],7'b0100011};
    endfunction
    function automatic [31:0] enc_b(input integer imm,input [4:0] rs2,input [4:0] rs1,input [2:0] f3);
        enc_b={imm[12],imm[10:5],rs2,rs1,f3,imm[4:1],imm[11],7'b1100011};
    endfunction

    always @(posedge cpu_clk) begin
        cycles <= cycles+1; ifetch_valid<=0; daccess_rvalid<=0; daccess_wresp<=0;
        if(ifetch_req) begin ifetch_inst<=imem[ifetch_addr[5:2]]; ifetch_valid<=1; end
        if(|daccess_wen) begin
            if(daccess_wen[0])dmem[daccess_addr[5:2]][7:0]<=daccess_wdata[7:0];
            if(daccess_wen[1])dmem[daccess_addr[5:2]][15:8]<=daccess_wdata[15:8];
            if(daccess_wen[2])dmem[daccess_addr[5:2]][23:16]<=daccess_wdata[23:16];
            if(daccess_wen[3])dmem[daccess_addr[5:2]][31:24]<=daccess_wdata[31:24];
            daccess_wresp<=1;
        end
        if(|daccess_ren) begin daccess_rdata<=dmem[daccess_addr[5:2]]; daccess_rvalid<=1; end
        if(cycles>700)$fatal(1,"core timeout pc=%h",ifetch_addr);
    end

    task check(input bit ok,input string name);if(!ok)begin $display("FAIL %s",name);errors=errors+1;end endtask
    initial begin
        for(i=0;i<16;i=i+1)begin imem[i]=32'h00000013;dmem[i]=0;end
        imem[0]=enc_i(5,0,3'b000,1,7'b0010011);       // addi x1,x0,5
        imem[1]=enc_i(3,0,3'b000,2,7'b0010011);       // addi x2,x0,3
        imem[2]=enc_r(0,2,1,3'b000,3);                 // add x3,x1,x2
        imem[3]=enc_r(7'b0100000,2,1,3'b000,4);        // sub x4,x1,x2
        imem[4]=enc_b(8,3,3,3'b000);                   // beq x3,x3,+8
        imem[5]=enc_i(99,0,3'b000,4,7'b0010011);       // skipped
        imem[6]=enc_s(0,3,0,3'b010);                   // sw x3,0(x0)
        imem[7]=enc_i(0,0,3'b000,5,7'b0000011);        // lb x5,0(x0)
        imem[8]=enc_r(7'b0000001,2,1,3'b000,6);        // mul x6,x1,x2
        imem[9]=enc_r(7'b0000001,2,1,3'b100,7);        // div x7,x1,x2
        imem[10]=enc_i(77,0,3'b000,11,7'b0010011);     // addi x11,x0,77
        imem[11]=enc_i(2,0,3'b010,11,7'b0000011);      // unaligned lw: no request/write
        imem[12]=enc_i(9,0,3'b000,12,7'b0010011);      // must continue
        imem[13]={20'h0,5'd13,7'b0010111};              // auipc x13,0 (PC=52)
        imem[14]=enc_i(8,13,3'b000,14,7'b1100111);     // jalr x14,x13,8 -> PC=60
        imem[15]=enc_i(1,0,3'b000,15,7'b0010011);      // jump target
        repeat(3)@(negedge cpu_clk);cpu_rst=0;
        wait(dut.U_RF.regs[15]===32'd1); #2;
        check(dut.U_RF.regs[3]===8,"ADD writeback"); check(dut.U_RF.regs[4]===2,"branch skip");
        check(dmem[0]===8,"SW data"); check(dut.U_RF.regs[5]===8,"LB data");
        check(dut.U_RF.regs[6]===15,"MUL writeback"); check(dut.U_RF.regs[7]===1,"DIV writeback");
        check(dut.U_RF.regs[11]===77,"unaligned LW has no writeback"); check(dut.U_RF.regs[12]===9,"unaligned LW advances");
        check(dut.U_RF.regs[13]===52,"AUIPC writeback"); check(dut.U_RF.regs[14]===60,"JALR link");
        if(errors==0)$display("PASS tb_cpu_core");else $fatal(1,"%0d failures",errors);$finish;
    end
endmodule
