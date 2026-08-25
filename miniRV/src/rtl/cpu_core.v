`timescale 1ns / 1ps

`include "defines.vh"

module cpu_core(
    input  wire         cpu_rst,
    input  wire         cpu_clk,

    // Instruction Fetch Interface
    output wire         ifetch_req   /* verilator public */ ,
    output wire [31:0]  ifetch_addr  /* verilator public */ ,
    input  wire         ifetch_valid /* verilator public */ ,
    input  wire [31:0]  ifetch_inst,

    // Data Access Interface
    output reg  [ 3:0]  daccess_ren,
    output reg  [31:0]  daccess_addr,
    input  wire         daccess_rvalid,
    input  wire [31:0]  daccess_rdata,
    output reg  [ 3:0]  daccess_wen,
    output reg  [31:0]  daccess_wdata,
    input  wire         daccess_wresp
);

    /***************************** IF *****************************/
    reg  [31:0] fetch_next_pc;
    reg  [31:0] fetch_pc_r;
    reg         fetch_outstanding;

    reg         if_id_valid;
    reg  [31:0] if_id_pc;
    reg  [31:0] if_id_inst;

    /***************************** ID *****************************/
    wire [ 1:0] id_npc_op;
    wire [ 1:0] id_rf_wsel;
    wire [ 2:0] id_sext_op;
    wire [ 4:0] id_alu_op;
    wire        id_alua_sel;
    wire        id_alub_sel;
    wire [ 2:0] id_ram_rop;
    wire [ 3:0] id_ram_wop;
    wire        id_is_mul;
    wire        id_is_div;
    wire        id_rf_we;
    wire        id_use_rs1;
    wire        id_use_rs2;
    wire [31:0] id_ext;
    wire [31:0] rf_rd1;
    wire [31:0] rf_rd2;

    wire [ 4:0] id_rs1 = if_id_inst[19:15];
    wire [ 4:0] id_rs2 = if_id_inst[24:20];
    wire [ 4:0] id_rd  = if_id_inst[11:7];
    wire        id_is_mem = (id_ram_rop != `RAM_EXT_N) | (id_ram_wop != `RAM_WE_N);
    wire        id_is_mul_div = id_is_mul | id_is_div;

    Controller U_CU (
        .opcode     (if_id_inst[6:0]),
        .funct3     (if_id_inst[14:12]),
        .funct7     (if_id_inst[31:25]),
        .npc_op     (id_npc_op),
        .sext_op    (id_sext_op),
        .alu_op     (id_alu_op),
        .alua_sel   (id_alua_sel),
        .alub_sel   (id_alub_sel),
        .is_mul     (id_is_mul),
        .is_div     (id_is_div),
        .ram_r_op   (id_ram_rop),
        .ram_w_op   (id_ram_wop),
        .rf_we      (id_rf_we),
        .rf_wsel    (id_rf_wsel),
        .use_rs1    (id_use_rs1),
        .use_rs2    (id_use_rs2)
    );

    SEXT U_SEXT (
        .op         (id_sext_op),
        .imm        (if_id_inst[31:7]),
        .ext        (id_ext)
    );

    /***************************** WB *****************************/
    reg         mem_wb_valid;
    reg  [31:0] mem_wb_pc;
    reg  [ 4:0] mem_wb_rd;
    reg         mem_wb_rf_we;
    reg  [31:0] mem_wb_data;

    wire        rf_we1 = mem_wb_valid & mem_wb_rf_we;
    wire        id_forward_rs1_wb;
    wire        id_forward_rs2_wb;
    wire [ 1:0] ex_forward_rs1_sel;
    wire [ 1:0] ex_forward_rs2_sel;
    wire        fetch_pause;
    wire        redirect_fire;
    wire        flush_if_id;
    wire        flush_id_ex;

    wire [31:0] id_rs1_data = id_forward_rs1_wb ? mem_wb_data : rf_rd1;
    wire [31:0] id_rs2_data = id_forward_rs2_wb ? mem_wb_data : rf_rd2;

    RF U_RF (
        .clk        (cpu_clk),
        .rR1        (id_rs1),
        .rR2        (id_rs2),
        .rD1        (rf_rd1),
        .rD2        (rf_rd2),
        .we         (rf_we1),
        .wR         (mem_wb_rd),
        .wD         (mem_wb_data)
    );

    /*************************** ID/EX ****************************/
    reg         id_ex_valid;
    reg  [31:0] id_ex_pc;
    reg  [31:0] id_ex_pc4;
    reg  [ 4:0] id_ex_rs1;
    reg  [ 4:0] id_ex_rs2;
    reg  [ 4:0] id_ex_rd;
    reg  [31:0] id_ex_rs1_data;
    reg  [31:0] id_ex_rs2_data;
    reg  [31:0] id_ex_ext;
    reg         id_ex_use_rs1;
    reg         id_ex_use_rs2;
    reg  [ 1:0] id_ex_npc_op;
    reg  [ 1:0] id_ex_rf_wsel;
    reg  [ 4:0] id_ex_alu_op;
    reg         id_ex_alua_sel;
    reg         id_ex_alub_sel;
    reg  [ 2:0] id_ex_ram_rop;
    reg  [ 3:0] id_ex_ram_wop;
    reg         id_ex_rf_we;
    reg         id_ex_is_mul_div;

    wire id_ex_is_mem = (id_ex_ram_rop != `RAM_EXT_N) | (id_ex_ram_wop != `RAM_WE_N);

    /***************************** EX *****************************/
    reg         ex_mem_valid;
    reg  [31:0] ex_mem_pc;
    reg  [ 4:0] ex_mem_rd;
    reg         ex_mem_rf_we;
    reg  [ 1:0] ex_mem_rf_wsel;
    reg  [31:0] ex_mem_result;
    reg  [31:0] ex_mem_addr;
    reg  [31:0] ex_mem_store_data;
    reg  [ 2:0] ex_mem_ram_rop;
    reg  [ 3:0] ex_mem_ram_wop;
    reg         ex_mem_mem_aligned;
    wire [31:0] mem_load_data;

    wire ex_mem_is_load  = ex_mem_ram_rop != `RAM_EXT_N;
    wire ex_mem_is_store = ex_mem_ram_wop != `RAM_WE_N;
    wire ex_mem_is_mem   = ex_mem_is_load | ex_mem_is_store;

    wire [31:0] ex_mem_forward_data = ex_mem_is_load ? mem_load_data : ex_mem_result;

    wire [31:0] ex_rs1_data = ex_forward_rs1_sel == 2'b10 ? ex_mem_forward_data :
                              ex_forward_rs1_sel == 2'b01 ? mem_wb_data :
                                                           id_ex_rs1_data;
    wire [31:0] ex_rs2_data = ex_forward_rs2_sel == 2'b10 ? ex_mem_forward_data :
                              ex_forward_rs2_sel == 2'b01 ? mem_wb_data :
                                                           id_ex_rs2_data;

    reg         muldiv_started;
    wire [ 4:0] alu_op_drive = !id_ex_valid ? `ALU_ADD :
                               id_ex_is_mul_div ?
                               (muldiv_started ? `ALU_ADD : id_ex_alu_op) : id_ex_alu_op;
    wire [31:0] alu_a = id_ex_alua_sel ? id_ex_pc  : ex_rs1_data;
    wire [31:0] alu_b = id_ex_alub_sel ? id_ex_ext : ex_rs2_data;
    wire [31:0] alu_c;
    wire        alu_br;
    wire        mul_div_busy;

    ALU U_ALU (
        .rst        (cpu_rst),
        .clk        (cpu_clk),
        .op         (alu_op_drive),
        .a          (alu_a),
        .b          (alu_b),
        .br         (alu_br),
        .c          (alu_c),
        .busy       (mul_div_busy)
    );

    wire [31:0] ex_npc;
    wire [31:0] ex_pc4_unused;
    NPC U_NPC (
        .op         (id_ex_npc_op),
        .pc         (id_ex_pc),
        .base       (ex_rs1_data),
        .offset     (id_ex_ext),
        .br         (alu_br),
        .npc        (ex_npc),
        .pc4        (ex_pc4_unused)
    );

    wire [31:0] ex_result = id_ex_rf_wsel == `WB_PC4 ? id_ex_pc4 :
                                id_ex_rf_wsel == `WB_EXT ? id_ex_ext : alu_c;
    wire ex_mem_aligned = (id_ex_ram_rop == `RAM_EXT_B)  | (id_ex_ram_rop == `RAM_EXT_BU) |
                          (id_ex_ram_wop == `RAM_WE_B) |
                         ((id_ex_ram_rop == `RAM_EXT_H)  | (id_ex_ram_rop == `RAM_EXT_HU) |
                          (id_ex_ram_wop == `RAM_WE_H)) & !alu_c[0] |
                         ((id_ex_ram_rop == `RAM_EXT_W)  | (id_ex_ram_wop == `RAM_WE_W)) &
                          (alu_c[1:0] == 2'b00);

    wire muldiv_done = id_ex_is_mul_div && muldiv_started && !mul_div_busy;

    /***************************** MEM ****************************/
    wire [ 3:0] mem_da_ren;
    wire [31:0] mem_da_addr;
    wire [ 3:0] mem_da_wen;
    wire [31:0] mem_da_wdata;
    reg         mem_req_sent;

    MREQ U_MEM_REQ (
        .ram_addr   (ex_mem_addr),
        .ram_rop    (ex_mem_ram_rop),
        .da_ren     (mem_da_ren),
        .da_addr    (mem_da_addr),
        .ram_wop    (ex_mem_ram_wop),
        .ram_wdata  (ex_mem_store_data),
        .da_wen     (mem_da_wen),
        .da_wdata   (mem_da_wdata)
    );

    MEXT U_MEM_EXT (
        .op         (ex_mem_ram_rop),
        .din        (daccess_rdata),
        .byte_offs  (ex_mem_addr[1:0]),
        .ext        (mem_load_data)
    );

    wire mem_response = ex_mem_is_load ? daccess_rvalid : daccess_wresp;
    wire mem_complete = !ex_mem_is_mem || !ex_mem_mem_aligned ||
                        (mem_req_sent && mem_response);
    wire mem_stage_ready = !ex_mem_valid || mem_complete;
    wire mem_fire = ex_mem_valid && mem_stage_ready;
    wire ex_mem_can_accept = mem_stage_ready;

    wire ex_stage_ready = !id_ex_valid || !id_ex_is_mul_div || muldiv_done;
    wire ex_fire = id_ex_valid && ex_stage_ready && ex_mem_can_accept;
    wire id_ex_can_accept = !id_ex_valid || ex_fire;

    wire branch_taken = (id_ex_npc_op == `NPC_JMP) ||
                        (id_ex_npc_op == `NPC_JALR) ||
                        ((id_ex_npc_op == `NPC_BRA) && alu_br);
    wire [31:0] redirect_target = ex_npc;

    wire id_fire = if_id_valid && id_ex_can_accept && !redirect_fire;
    wire if_slot_ready = !if_id_valid || id_fire || redirect_fire;

    wire id_ex_long_block = id_ex_valid &&
                            (id_ex_is_mem || (id_ex_is_mul_div && !muldiv_done));
    wire ex_mem_long_block = ex_mem_valid && ex_mem_is_mem && !mem_complete;

    HazardUnit U_HAZARD (
        .id_valid              (if_id_valid),
        .id_use_rs1            (id_use_rs1),
        .id_use_rs2            (id_use_rs2),
        .id_rs1                (id_rs1),
        .id_rs2                (id_rs2),
        .ex_valid              (id_ex_valid),
        .ex_use_rs1            (id_ex_use_rs1),
        .ex_use_rs2            (id_ex_use_rs2),
        .ex_rs1                (id_ex_rs1),
        .ex_rs2                (id_ex_rs2),
        .mem_valid             (ex_mem_valid),
        .mem_rf_we             (ex_mem_rf_we),
        .mem_value_ready       (!ex_mem_is_load ||
                                (ex_mem_mem_aligned && daccess_rvalid)),
        .mem_rd                (ex_mem_rd),
        .wb_valid              (mem_wb_valid),
        .wb_rf_we              (mem_wb_rf_we),
        .wb_rd                 (mem_wb_rd),
        .id_can_advance        (id_ex_can_accept),
        .id_is_long            (id_is_mem || id_is_mul_div),
        .ex_long_block         (id_ex_long_block),
        .mem_long_block        (ex_mem_long_block),
        .ex_fire               (ex_fire),
        .branch_taken          (branch_taken),
        .id_forward_rs1_wb     (id_forward_rs1_wb),
        .id_forward_rs2_wb     (id_forward_rs2_wb),
        .ex_forward_rs1_sel    (ex_forward_rs1_sel),
        .ex_forward_rs2_sel    (ex_forward_rs2_sel),
        .fetch_pause           (fetch_pause),
        .redirect_fire         (redirect_fire),
        .flush_if_id           (flush_if_id),
        .flush_id_ex           (flush_id_ex)
    );

    wire normal_fetch_req = if_slot_ready && !fetch_pause &&
                            (!fetch_outstanding || ifetch_valid);
    assign ifetch_req  = !cpu_rst && (redirect_fire || normal_fetch_req);
    assign ifetch_addr = redirect_fire ? redirect_target : fetch_next_pc;

    /************************ Sequential control *****************/
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            fetch_next_pc    <= 32'h0;
            fetch_pc_r       <= 32'h0;
            fetch_outstanding<= 1'b0;
        end else begin
            case ({ifetch_req, ifetch_valid})
                2'b10: fetch_outstanding <= 1'b1;
                2'b01: fetch_outstanding <= 1'b0;
                2'b11: fetch_outstanding <= 1'b1;
                default: fetch_outstanding <= fetch_outstanding;
            endcase

            if (ifetch_req) begin
                fetch_pc_r <= ifetch_addr;
                fetch_next_pc <= redirect_fire ? redirect_target + 32'h4 :
                                                  fetch_next_pc + 32'h4;
            end
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            if_id_valid <= 1'b0;
            if_id_pc    <= 32'h0;
            if_id_inst  <= 32'h0000_0013;
        end else if (flush_if_id) begin
            if_id_valid <= 1'b0;
            if_id_pc    <= 32'h0;
            if_id_inst  <= 32'h0000_0013;
        end else if (if_slot_ready) begin
            if_id_valid <= ifetch_valid;
            if (ifetch_valid) begin
                if_id_pc   <= fetch_pc_r;
                if_id_inst <= ifetch_inst;
            end
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst || flush_id_ex) begin
            id_ex_valid      <= 1'b0;
            id_ex_pc         <= 32'h0;
            id_ex_pc4        <= 32'h0;
            id_ex_rs1        <= 5'h0;
            id_ex_rs2        <= 5'h0;
            id_ex_rd         <= 5'h0;
            id_ex_rs1_data   <= 32'h0;
            id_ex_rs2_data   <= 32'h0;
            id_ex_ext        <= 32'h0;
            id_ex_use_rs1    <= 1'b0;
            id_ex_use_rs2    <= 1'b0;
            id_ex_npc_op     <= `NPC_PC4;
            id_ex_rf_wsel    <= `WB_ALU;
            id_ex_alu_op     <= `ALU_ADD;
            id_ex_alua_sel   <= `ALU_A_RS1;
            id_ex_alub_sel   <= `ALU_B_RS2;
            id_ex_ram_rop    <= `RAM_EXT_N;
            id_ex_ram_wop    <= `RAM_WE_N;
            id_ex_rf_we      <= 1'b0;
            id_ex_is_mul_div <= 1'b0;
        end else if (id_ex_can_accept) begin
            id_ex_valid <= id_fire;
            if (id_fire) begin
                id_ex_pc         <= if_id_pc;
                id_ex_pc4        <= if_id_pc + 32'h4;
                id_ex_rs1        <= id_rs1;
                id_ex_rs2        <= id_rs2;
                id_ex_rd         <= id_rd;
                id_ex_rs1_data   <= id_rs1_data;
                id_ex_rs2_data   <= id_rs2_data;
                id_ex_ext        <= id_ext;
                id_ex_use_rs1    <= id_use_rs1;
                id_ex_use_rs2    <= id_use_rs2;
                id_ex_npc_op     <= id_npc_op;
                id_ex_rf_wsel    <= id_rf_wsel;
                id_ex_alu_op     <= id_alu_op;
                id_ex_alua_sel   <= id_alua_sel;
                id_ex_alub_sel   <= id_alub_sel;
                id_ex_ram_rop    <= id_ram_rop;
                id_ex_ram_wop    <= id_ram_wop;
                id_ex_rf_we      <= id_rf_we;
                id_ex_is_mul_div <= id_is_mul_div;
            end
        end else if (id_ex_valid) begin
            // A stage held behind MEM may briefly see a producer in WB. Keep
            // the forwarded value so it is not lost after that producer
            // leaves the forwarding window.
            if (id_ex_use_rs1) id_ex_rs1_data <= ex_rs1_data;
            if (id_ex_use_rs2) id_ex_rs2_data <= ex_rs2_data;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            muldiv_started <= 1'b0;
        end else if (!id_ex_valid || !id_ex_is_mul_div) begin
            muldiv_started <= 1'b0;
        end else if (!muldiv_started) begin
            muldiv_started <= 1'b1;
        end else if (ex_fire) begin
            muldiv_started <= 1'b0;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            ex_mem_valid       <= 1'b0;
            ex_mem_pc          <= 32'h0;
            ex_mem_rd          <= 5'h0;
            ex_mem_rf_we       <= 1'b0;
            ex_mem_rf_wsel     <= `WB_ALU;
            ex_mem_result      <= 32'h0;
            ex_mem_addr        <= 32'h0;
            ex_mem_store_data  <= 32'h0;
            ex_mem_ram_rop     <= `RAM_EXT_N;
            ex_mem_ram_wop     <= `RAM_WE_N;
            ex_mem_mem_aligned <= 1'b0;
        end else if (mem_stage_ready) begin
            ex_mem_valid <= ex_fire;
            if (ex_fire) begin
                ex_mem_pc          <= id_ex_pc;
                ex_mem_rd          <= id_ex_rd;
                ex_mem_rf_we       <= id_ex_rf_we;
                ex_mem_rf_wsel     <= id_ex_rf_wsel;
                ex_mem_result      <= ex_result;
                ex_mem_addr        <= alu_c;
                ex_mem_store_data  <= ex_rs2_data;
                ex_mem_ram_rop     <= id_ex_ram_rop;
                ex_mem_ram_wop     <= id_ex_ram_wop;
                ex_mem_mem_aligned <= ex_mem_aligned;
            end
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            daccess_ren   <= 4'h0;
            daccess_addr  <= 32'h0;
            daccess_wen   <= 4'h0;
            daccess_wdata <= 32'h0;
            mem_req_sent  <= 1'b0;
        end else begin
            daccess_ren <= 4'h0;
            daccess_wen <= 4'h0;

            if (ex_mem_valid && ex_mem_is_mem && ex_mem_mem_aligned && !mem_req_sent) begin
                daccess_ren   <= mem_da_ren;
                daccess_addr  <= mem_da_addr;
                daccess_wen   <= mem_da_wen;
                daccess_wdata <= mem_da_wdata;
                mem_req_sent  <= 1'b1;
            end

            if (mem_fire && ex_mem_is_mem)
                mem_req_sent <= 1'b0;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            mem_wb_valid <= 1'b0;
            mem_wb_pc    <= 32'h0;
            mem_wb_rd    <= 5'h0;
            mem_wb_rf_we <= 1'b0;
            mem_wb_data  <= 32'h0;
        end else begin
            mem_wb_valid <= mem_fire;
            if (mem_fire) begin
                mem_wb_pc    <= ex_mem_pc;
                mem_wb_rd    <= ex_mem_rd;
                mem_wb_rf_we <= ex_mem_rf_we &&
                                (!ex_mem_is_mem || ex_mem_mem_aligned);
                mem_wb_data  <= ex_mem_is_load ? mem_load_data : ex_mem_result;
            end
        end
    end

    /********************* Your CPU ends here *********************/

`ifdef RUN_TRACE
    wire [31:0] debug_wb_pc    /* verilator public */ ;
    wire        debug_wb_rf_we /* verilator public */ ;
    wire [ 4:0] debug_wb_rf_wR /* verilator public */ ;
    wire [31:0] debug_wb_rf_wD /* verilator public */ ;

    wire [31:0] debug_mem_pc    /* verilator public */ ;
    wire [ 3:0] debug_mem_we    /* verilator public */ ;
    wire [31:0] debug_mem_waddr /* verilator public */ ;
    wire [31:0] debug_mem_wdata /* verilator public */ ;

    assign debug_wb_pc    = mem_wb_pc;
    assign debug_wb_rf_we = rf_we1;
    assign debug_wb_rf_wR = mem_wb_rd;
    assign debug_wb_rf_wD = mem_wb_data;

    assign debug_mem_pc    = ex_mem_pc;
    assign debug_mem_we    = daccess_wen;
    assign debug_mem_waddr = daccess_addr;
    assign debug_mem_wdata = daccess_wdata;
`endif

endmodule
