`timescale 1ns/1ps

module tb_hazard_unit;
    reg         id_valid, id_use_rs1, id_use_rs2;
    reg  [ 4:0] id_rs1, id_rs2;
    reg         ex_valid, ex_use_rs1, ex_use_rs2;
    reg  [ 4:0] ex_rs1, ex_rs2;
    reg         mem_valid, mem_rf_we, mem_value_ready;
    reg  [ 4:0] mem_rd;
    reg         wb_valid, wb_rf_we;
    reg  [ 4:0] wb_rd;
    reg         id_can_advance, id_is_long;
    reg         ex_long_block, mem_long_block;
    reg         ex_fire, branch_taken;

    wire        id_forward_rs1_wb, id_forward_rs2_wb;
    wire [ 1:0] ex_forward_rs1_sel, ex_forward_rs2_sel;
    wire        fetch_pause, redirect_fire, flush_if_id, flush_id_ex;

    integer errors = 0;

    HazardUnit dut (
        .id_valid(id_valid),
        .id_use_rs1(id_use_rs1),
        .id_use_rs2(id_use_rs2),
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .ex_valid(ex_valid),
        .ex_use_rs1(ex_use_rs1),
        .ex_use_rs2(ex_use_rs2),
        .ex_rs1(ex_rs1),
        .ex_rs2(ex_rs2),
        .mem_valid(mem_valid),
        .mem_rf_we(mem_rf_we),
        .mem_value_ready(mem_value_ready),
        .mem_rd(mem_rd),
        .wb_valid(wb_valid),
        .wb_rf_we(wb_rf_we),
        .wb_rd(wb_rd),
        .id_can_advance(id_can_advance),
        .id_is_long(id_is_long),
        .ex_long_block(ex_long_block),
        .mem_long_block(mem_long_block),
        .ex_fire(ex_fire),
        .branch_taken(branch_taken),
        .id_forward_rs1_wb(id_forward_rs1_wb),
        .id_forward_rs2_wb(id_forward_rs2_wb),
        .ex_forward_rs1_sel(ex_forward_rs1_sel),
        .ex_forward_rs2_sel(ex_forward_rs2_sel),
        .fetch_pause(fetch_pause),
        .redirect_fire(redirect_fire),
        .flush_if_id(flush_if_id),
        .flush_id_ex(flush_id_ex)
    );

    task automatic check(input bit ok, input string name);
        if (!ok) begin
            $display("FAIL %s", name);
            errors = errors + 1;
        end
    endtask

    task automatic clear_inputs;
        begin
            id_valid=0; id_use_rs1=0; id_use_rs2=0; id_rs1=0; id_rs2=0;
            ex_valid=0; ex_use_rs1=0; ex_use_rs2=0; ex_rs1=0; ex_rs2=0;
            mem_valid=0; mem_rf_we=0; mem_value_ready=0; mem_rd=0;
            wb_valid=0; wb_rf_we=0; wb_rd=0;
            id_can_advance=0; id_is_long=0;
            ex_long_block=0; mem_long_block=0;
            ex_fire=0; branch_taken=0;
        end
    endtask

    initial begin
        clear_inputs(); #1;
        check(!id_forward_rs1_wb && !id_forward_rs2_wb,
              "no false ID bypass");
        check(ex_forward_rs1_sel == 2'b00 && ex_forward_rs2_sel == 2'b00,
              "no false EX forwarding");

        id_valid=1; id_use_rs1=1; id_use_rs2=1; id_rs1=5; id_rs2=6;
        wb_valid=1; wb_rf_we=1; wb_rd=5; #1;
        check(id_forward_rs1_wb && !id_forward_rs2_wb,
              "WB to ID rs1 bypass");
        wb_rd=6; #1;
        check(!id_forward_rs1_wb && id_forward_rs2_wb,
              "WB to ID rs2 bypass");
        wb_rd=0; id_rs1=0; #1;
        check(!id_forward_rs1_wb, "x0 never bypasses");
        id_use_rs1=0; wb_rd=5; id_rs1=5; #1;
        check(!id_forward_rs1_wb, "unused source never bypasses");

        clear_inputs();
        ex_valid=1; ex_use_rs1=1; ex_use_rs2=1; ex_rs1=7; ex_rs2=8;
        wb_valid=1; wb_rf_we=1; wb_rd=7;
        mem_valid=1; mem_rf_we=1; mem_value_ready=1; mem_rd=8; #1;
        check(ex_forward_rs1_sel == 2'b01, "WB to EX forwarding");
        check(ex_forward_rs2_sel == 2'b10, "MEM to EX forwarding");

        mem_rd=7; wb_rd=7; #1;
        check(ex_forward_rs1_sel == 2'b10, "MEM forwarding has priority");
        mem_value_ready=0; #1;
        check(ex_forward_rs1_sel == 2'b01,
              "unready load result cannot forward");
        wb_valid=0; #1;
        check(ex_forward_rs1_sel == 2'b00,
              "unready producer causes no false forwarding");

        clear_inputs();
        id_valid=1; id_can_advance=1; id_is_long=1; #1;
        check(fetch_pause, "long instruction pauses fetch");
        id_valid=0; id_is_long=0; ex_long_block=1; #1;
        check(fetch_pause, "EX long-latency block pauses fetch");
        ex_long_block=0; mem_long_block=1; #1;
        check(fetch_pause, "MEM long-latency block pauses fetch");

        clear_inputs();
        ex_fire=1; branch_taken=1; #1;
        check(redirect_fire && flush_if_id && flush_id_ex,
              "taken control transfer redirects and flushes");
        ex_fire=0; #1;
        check(!redirect_fire && !flush_if_id && !flush_id_ex,
              "blocked branch cannot redirect repeatedly");
        ex_fire=1; branch_taken=0; #1;
        check(!redirect_fire && !flush_if_id && !flush_id_ex,
              "not-taken branch does not flush");

        if (errors == 0)
            $display("PASS tb_hazard_unit");
        else
            $fatal(1, "%0d hazard-unit failures", errors);
        $finish;
    end
endmodule
