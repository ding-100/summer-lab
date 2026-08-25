`timescale 1ns / 1ps

module HazardUnit (
    // ID-stage source usage and WB-to-ID bypass
    input  wire        id_valid,
    input  wire        id_use_rs1,
    input  wire        id_use_rs2,
    input  wire [ 4:0] id_rs1,
    input  wire [ 4:0] id_rs2,

    // EX-stage source usage and forwarding
    input  wire        ex_valid,
    input  wire        ex_use_rs1,
    input  wire        ex_use_rs2,
    input  wire [ 4:0] ex_rs1,
    input  wire [ 4:0] ex_rs2,

    // Producer in MEM
    input  wire        mem_valid,
    input  wire        mem_rf_we,
    input  wire        mem_value_ready,
    input  wire [ 4:0] mem_rd,

    // Producer in WB
    input  wire        wb_valid,
    input  wire        wb_rf_we,
    input  wire [ 4:0] wb_rd,

    // Long-latency and control hazards
    input  wire        id_can_advance,
    input  wire        id_is_long,
    input  wire        ex_long_block,
    input  wire        mem_long_block,
    input  wire        ex_fire,
    input  wire        branch_taken,

    output wire        id_forward_rs1_wb,
    output wire        id_forward_rs2_wb,
    output reg  [ 1:0] ex_forward_rs1_sel,
    output reg  [ 1:0] ex_forward_rs2_sel,
    output wire        fetch_pause,
    output wire        redirect_fire,
    output wire        flush_if_id,
    output wire        flush_id_ex
);

    localparam FWD_NONE = 2'b00;
    localparam FWD_WB   = 2'b01;
    localparam FWD_MEM  = 2'b10;

    wire mem_can_forward = mem_valid && mem_rf_we && mem_value_ready &&
                           (mem_rd != 5'h0);
    wire wb_can_forward  = wb_valid && wb_rf_we && (wb_rd != 5'h0);

    assign id_forward_rs1_wb = id_valid && id_use_rs1 && wb_can_forward &&
                               (wb_rd == id_rs1);
    assign id_forward_rs2_wb = id_valid && id_use_rs2 && wb_can_forward &&
                               (wb_rd == id_rs2);

    always @(*) begin
        ex_forward_rs1_sel = FWD_NONE;
        if (ex_valid && ex_use_rs1) begin
            if (mem_can_forward && (mem_rd == ex_rs1))
                ex_forward_rs1_sel = FWD_MEM;
            else if (wb_can_forward && (wb_rd == ex_rs1))
                ex_forward_rs1_sel = FWD_WB;
        end
    end

    always @(*) begin
        ex_forward_rs2_sel = FWD_NONE;
        if (ex_valid && ex_use_rs2) begin
            if (mem_can_forward && (mem_rd == ex_rs2))
                ex_forward_rs2_sel = FWD_MEM;
            else if (wb_can_forward && (wb_rd == ex_rs2))
                ex_forward_rs2_sel = FWD_WB;
        end
    end

    // Stop issuing younger instructions when a memory or M-extension
    // instruction starts, or while an older long-latency stage is blocked.
    assign redirect_fire = ex_fire && branch_taken;
    assign fetch_pause = (id_valid && id_can_advance && !redirect_fire &&
                          id_is_long) ||
                         ex_long_block || mem_long_block;

    // Branches and jumps resolve in EX. Only younger IF/ID and ID/EX
    // contents are invalidated; the resolving instruction continues.
    assign flush_if_id = redirect_fire;
    assign flush_id_ex = redirect_fire;

endmodule
