`timescale 1ns / 1ps
`include "defines.vh"

module Controller (
    input wire [6:0] opcode, input wire [2:0] funct3, input wire [6:0] funct7,
    output reg [1:0] npc_op, output reg [2:0] sext_op,
    output reg alua_sel, output reg alub_sel, output reg [4:0] alu_op,
    output reg is_mul, output reg is_div,
    output reg [2:0] ram_r_op, output reg [3:0] ram_w_op,
    output reg rf_we, output reg [1:0] rf_wsel
);
    localparam OP      = 7'b0110011, OP_IMM = 7'b0010011;
    localparam LOAD    = 7'b0000011, STORE  = 7'b0100011;
    localparam BRANCH  = 7'b1100011, JAL    = 7'b1101111, JALR = 7'b1100111;
    localparam LUI     = 7'b0110111, AUIPC  = 7'b0010111;

    always @(*) begin
        npc_op=`NPC_PC4; sext_op=`EXT_I; alua_sel=`ALU_A_RS1; alub_sel=`ALU_B_RS2;
        alu_op=`ALU_ADD; is_mul=0; is_div=0; ram_r_op=`RAM_EXT_N; ram_w_op=`RAM_WE_N;
        rf_we=0; rf_wsel=`WB_ALU;
        case (opcode)
            OP: begin
                rf_we=1;
                if (funct7 == 7'b0000001) begin
                    case (funct3)
                        3'b000: begin alu_op=`ALU_MUL;   is_mul=1; end
                        3'b001: begin alu_op=`ALU_MULH;  is_mul=1; end
                        3'b011: begin alu_op=`ALU_MULHU; is_mul=1; end
                        3'b100: begin alu_op=`ALU_DIV;   is_div=1; end
                        3'b101: begin alu_op=`ALU_DIVU;  is_div=1; end
                        3'b110: begin alu_op=`ALU_REM;   is_div=1; end
                        3'b111: begin alu_op=`ALU_REMU;  is_div=1; end
                        default: begin rf_we=0; alu_op=`ALU_ADD; end
                    endcase
                end else begin
                    case (funct3)
                        3'b000: alu_op = funct7[5] ? `ALU_SUB : `ALU_ADD;
                        3'b001: alu_op = `ALU_SLL;
                        3'b010: alu_op = `ALU_SLT;
                        3'b011: alu_op = `ALU_SLTU;
                        3'b100: alu_op = `ALU_XOR;
                        3'b101: alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;
                        3'b110: alu_op = `ALU_OR;
                        3'b111: alu_op = `ALU_AND;
                    endcase
                end
            end
            OP_IMM: begin
                rf_we=1; sext_op=`EXT_I; alub_sel=`ALU_B_EXT;
                case (funct3)
                    3'b000: alu_op=`ALU_ADD;
                    3'b010: alu_op=`ALU_SLT;
                    3'b011: alu_op=`ALU_SLTU;
                    3'b100: alu_op=`ALU_XOR;
                    3'b110: alu_op=`ALU_OR;
                    3'b111: alu_op=`ALU_AND;
                    3'b001: alu_op=`ALU_SLL;
                    3'b101: alu_op=funct7[5] ? `ALU_SRA : `ALU_SRL;
                endcase
            end
            LOAD: begin
                rf_we=1; rf_wsel=`WB_RAM; sext_op=`EXT_I; alub_sel=`ALU_B_EXT; alu_op=`ALU_ADD;
                case(funct3)
                    3'b000: ram_r_op=`RAM_EXT_B; 3'b001: ram_r_op=`RAM_EXT_H;
                    3'b010: ram_r_op=`RAM_EXT_W; 3'b100: ram_r_op=`RAM_EXT_BU;
                    3'b101: ram_r_op=`RAM_EXT_HU; default: begin ram_r_op=`RAM_EXT_N; rf_we=0; end
                endcase
            end
            STORE: begin
                sext_op=`EXT_S; alub_sel=`ALU_B_EXT; alu_op=`ALU_ADD;
                case(funct3)
                    3'b000: ram_w_op=`RAM_WE_B; 3'b001: ram_w_op=`RAM_WE_H;
                    3'b010: ram_w_op=`RAM_WE_W; default: ram_w_op=`RAM_WE_N;
                endcase
            end
            BRANCH: begin
                npc_op=`NPC_BRA; sext_op=`EXT_B;
                case(funct3)
                    3'b000: alu_op=`ALU_EQ;  3'b001: alu_op=`ALU_NE;
                    3'b100: alu_op=`ALU_LT;  3'b101: alu_op=`ALU_GE;
                    3'b110: alu_op=`ALU_LTU; 3'b111: alu_op=`ALU_GEU;
                    default: npc_op=`NPC_PC4;
                endcase
            end
            LUI: begin rf_we=1; rf_wsel=`WB_EXT; sext_op=`EXT_U; end
            AUIPC: begin rf_we=1; sext_op=`EXT_U; alua_sel=`ALU_A_PC; alub_sel=`ALU_B_EXT; alu_op=`ALU_ADD; end
            JAL: begin rf_we=1; rf_wsel=`WB_PC4; sext_op=`EXT_J; npc_op=`NPC_JMP; end
            JALR: begin
                if(funct3==0) begin rf_we=1; rf_wsel=`WB_PC4; sext_op=`EXT_I; npc_op=`NPC_JALR; end
            end
        endcase
    end
endmodule

