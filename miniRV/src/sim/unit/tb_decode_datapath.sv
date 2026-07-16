`timescale 1ns/1ps
`include "defines.vh"

module tb_decode_datapath;
    reg [6:0] opcode, funct7;
    reg [2:0] funct3;
    wire [1:0] npc_op, rf_wsel;
    wire [2:0] sext_op, ram_r_op;
    wire [3:0] ram_w_op;
    wire [4:0] alu_op;
    wire alua_sel, alub_sel, is_mul, is_div, rf_we;
    reg [31:7] imm;
    wire [31:0] ext;
    reg [31:0] pc, offset, base, a, b;
    reg br;
    wire [31:0] npc, pc4, c;
    wire alu_br, busy;
    reg clk=0, rst=1;
    integer errors = 0;

    Controller cu(.*);
    SEXT sext(.op(sext_op), .imm(imm), .ext(ext));
    NPC npc_u(.op(npc_op), .pc(pc), .base(base), .offset(offset), .br(br), .npc(npc), .pc4(pc4));
    always #0.5 clk=~clk;
    ALU alu(.rst(rst), .clk(clk), .op(alu_op), .a(a), .b(b), .c(c), .br(alu_br), .busy(busy));

    task check(input bit ok, input string name);
        if (!ok) begin $display("FAIL %s", name); errors = errors + 1; end
    endtask
    task decode(input [6:0] op, input [2:0] f3, input [6:0] f7);
        begin opcode=op; funct3=f3; funct7=f7; #1; end
    endtask
    task expect_ctl(input [6:0] opc,input [2:0] f3,input [6:0] f7,input [4:0] aop,
                    input bit we,input bit mul,input bit div,input string name);
        begin decode(opc,f3,f7); check(alu_op==aop && rf_we==we && is_mul==mul && is_div==div,name); end
    endtask

    initial begin
        #1; rst=0;
        imm = '0; imm[31:25]=7'h7f; imm[11:7]=5'h1f;
        decode(7'b0100011, 3'b010, 7'b1111111);
        check(sext_op == `EXT_S && ext == 32'hffff_ffff, "S immediate");
        check(ram_w_op == `RAM_WE_W && !rf_we, "SW decode");

        decode(7'b1100111, 3'b000, 0);
        check(npc_op == `NPC_JALR && rf_we && rf_wsel == `WB_PC4, "JALR decode");
        pc=32'h100; base=32'h205; offset=32'hfffffffc; br=0; #1;
        check(npc == 32'h200, "JALR target clears bit0");

        a=32'h80000000; b=32'h1;
        decode(7'b0110011,3'b000,7'b0100000); #1; check(alu_op==`ALU_SUB && c==32'h7fffffff,"SUB");
        decode(7'b0110011,3'b100,7'b0000000); #1; check(alu_op==`ALU_XOR && c==32'h80000001,"XOR");
        decode(7'b0110011,3'b101,7'b0000000); b=1; #1; check(alu_op==`ALU_SRL && c==32'h40000000,"SRL");
        decode(7'b0110011,3'b101,7'b0100000); #1; check(alu_op==`ALU_SRA && c==32'hc0000000,"SRA");
        decode(7'b0110011,3'b010,7'b0000000); b=0; #1; check(alu_op==`ALU_SLT && c==1,"SLT signed");
        decode(7'b0110011,3'b011,7'b0000000); #1; check(alu_op==`ALU_SLTU && c==0,"SLTU unsigned");

        decode(7'b0010011,3'b111,7'b0000000); a=32'hf0; b=32'h0f; #1; check(alu_op==`ALU_AND && c==0,"ANDI");
        decode(7'b0010011,3'b010,7'b0000000); a=-2; b=1; #1; check(alu_op==`ALU_SLT && c==1,"SLTI");
        decode(7'b0010011,3'b011,7'b0000000); #1; check(alu_op==`ALU_SLTU && c==0,"SLTIU");

        decode(7'b1100011,3'b100,0); a=-1; b=1; #1; check(npc_op==`NPC_BRA && alu_br,"BLT");
        decode(7'b1100011,3'b111,0); a=32'hffffffff; b=1; #1; check(alu_br,"BGEU");

        decode(7'b0010111,0,0); check(alua_sel==`ALU_A_PC && alub_sel==`ALU_B_EXT && rf_we,"AUIPC");

        // 逐条覆盖 37 条基础指令与 7 条 M 扩展指令。
        expect_ctl(7'b0110011,3'b000,7'b0000000,`ALU_ADD, 1,0,0,"ADD ctl");
        expect_ctl(7'b0110011,3'b000,7'b0100000,`ALU_SUB, 1,0,0,"SUB ctl");
        expect_ctl(7'b0110011,3'b111,7'b0000000,`ALU_AND, 1,0,0,"AND ctl");
        expect_ctl(7'b0110011,3'b110,7'b0000000,`ALU_OR,  1,0,0,"OR ctl");
        expect_ctl(7'b0110011,3'b100,7'b0000000,`ALU_XOR, 1,0,0,"XOR ctl");
        expect_ctl(7'b0110011,3'b001,7'b0000000,`ALU_SLL, 1,0,0,"SLL ctl");
        expect_ctl(7'b0110011,3'b101,7'b0000000,`ALU_SRL, 1,0,0,"SRL ctl");
        expect_ctl(7'b0110011,3'b101,7'b0100000,`ALU_SRA, 1,0,0,"SRA ctl");
        expect_ctl(7'b0110011,3'b010,7'b0000000,`ALU_SLT, 1,0,0,"SLT ctl");
        expect_ctl(7'b0110011,3'b011,7'b0000000,`ALU_SLTU,1,0,0,"SLTU ctl");

        expect_ctl(7'b0010011,3'b000,0,`ALU_ADD, 1,0,0,"ADDI ctl");
        expect_ctl(7'b0010011,3'b111,0,`ALU_AND, 1,0,0,"ANDI ctl");
        expect_ctl(7'b0010011,3'b110,0,`ALU_OR,  1,0,0,"ORI ctl");
        expect_ctl(7'b0010011,3'b100,0,`ALU_XOR, 1,0,0,"XORI ctl");
        expect_ctl(7'b0010011,3'b001,0,`ALU_SLL, 1,0,0,"SLLI ctl");
        expect_ctl(7'b0010011,3'b101,0,`ALU_SRL, 1,0,0,"SRLI ctl");
        expect_ctl(7'b0010011,3'b101,7'b0100000,`ALU_SRA,1,0,0,"SRAI ctl");
        expect_ctl(7'b0010011,3'b010,0,`ALU_SLT, 1,0,0,"SLTI ctl");
        expect_ctl(7'b0010011,3'b011,0,`ALU_SLTU,1,0,0,"SLTIU ctl");

        expect_ctl(7'b0000011,3'b000,0,`ALU_ADD,1,0,0,"LB ctl");  check(ram_r_op==`RAM_EXT_B,"LB rop");
        expect_ctl(7'b0000011,3'b100,0,`ALU_ADD,1,0,0,"LBU ctl"); check(ram_r_op==`RAM_EXT_BU,"LBU rop");
        expect_ctl(7'b0000011,3'b001,0,`ALU_ADD,1,0,0,"LH ctl");  check(ram_r_op==`RAM_EXT_H,"LH rop");
        expect_ctl(7'b0000011,3'b101,0,`ALU_ADD,1,0,0,"LHU ctl"); check(ram_r_op==`RAM_EXT_HU,"LHU rop");
        expect_ctl(7'b0000011,3'b010,0,`ALU_ADD,1,0,0,"LW ctl");  check(ram_r_op==`RAM_EXT_W,"LW rop");
        expect_ctl(7'b0100011,3'b000,0,`ALU_ADD,0,0,0,"SB ctl");  check(ram_w_op==`RAM_WE_B,"SB wop");
        expect_ctl(7'b0100011,3'b001,0,`ALU_ADD,0,0,0,"SH ctl");  check(ram_w_op==`RAM_WE_H,"SH wop");
        expect_ctl(7'b0100011,3'b010,0,`ALU_ADD,0,0,0,"SW ctl");  check(ram_w_op==`RAM_WE_W,"SW wop");

        expect_ctl(7'b1100011,3'b000,0,`ALU_EQ, 0,0,0,"BEQ ctl");
        expect_ctl(7'b1100011,3'b001,0,`ALU_NE, 0,0,0,"BNE ctl");
        expect_ctl(7'b1100011,3'b100,0,`ALU_LT, 0,0,0,"BLT ctl");
        expect_ctl(7'b1100011,3'b101,0,`ALU_GE, 0,0,0,"BGE ctl");
        expect_ctl(7'b1100011,3'b110,0,`ALU_LTU,0,0,0,"BLTU ctl");
        expect_ctl(7'b1100011,3'b111,0,`ALU_GEU,0,0,0,"BGEU ctl");
        expect_ctl(7'b0110111,0,0,`ALU_ADD,1,0,0,"LUI ctl");
        expect_ctl(7'b0010111,0,0,`ALU_ADD,1,0,0,"AUIPC ctl");
        expect_ctl(7'b1101111,0,0,`ALU_ADD,1,0,0,"JAL ctl");
        expect_ctl(7'b1100111,0,0,`ALU_ADD,1,0,0,"JALR ctl");

        expect_ctl(7'b0110011,3'b000,7'b0000001,`ALU_MUL,  1,1,0,"MUL ctl");
        expect_ctl(7'b0110011,3'b001,7'b0000001,`ALU_MULH, 1,1,0,"MULH ctl");
        expect_ctl(7'b0110011,3'b011,7'b0000001,`ALU_MULHU,1,1,0,"MULHU ctl");
        expect_ctl(7'b0110011,3'b100,7'b0000001,`ALU_DIV,  1,0,1,"DIV ctl");
        expect_ctl(7'b0110011,3'b101,7'b0000001,`ALU_DIVU, 1,0,1,"DIVU ctl");
        expect_ctl(7'b0110011,3'b110,7'b0000001,`ALU_REM,  1,0,1,"REM ctl");
        expect_ctl(7'b0110011,3'b111,7'b0000001,`ALU_REMU, 1,0,1,"REMU ctl");

        if (errors == 0) $display("PASS tb_decode_datapath");
        else $fatal(1, "%0d failures", errors);
        $finish;
    end
endmodule
