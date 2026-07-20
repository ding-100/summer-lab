# 实验一：单周期 CPU 设计、实现与仿真 TODO

在 `miniRV_basic` 模板上完成 37 条 RV32I 基础指令和 7 条 M 扩展指令。普通算术、逻辑、移位、比较、分支和跳转保持单周期完成；Load/Store 等待总线响应；乘除法等待迭代单元结束。模板原有 `ADDI、ORI、SLLI、LUI、LW、BEQ、BNE、JAL` 8 条指令，最终实现并验证 44 条指令。

## IF、ID 单元的 PC、NPC、RF 与 SEXT

以 `miniRV_basic/src/rtl/{PC,NPC,RF,SEXT}.v` 及它们在 `cpu_core.v` 中的连线为准；`cdp-tests/mySoC` 中的同名文件与之一致。四个部件没有编码状态机：PC 和 RF 含触发器/寄存器阵列，属于时序部件；NPC 和 SEXT 的输出只取决于当前输入，是纯组合逻辑。

**PC（Program Counter，IF 单元）**

PC 内部只有一个 32 位状态寄存器 `pc`，输入为 `clk/rst/npc/fetch`。`always @(posedge clk or posedge rst)` 表示“时钟上升沿更新，高电平异步复位”：`rst=1` 时无需等时钟便令 `pc<=0`；非复位时，每个上升沿若 `fetch=1` 则 `pc<=npc`，否则 `pc<=pc` 保持。非阻塞赋值 `<=` 使新 PC 在该边沿后生效，不会在组合路径中反复改变。

`cpu_core` 将 `fetch` 连到 `inst_finished`，因此 PC 只在当前指令已完成的上升沿推进。普通 ALU/分支/跳转指令在 `ifetch_valid=1` 的周期由组合逻辑得到 `npc`，并在周期末写入 PC；对齐的 Load/Store 在总线响应前、乘除法在 `mul_div_busy` 撤销前，`inst_finished=0`，PC 保持。访存或乘除法等待时 `inst` 被置为 NOP，因此完成时 NPC 默认给出 `pc+4`，正好推进到顺序下一条。`inst_finished` 还会在上升沿被寄存到 `inst_finished_r`，用于下一次 `ifetch_req`；复位撤销后则由 `first_req=rst_r & !cpu_rst` 发出首次取指。

PC 虽无 FSM，但可将其状态变化精确概括为：`rst=1 → pc=0`；`rst=0, fetch=0, ↑clk → pc保持`；`rst=0, fetch=1, ↑clk → pc=npc`。

**NPC（Next Program Counter，IF 单元）**

NPC 无 `clk/rst` 且不保存状态。`assign pc4=pc+4` 持续生成顺序地址，`always @(*) case(op)` 在任何输入改变时重新选择 `npc`；所有 `case` 分支和 `default` 都赋值，不会推导锁存器。

| `op` | 适用指令 | `npc` 计算 | 关键含义 |
|---|---|---|---|
| `NPC_PC4` | 普通指令、未采用的控制流 | `pc+4` | RV32 固定 4 字节指令顺序执行，也是非法/默认 `op` 的安全值。 |
| `NPC_JALR` | `JALR` | `(base+offset) & 32'hffff_fffe` | `base=rs1`、`offset=I` 型符号扩展立即数；强制清零目标 bit 0。 |
| `NPC_BRA` | `BEQ/BNE/BLT/BGE/BLTU/BGEU` | `br ? pc+offset : pc+4` | `br` 由 ALU 比较产生；采用分支时加 B 型偏移，否则顺序执行。 |
| `NPC_JMP` | `JAL` | `pc+offset` | 相对当前 PC 加 J 型有符号偏移。 |

NPC 是 PC 前的组合输入逻辑：它可在一个周期内随 `pc/base/offset/br/op` 变化，只有当 PC 在 `fetch=1` 的上升沿采样它时，选定的下一地址才成为新状态。B/J 型 `offset[0]` 由 SEXT 固定为 0；JALR 在加法后单独清 bit 0。

**RF（Register File，ID 单元）**

RF 实现 RV32I 的“两读一写”寄存器堆。内部 `reg [31:0] regs [1:31]` 只存放 `x1～x31`；`x0` 不占数组单元，两路组合读口分别执行 `rR==0 ? 0 : regs[rR]`，因此读 `x0` 永返回 0。`rR1/rR2` 来自 `inst[19:15]`/`inst[24:20]`，地址或数组内容一变，`rD1/rD2` 就组合更新，读操作不等时钟。

写口是时序逻辑：仅在 `posedge clk` 且 `we && wR!=0` 时执行 `regs[wR]<=wD`，写 `x0` 被丢弃，其他情况全部寄存保持。同一寄存器在上升沿被写后，非阻塞赋值更新数组，异步读口随后反映新值。RF 没有复位端，仿真初始时 `x1～x31` 为未定值，软件必须先写后读；`x0` 则从始至终确定为 0。

`cpu_core` 中 `we=rf_we1`：普通写回指令在 `ifetch_valid && rf_we` 的周期末写 RF，Load 在 `daccess_rvalid` 到达时写，乘除法在 `mul_div_busy=0` 时写。后两类是多周期指令，所以译码时先把 `rd` 锁存到 `rf_wR_r`，完成时由 `rf_wR` 选它；普通指令直接用 `inst[11:7]`。写回数据 `rf_wD` 在 ALU 结果、`pc+4`、立即数和 Load 扩展结果中组合选择。RF 也无 FSM，状态转移就是 `we && wR!=0, ↑clk → regs[wR]=wD`，否则保持。

**SEXT（Immediate Extension，ID 单元）**

SEXT 不含寄存器。输入 `imm=inst[31:7]`，`Controller` 根据指令类型给出 `op`，`always @(*)` 完成立即数重排/扩展；每个分支都赋值且默认输出 0，所以无锁存器、无 FSM、无额外周期延迟。

| `op` | 形成的 32 位 `ext` | 用途与细节 |
|---|---|---|
| `EXT_I` | `{{20{inst[31]}}, inst[31:20]}` | 12 位有符号数，用于 OP-IMM、Load、JALR；移位立即数最终只由 ALU 使用 `ext[4:0]`。 |
| `EXT_S` | `{{20{inst[31]}}, inst[31:25], inst[11:7]}` | 把分散的 Store 12 位偏移重组后符号扩展。 |
| `EXT_B` | `{{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}` | 重组 13 位 PC 相对分支偏移；bit 0 补 0，故偏移是 2 字节倍数，再符号扩展。 |
| `EXT_U` | `{inst[31:12], 12'h000}` | U 型 20 位字段直接放到结果高 20 位，低 12 位清零，用于 LUI/AUIPC。 |
| `EXT_J` | `{{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}` | 重组 21 位 JAL PC 相对偏移；bit 0 为 0，再符号扩展。 |

四部件在一条普通指令中的整体时序是：`ifetch_valid/ifetch_inst有效 → 组合译码 → RF异步读 + SEXT立即数形成 → ALU产生br/结果 → NPC产生npc → inst_finished=1 → 同一上升沿中RF按需写回、PC采样npc → inst_finished_r触发下一次取指`。组合部件在边沿前必须满足建立时间；边沿后 PC/RF 状态更新，并驱动下一周期的组合路径。

## EX、MEM 与 WB 单元的 ALU、MREQ、MEXT 及写回逻辑

以 `miniRV_basic/src/rtl/{ALU,MREQ,MEXT,multiplier,divider}.v` 和 `cpu_core.v` 的 EX/MEM/WB 部分为准。ALU 的基础运算、分支比较为组合逻辑，乘除法含跨周期状态；MREQ、MEXT 和 WB 选择器本身均为组合逻辑，`cpu_core` 另用寄存器保存总线请求、原 Load 信息、多周期 `rd` 和执行中标志。

**ALU（EX 单元）**

ALU 的两个操作数先由 `cpu_core` 组合选择：`alu_a=alua_sel ? pc : rf_rd1`，`alu_b=alub_sel ? ext : rf_rd2`，所以 A 可为 `rs1` 或 PC，B 可为 `rs2` 或立即数。ALU 既做整数运算，也计算 Load/Store 有效地址 `rs1+ext` 和 AUIPC 的 `pc+ext`。

ALU 有两路独立的组合输出：`c` 先默认为 0，再按 `active_op` 选算术/乘除结果；`br` 先默认为 0，再按当前 `op` 生成分支判断。两个 `always @(*)` 均对所有路径赋值，不会推导锁存器。

| 类别 | 组合计算 | 细节 |
|---|---|---|
| 算术/逻辑 | `ADD:a+b`、`SUB:a-b`、`AND:a&b`、OR 按位或、`XOR:a^b` | 32 位运算，溢出高位自然丢弃。 |
| 移位 | `SLL:a<<b[4:0]`、`SRL:a>>b[4:0]`、`SRA:$signed(a)>>>b[4:0]` | 只使用 B 低 5 位，移位量为 0～31；SRA 复制符号位，SRL 高位补 0。 |
| 写回比较 | `SLT:$signed(a)<$signed(b)`、`SLTU:a<b` | 有符号/无符号比较结果作为 32 位 0 或 1 写回。 |
| 分支比较 | `EQ/NE/LT/LTU/GE/GEU` 产生 `br` | `LT/GE` 使用 `$signed`，`LTU/GEU` 按无符号比较，结果交给 NPC。 |
| 乘法 | MUL 取积 `[31:0]`，MULH 取有符号积 `[63:32]`，MULHU 取无符号积 `[63:32]` | MUL/MULH 共用 32 位有符号迭代乘法器；MUL 的低 32 位与无符号乘法相同。MULHU 将 A/B 零扩展到 33 位后迭代。 |
| 除法/余数 | DIV/DIVU 选商，REM/REMU 选余数 | 有符号 DIV/REM 先对 A/B 取绝对值，使用无符号除法器，再按锁存的符号修正；商符号为 `a[31]^b[31]`，余数符号跟随 A。 |

乘除启动信号由 `op` 直接译码：`mul_start` 对应 MUL/MULH，`mulu_start` 对应 MULHU，`div_start` 对应 DIV/REM，`divu_start` 对应 DIVU/REMU，四个子单元 `busy` 相或成 ALU `busy`。`op_r` 在启动边沿锁存 M 操作，`active_op=(op_r>=ALU_MUL)?op_r:op`，因此 `ifetch_valid` 撤销、`inst` 变为 NOP 后仍能选出原操作结果。子单元完成的上升沿用非阻塞赋值将 `busy` 置 0，ALU 的 `op_r` 在该边沿仍看到旧 `busy=1`，所以会再保持一拍；此时 `c` 有效、WB 拉高写使能，下一上升沿写 RF 后 `op_r` 回到 `ALU_ADD`。

ALU 没有显式 `state` 枚举，但乘除子单元的 `busy/count` 构成隐式状态机：

| 状态 | 动作 | 转移 |
|---|---|---|
| `IDLE` | `busy=0`，等待 `start` | `start && !busy` 的上升沿锁存操作数/符号，清累加器或余数，`count=0,busy=1`，进入 `ITERATE`。 |
| `ITERATE` | 乘法每拍按乘数 bit 0 选择累加，被乘数左移、乘数右移；除法每拍左移被除数，比较/减除数并生成一位商 | MUL/MULH 迭代 32 轮，MULHU 迭代 33 轮，非零除数迭代 32 轮；末轮锁存 `z/r`、`busy=0`，进入 `RESULT`。 |
| `RESULT/COMMIT` | `busy=0`但 `op_r` 仍保存原操作，`c` 选出结果，`mul_div_flag && !busy` 使 `rf_we1=1,inst_finished=1` | 下一上升沿将结果写 RF、PC 前进，清 `mul_div_flag`并复位 `op_r`，返回 `IDLE`。 |

除数为 0 时，除法器在启动边沿直接置商为全 1、余数为原被除数，经一个 `busy` 周期后撤销；ALU 锁存 `div_by_zero/dividend_r`，保证 DIV 返回 `32'hffff_ffff`、REM 返回原 A。`INT_MIN/-1` 的补码商自然为 `INT_MIN`、余数为 0。`rst` 对 ALU 状态寄存器和乘除子单元均为高电平异步复位，复位后 `busy=0`且结果/计数/符号状态清零。

**MREQ（Memory Request，MEM 请求生成）**

MREQ 无 `clk/rst`、无状态机，是纯组合逻辑。`ram_addr=alu_c=rs1+ext`，`offset=ram_addr[1:0]`，`da_addr` 原样传递有效地址。两个 `always @(*)` 分别产生读字节使能 `da_ren`、写字节使能 `da_wen` 和对齐后写数据 `da_wdata`；使能均有默认 0，不会推导锁存器。

| 访存 | 对齐条件 | MREQ 输出 |
|---|---|---|
| `LB/LBU` | `offset=0/1/2/3` 均允许 | `da_ren=1111`，总线读完整 32 位字，MEXT 再取目标字节。 |
| `LH/LHU` | 仅偏移 0 或 2 | 对齐时 `da_ren=1111`，偏移 1/3 时为 0。 |
| `LW` | 仅偏移 0 | 对齐时 `da_ren=1111`，否则为 0。 |
| `SB` | 任意偏移 | `da_wen=0001<<offset`，`da_wdata=ram_wdata<<(8*offset)`，写掩码只允许目标字节落存。 |
| `SH` | 仅偏移 0 或 2 | 偏移 0 产生 `0011`/数据不移，偏移 2 产生 `1100`/数据左移 16 位；未对齐时 `da_wen=0`。 |
| `SW` | 仅偏移 0 | `da_wen=1111, da_wdata=ram_wdata`；未对齐时 `da_wen=0`。 |

MREQ 输出的当前周期，`cpu_core` 还用 `mem_aligned` 做同样的对齐检查，只有 `is_ld_st_req=is_ld_st & mem_aligned` 才进入访存等待。该周期末的上升沿将 MREQ 输出采样到 `daccess_ren/addr/wen/wdata`、置 `ld_st_flag=1`，并锁存 `rf_wR_r`；同时锁存 Load 的 `alu_c_r` 和 `ram_rop_r`。未对齐半字/字访问不发总线请求、不进入等待、不写 RF，当前指令直接完成并推进 PC。

**MEXT（Memory Extension，MEM 读数据整理）**

MEXT 也无时钟和状态机，用两级组合逻辑处理 `din=daccess_rdata`。第一级按原有效地址 `byte_offs=alu_c_r[1:0]` 将目标数据移到低位：偏移 0 保持 `din`，偏移 1/2/3 等价于逻辑右移 8/16/24 位。第二级按请求时锁存的 `op=ram_rop_r` 扩展：

| `op` | `ext=ram_ext` | 意义 |
|---|---|---|
| `RAM_EXT_B` | `{{24{real_din[7]}},real_din[7:0]}` | LB 字节符号扩展。 |
| `RAM_EXT_BU` | `{24'h0,real_din[7:0]}` | LBU 字节零扩展。 |
| `RAM_EXT_H` | `{{16{real_din[15]}},real_din[15:0]}` | LH 对齐半字符号扩展。 |
| `RAM_EXT_HU` | `{16'h0,real_din[15:0]}` | LHU 半字零扩展。 |
| 其他（合法 Load 中即 `RAM_EXT_W`） | `real_din` | 对齐 LW 的偏移为 0，所以完整 32 位直通。 |

等待读响应时 `ifetch_valid` 已撤销、译码信号已变为 NOP，因此 MEXT 不能使用当前 `alu_c/ram_rop`；`alu_c_r/ram_rop_r` 保存原 Load 的字节偏移和扩展类型，使 `daccess_rvalid` 到达时可在同一周期组合生成正确 `ram_ext`。

**WB（Write Back，`cpu_core.v` 内的写回单元）**

WB 没有独立 `WB.v`，由 `cpu_core` 中的 `rf_we1/rf_wR/rf_wD` 组合逻辑和 RF 的上升沿写入共同实现。

| 指令类型 | `rf_we1` 条件 | 目的寄存器与数据 |
|---|---|---|
| 普通 ALU、LUI/AUIPC、JAL/JALR | `ifetch_valid && rf_we && !is_ld_st && !is_mul_div` | `rf_wR=inst[11:7]`；`rf_wsel` 选 `alu_c/ext/pc4`，当前指令周期末写 RF。 |
| Load | `ld_st_flag && daccess_rvalid` | `rf_wR=rf_wR_r`；`ld_st_flag=1` 无视 `rf_wsel` 强制 `rf_wD=ram_ext`，在读响应周期末写 RF。 |
| MUL/DIV/REM | `mul_div_flag && !mul_div_busy` | `rf_wR=rf_wR_r`；此时 NOP 译码的 `rf_wsel=WB_ALU`，而 `op_r` 使 `alu_c` 仍为原 M 结果，因此经 `WB_ALU` 写回。 |
| Store、分支、未对齐 Load | 上述条件均不成立 | 不写 RF；Store 的 `daccess_wresp` 只结束指令，未对齐 Load 不发请求并跳过写回。 |

`rf_wD` 的组合选择为：`ld_st_flag=1 → ram_ext`；否则 `WB_ALU → alu_c`、`WB_PC4 → pc4`、`WB_EXT → ext`，其他编码默认 0。`WB_RAM` 不需单独分支：Load 发起时尚未写回，响应时由 `ld_st_flag` 直接覆盖为 `ram_ext`。`rf_wR=(ld_st_flag || mul_div_flag)?rf_wR_r:inst[11:7]`，解决多周期完成时原指令已不在 `inst` 总线上的问题。WB MUX 本身不保存状态，真正的写状态发生在 RF `posedge clk`。

WB 无显式 FSM，但两个标志构成隐式等待状态：`IDLE(ld_st_flag=0,mul_div_flag=0)` 遇到对齐 Load/Store 则进入 `WAIT_MEM(ld_st_flag=1)`，收到 `daccess_rvalid || daccess_wresp` 后令 `inst_finished=1`，在完成边沿写 Load 结果（Store 不写）、更新 PC 并清标志；遇到 M 指令则进入 `WAIT_MULDIV(mul_div_flag=1)`，`mul_div_busy=0` 时令 `rf_we1=1,inst_finished=1`，完成边沿写 RF、更新 PC 并清标志。普通指令不进入等待状态，在 `ifetch_valid` 周期直接写回/完成。

整体数据流：普通指令为 `RF/SEXT → 操作数MUX → ALU.c → WB MUX → ↑clk写RF`；Load 为 `ALU地址 → MREQ读请求 → ↑clk锁存请求信息 → 等daccess_rvalid → MEXT取数/扩展 → WB选ram_ext → ↑clk写RF`；Store 为 `ALU地址+RF.rs2 → MREQ写掩码/移位 → ↑clk发请求 → 等daccess_wresp → ↑clk更新PC`；M 指令为 `ALU启动迭代 → busy期间保持PC/rd/op → busy撤销 → WB选alu_c → ↑clk写RF并更新PC`。

## 44 条指令在数据通路图中的对应通路

本节按数据通路图中的器件和端口名称记录每条指令真正有效的路径。所有指令都先经过公共取指通路：

`PC.pc → Inst_ROM.ifetch_addr → Inst_ROM.inst → Controller + RF读地址 + SEXT.imm`。

除分支和跳转外，顺序更新通路均为 `NPC.pc4 → NPC.npc → PC.npc`。表中 `A0/A1` 分别表示 A MUX 选择 `rD1/pc`，`B0/B1` 分别表示 B MUX 选择 `rD2/ext`；`WB0/WB1/WB2/WB3` 分别表示 WB MUX 选择 `ALU.C/MEXT.ext/NPC.pc4/SEXT.ext`。

### 寄存器—寄存器运算（10 条）

| 指令 | 图中有效数据通路 | 选择与 PC 更新 |
|---|---|---|
| ADD | `RF.rD1 → A MUX(A0)` + `RF.rD2 → B MUX(B0) → ALU.ADD → ALU.C → WB MUX(WB0) → RF.wD(rd)` | `alua_sel=0, alub_sel=0, rf_wsel=WB_ALU`；`NPC.pc4 → PC` |
| SUB | `RF.rD1 → A0` + `RF.rD2 → B0 → ALU.SUB → C → WB0 → RF.wD(rd)` | 与 ADD 相同，仅 `alu_op=ALU_SUB`；`PC←pc4` |
| SLL | `RF.rD1 → A0` + `RF.rD2[4:0] → B0 → ALU.SLL → C → WB0 → RF.wD(rd)` | 移位量取 `rD2[4:0]`；`PC←pc4` |
| SRL | `RF.rD1 → A0` + `RF.rD2[4:0] → B0 → ALU.SRL → C → WB0 → RF.wD(rd)` | 逻辑右移；`PC←pc4` |
| SRA | `RF.rD1 → A0` + `RF.rD2[4:0] → B0 → ALU.SRA → C → WB0 → RF.wD(rd)` | 算术右移；`PC←pc4` |
| SLT | `RF.rD1 → A0` + `RF.rD2 → B0 → ALU.SLT(有符号) → 0/1 → WB0 → RF.wD(rd)` | `PC←pc4` |
| SLTU | `RF.rD1 → A0` + `RF.rD2 → B0 → ALU.SLTU(无符号) → 0/1 → WB0 → RF.wD(rd)` | `PC←pc4` |
| XOR | `RF.rD1 → A0` + `RF.rD2 → B0 → ALU.XOR → C → WB0 → RF.wD(rd)` | `PC←pc4` |
| OR | `RF.rD1 → A0` + `RF.rD2 → B0 → ALU.OR → C → WB0 → RF.wD(rd)` | `PC←pc4` |
| AND | `RF.rD1 → A0` + `RF.rD2 → B0 → ALU.AND → C → WB0 → RF.wD(rd)` | `PC←pc4` |

### 立即数运算（9 条）

| 指令 | 图中有效数据通路 | 选择与 PC 更新 |
|---|---|---|
| ADDI | `RF.rD1 → A0` + `SEXT(EXT_I).ext → B MUX(B1) → ALU.ADD → C → WB0 → RF.wD(rd)` | `alub_sel=1`；`PC←pc4` |
| SLLI | `RF.rD1 → A0` + `SEXT(EXT_I).ext[4:0] → B1 → ALU.SLL → C → WB0 → RF.wD(rd)` | 移位量为 `inst[24:20]`；`PC←pc4` |
| SRLI | `RF.rD1 → A0` + `SEXT.ext[4:0] → B1 → ALU.SRL → C → WB0 → RF.wD(rd)` | 逻辑右移；`PC←pc4` |
| SRAI | `RF.rD1 → A0` + `SEXT.ext[4:0] → B1 → ALU.SRA → C → WB0 → RF.wD(rd)` | 算术右移；`PC←pc4` |
| SLTI | `RF.rD1 → A0` + `SEXT.ext → B1 → ALU.SLT(有符号) → 0/1 → WB0 → RF.wD(rd)` | `PC←pc4` |
| SLTIU | `RF.rD1 → A0` + `SEXT.ext → B1 → ALU.SLTU(无符号) → 0/1 → WB0 → RF.wD(rd)` | `PC←pc4` |
| XORI | `RF.rD1 → A0` + `SEXT.ext → B1 → ALU.XOR → C → WB0 → RF.wD(rd)` | `PC←pc4` |
| ORI | `RF.rD1 → A0` + `SEXT.ext → B1 → ALU.OR → C → WB0 → RF.wD(rd)` | `PC←pc4` |
| ANDI | `RF.rD1 → A0` + `SEXT.ext → B1 → ALU.AND → C → WB0 → RF.wD(rd)` | `PC←pc4` |

### Load/Store（8 条）

Load 和 Store 的有效地址共用 `RF.rD1 → A0` 与 `SEXT → B1 → ALU.ADD → ALU.C/ram_addr → MREQ.ram_addr`。对齐访问在请求后保持 PC，直到 Data_RAM 返回响应。

| 指令 | 图中有效数据通路 | 存储器与完成路径 |
|---|---|---|
| LB | `rs1+I-ext → ALU.C → MREQ → Data_RAM.daccess_rdata → MEXT(取目标字节+符号扩展) → WB1 → RF.wD(rd)` | `ram_rop=RAM_EXT_B`；`rvalid → 写RF + PC←pc4` |
| LBU | `rs1+I-ext → MREQ → Data_RAM → MEXT(取字节+零扩展) → WB1 → RF.wD(rd)` | `ram_rop=RAM_EXT_BU`；`rvalid → 写RF + PC←pc4` |
| LH | `rs1+I-ext → MREQ → Data_RAM → MEXT(取半字+符号扩展) → WB1 → RF.wD(rd)` | `ram_rop=RAM_EXT_H`；仅偏移 0/2 对齐时发请求 |
| LHU | `rs1+I-ext → MREQ → Data_RAM → MEXT(取半字+零扩展) → WB1 → RF.wD(rd)` | `ram_rop=RAM_EXT_HU`；仅偏移 0/2 有效 |
| LW | `rs1+I-ext → MREQ → Data_RAM → MEXT(32位直通) → WB1 → RF.wD(rd)` | `ram_rop=RAM_EXT_W`；仅 `addr[1:0]=00` 有效 |
| SB | `rs1+S-ext → ALU.C → MREQ.ram_addr` + `RF.rD2 → MREQ.ram_wdata → 字节移位/写掩码 → Data_RAM` | `ram_wop=RAM_WE_B`；`wresp → PC←pc4`，不写 RF |
| SH | `rs1+S-ext → MREQ.ram_addr` + `RF.rD2 → MREQ → 半字移位/掩码 → Data_RAM` | `ram_wop=RAM_WE_H`；仅偏移 0/2 有效；`wresp → PC←pc4` |
| SW | `rs1+S-ext → MREQ.ram_addr` + `RF.rD2 → MREQ.da_wdata → Data_RAM.data_wdata` | `ram_wop=RAM_WE_W`；仅偏移 0 有效；`wresp → PC←pc4` |

### 分支、跳转和高位立即数（10 条）

| 指令 | 图中有效数据通路 | NPC/WB 选择 |
|---|---|---|
| BEQ | `RF.rD1 → A0` + `RF.rD2 → B0 → ALU.EQ → ALU.br → NPC.br`；`SEXT(EXT_B).ext → NPC.offset`；`PC.pc → NPC.pc` | `npc_op=NPC_BRA`；`br?pc+ext:pc4`；不写 RF |
| BNE | `rD1/rD2 → A0/B0 → ALU.NE → br → NPC`；`EXT_B → NPC.offset` | `npc_op=NPC_BRA`；不写 RF |
| BLT | `rD1/rD2 → ALU.LT(有符号) → br → NPC`；`EXT_B → offset` | 成立选 `pc+ext`，否则 `pc4` |
| BGE | `rD1/rD2 → ALU.GE(有符号) → br → NPC`；`EXT_B → offset` | 成立选 `pc+ext`，否则 `pc4` |
| BLTU | `rD1/rD2 → ALU.LTU(无符号) → br → NPC`；`EXT_B → offset` | 成立选 `pc+ext`，否则 `pc4` |
| BGEU | `rD1/rD2 → ALU.GEU(无符号) → br → NPC`；`EXT_B → offset` | 成立选 `pc+ext`，否则 `pc4` |
| LUI | `Inst_ROM.inst[31:12] → SEXT(EXT_U).ext → WB MUX(WB3) → RF.wD(rd)` | `rf_wsel=WB_EXT`；`PC←pc4`；ALU 结果无效 |
| AUIPC | `PC.pc → A MUX(A1)` + `SEXT(EXT_U).ext → B MUX(B1) → ALU.ADD → C → WB0 → RF.wD(rd)` | 写回 `pc+U-ext`；`NPC.pc4 → PC` |
| JAL | `PC.pc → NPC.pc` + `SEXT(EXT_J).ext → NPC.offset → NPC.npc=pc+ext → PC.npc`；同时 `NPC.pc4 → WB2 → RF.wD(rd)` | `npc_op=NPC_JMP, rf_wsel=WB_PC4` |
| JALR | `RF.rD1 → NPC.base` + `SEXT(EXT_I).ext → NPC.offset → NPC.npc=(base+offset) & ~1 → PC.npc`；同时 `NPC.pc4 → WB2 → RF.wD(rd)` | `npc_op=NPC_JALR`；目标地址不经过 ALU |

### M 扩展（7 条）

M 指令的公共输入通路为 `RF.rD1 → A MUX(A0)` 和 `RF.rD2 → B MUX(B0) → ALU`。ALU 启动迭代单元后，`mul_div_busy=1` 期间 PC 保持；撤销后 `ALU.C → WB0 → RF.wD(rd)`，并令 `NPC.pc4 → PC`。

| 指令 | ALU 内部有效路径 | 结果通路 |
|---|---|---|
| MUL | `rD1/rD2 → 有符号迭代乘法器 → 64位乘积[31:0]` | `ALU.C → WB0 → RF.wD(rd)` |
| MULH | `rD1/rD2 → 有符号迭代乘法器 → 64位乘积[63:32]` | `ALU.C → WB0 → RF.wD(rd)` |
| MULHU | `rD1/rD2 → 33位零扩展无符号乘法器 → 乘积[63:32]` | `ALU.C → WB0 → RF.wD(rd)` |
| DIV | `rD1/rD2 → 有符号除法预处理 → 恢复余数除法器 → 商符号修正` | `ALU.C(商) → WB0 → RF.wD(rd)` |
| DIVU | `rD1/rD2 → 无符号恢复余数除法器 → 无符号商` | `ALU.C → WB0 → RF.wD(rd)` |
| REM | `rD1/rD2 → 有符号除法迭代 → 余数按被除数符号修正` | `ALU.C(余数) → WB0 → RF.wD(rd)` |
| REMU | `rD1/rD2 → 无符号除法迭代 → 无符号余数` | `ALU.C → WB0 → RF.wD(rd)` |

## 完成状态与工作记录

- [x] 分析 A/B 组及模板指令的格式、立即数、操作数、写回数据、访存方式和 PC 更新方式，完成数据通路表、控制信号表及完整数据通路图。
- [x] 补全组合数据通路、访存路径和多周期乘除法，保持 CPU 外部接口及 Vivado IP 不变。
- [x] 建立译码、访存、乘法器、除法器、ALU 乘除法及 CPU 核心级自检。
- [x] 44 条官方 Basic Trace 单指令用例全部通过；`old-miniRV` 的正确 `start.bin` 完成 37 个综合测试点并输出 `Test Point Pass!`。
- [x] Vivado 2023.2/XSim 运行 `soc_simple_tb`，`miniRV_basic/vivado_sim.log` 在 11.4801 us 记录 `Test Passed!`。
- [ ] 与组员合并后再次回归全部单元测试、44 条 Basic Trace 和完整 SoC 仿真。

| 修改或新增文件 | 完成的工作 |
|---|---|
| `miniRV_basic/src/rtl/defines.vh` | 新增/整理 ALU、NPC、立即数扩展、写回选择、Load 扩展和 Store 字节使能编码，作为控制与数据通路的统一常量。 |
| `miniRV_basic/src/rtl/Controller.v` | 按 `opcode/funct3/funct7` 完成 44 条指令译码，产生 `npc_op、sext_op、alua_sel、alub_sel、alu_op、is_mul、is_div、ram_r_op、ram_w_op、rf_we、rf_wsel`；非法访存或非法 M 编码关闭写回/请求。 |
| `miniRV_basic/src/rtl/SEXT.v` | 实现 I/S/B/U/J 五类立即数拼接和符号扩展。 |
| `miniRV_basic/src/rtl/NPC.v` | 实现 `pc+4`、条件分支、JAL 目标和 `(rs1+imm)&~1` 的 JALR 目标。 |
| `miniRV_basic/src/rtl/ALU.v` | 实现加减、与或异或、逻辑/算术移位、有符号/无符号比较；接入 32/33 位乘法器和有符号/无符号除法器；用 `op_r` 保存多周期操作，用符号寄存器完成 DIV/REM 后处理，并处理除零和 `INT_MIN/-1`。 |
| `miniRV_basic/src/rtl/MREQ.v` | 由有效地址低两位产生 `da_ren/da_wen/da_wdata`；支持 LB/LBU/LH/LHU/LW 和 SB/SH/SW 的字节选择、数据移位与半字/字对齐限制。 |
| `miniRV_basic/src/rtl/MEXT.v` | 按 `byte_offs` 对读回字进行字节对齐，再完成 B/H 的符号扩展或零扩展。 |
| `miniRV_basic/src/rtl/multiplier.v` | 编写参数化移位累加迭代乘法器：`start → busy → acc/multiplicand/multiplier_mag/count → z`，支持符号结果；33 位实例用于 MULHU。 |
| `miniRV_basic/src/rtl/divider.v` | 编写参数化恢复余数迭代除法器：`start → busy → dividend/divisor/quotient/remainder/count → z/r`，包含除零结果。 |
| `miniRV_basic/src/rtl/cpu_core.v` | 接通全部选择器和模块；增加 `mem_aligned、is_ld_st_req、ld_st_flag、mul_div_flag、rf_wR_r、alu_c_r、ram_rop_r`；锁存多周期目的寄存器和访存信息；完成总线寄存、Load/普通/M 扩展写回仲裁及 `inst_finished`/下一次取指时序。 |
| `miniRV_basic/src/sim/unit/run_tests.sh` | 编写 iverilog/vvp 一键测试脚本，支持 `decode、memory、multiplier、divider、alu_muldiv、core、all`。 |
| `miniRV_basic/src/sim/unit/tb_decode_datapath.sv` | 逐条覆盖 37 条基础指令和 7 条 M 指令控制值，并检查 S 型立即数、JALR bit0 清零、移位和有/无符号比较。 |
| `miniRV_basic/src/sim/unit/tb_memory.sv` | 检查各地址偏移的字节/半字/字写掩码、写数据移位、未对齐抑制以及 Load 符号/零扩展。 |
| `miniRV_basic/src/sim/unit/tb_multiplier.sv`、`tb_divider.sv`、`tb_alu_muldiv.sv` | 检查正负乘积、高低半积、有/无符号除法与余数、除零、`INT_MIN/-1` 及 `busy` 握手。 |
| `miniRV_basic/src/sim/unit/tb_cpu_core.sv` | 编写指令/数据存储器模型和核心级程序，检查 ADD/SUB、分支跳过、SW/LB、MUL/DIV、未对齐 LW 不写回、AUIPC/JALR 及 PC 连续推进。 |
| `miniRV_basic/src/coe/mul_div_test.asm/.coe` | 编写/生成板级乘除法测试程序，覆盖正负数组合并把结果写到外设测试地址。 |
| `miniRV_basic/run_vivado_sim.tcl`、`miniRV_basic/vivado_sim.log` | 增加可重复的 Vivado 批处理仿真流程并保存通过日志。 |
| `tools/generate_minirv_datapath*.py`、`tools/verify_minirv_datapath.py`、`*.drawio` | 编写数据通路图生成/检查脚本；完成黑白数据通路图、源端信号名、纯位宽线标、公共干线复用及旋转 90°的 OFFSET/WB/A/B 梯形 MUX；最终文件为 `miniRV数据通路_梯形MUX优化版.drawio`。 |
| `实验一设计说明.md`、本文件、`docs/superpowers/{plans,specs}` | 记录实现范围、设计约束、验证方法、数据通路绘图规范和实际测试结果。 |

当前可重复验证命令：

```bash
bash miniRV_basic/src/sim/unit/run_tests.sh all
```

2026-07-15 本机复核结果依次为 `PASS tb_decode_datapath`、`PASS tb_memory`、`PASS tb_multiplier`、`PASS tb_divider`、`PASS tb_alu_muldiv`、`PASS tb_cpu_core`。

## 44 条指令仿真波形检查表

文件别名（下表每个信号均用别名标明所在文件）：`core`=`miniRV_basic/src/rtl/cpu_core.v`，`CU`=`miniRV_basic/src/rtl/Controller.v`，`ALU`=`miniRV_basic/src/rtl/ALU.v`，`SEXT`=`miniRV_basic/src/rtl/SEXT.v`，`NPC`=`miniRV_basic/src/rtl/NPC.v`，`MREQ`=`miniRV_basic/src/rtl/MREQ.v`，`MEXT`=`miniRV_basic/src/rtl/MEXT.v`，`MUL`=`miniRV_basic/src/rtl/multiplier.v`，`DIV`=`miniRV_basic/src/rtl/divider.v`，`RF`=`miniRV_basic/src/rtl/RF.v`，`PC`=`miniRV_basic/src/rtl/PC.v`。

通用取指/完成链必须先加入波形：`core.ifetch_req → core.ifetch_valid → core.inst → core.inst_finished → ↑core.cpu_clk → PC.pc/core.pc → core.inst_finished_r → core.ifetch_req`。普通指令在 `ifetch_valid` 周期组合产生结果，随后同一上升沿写 RF 并更新 PC；`RF.regs[rd]` 只在 `RF.we && RF.wR!=0` 时改变。

**寄存器—寄存器运算（10 条）**

| 指令 | 仿真重点信号（文件） | 对应时序逻辑 |
|---|---|---|
| ADD | `CU.alu_op=ALU_ADD, CU.rf_we=1`；`core.rf_rd1/rf_rd2 → core.alu_a/alu_b → core.alu_c`；`core.rf_wD=alu_c, rf_we1, rf_wR`；`ALU.a/b/c`；`RF.we/wR/wD/regs[rd]` | `ifetch_valid → rs1/rs2有效 → alu_c=rs1+rs2 → rf_we1=1 → ↑clk写rd且PC←pc4 → 下一次取指` |
| SUB | `CU.alu_op=ALU_SUB`；`core.rf_rd1/rf_rd2/alu_c/rf_wD/rf_we1`；`ALU.a/b/c`；`RF.regs[rd]` | `ifetch_valid → alu_c=rs1-rs2 → rf_wD → ↑clk写rd、PC+4 → ifetch_req` |
| AND | `CU.alu_op=ALU_AND`；`core.alu_a/alu_b/alu_c/rf_wD/rf_we1`；`ALU.c`；`RF.regs[rd]` | `ifetch_valid → alu_c=rs1&rs2 → rf_we1 → ↑clk写rd、PC+4 → 下一条` |
| OR | `CU.alu_op=ALU_OR`；`core.alu_a/alu_b/alu_c/rf_wD/rf_we1`；`ALU.c`；`RF.regs[rd]` | `ifetch_valid → alu_c=rs1|rs2 → rf_we1 → ↑clk写rd、PC+4 → 下一条` |
| XOR | `CU.alu_op=ALU_XOR`；`core.alu_a/alu_b/alu_c/rf_wD/rf_we1`；`ALU.c`；`RF.regs[rd]` | `ifetch_valid → alu_c=rs1^rs2 → rf_we1 → ↑clk写rd、PC+4 → 下一条` |
| SLL | `CU.alu_op=ALU_SLL`；`core.rf_rd1/rf_rd2, alu_b[4:0], alu_c`；`ALU.c=a<<b[4:0]`；`RF.regs[rd]` | `ifetch_valid → 取rs2[4:0]移位量 → 左移结果 → ↑clk写rd、PC+4 → 下一条` |
| SRL | `CU.alu_op=ALU_SRL`；`core.alu_a/alu_b[4:0]/alu_c`；`ALU.c=a>>b[4:0]`；`RF.regs[rd]` | `ifetch_valid → 逻辑右移 → rf_wD → ↑clk写rd、PC+4 → 下一条` |
| SRA | `CU.alu_op=ALU_SRA`；`core.alu_a/alu_b[4:0]/alu_c`；`ALU.c=$signed(a)>>>b[4:0]`；`RF.regs[rd]` | `ifetch_valid → 符号右移并复制符号位 → ↑clk写rd、PC+4 → 下一条` |
| SLT | `CU.alu_op=ALU_SLT`；`core.rf_rd1/rf_rd2/alu_c`；`ALU.$signed(a)<$signed(b), ALU.c[0]`；`RF.regs[rd]` | `ifetch_valid → 有符号比较 → alu_c={31'b0,比较值} → ↑clk写rd、PC+4 → 下一条` |
| SLTU | `CU.alu_op=ALU_SLTU`；`core.rf_rd1/rf_rd2/alu_c`；`ALU.a<b, ALU.c[0]`；`RF.regs[rd]` | `ifetch_valid → 无符号比较 → 0/1写回 → ↑clk写rd、PC+4 → 下一条` |

**立即数、移位立即数和比较立即数（9 条）**

| 指令 | 仿真重点信号（文件） | 对应时序逻辑 |
|---|---|---|
| ADDI | `CU.sext_op=EXT_I, alub_sel=ALU_B_EXT, alu_op=ALU_ADD, rf_we=1`；`SEXT.imm/ext`；`core.ext/alu_b/alu_c/rf_wD/rf_we1` | `ifetch_valid → I立即数符号扩展 → rs1+ext → rf_we1 → ↑clk写rd、PC+4 → 下一条` |
| ANDI | `CU.sext_op=EXT_I, alub_sel=1, alu_op=ALU_AND`；`SEXT.ext`；`core.alu_a/alu_b/alu_c/rf_wD`；`ALU.c` | `ifetch_valid → ext → rs1&ext → ↑clk写rd、PC+4 → 下一条` |
| ORI | `CU.sext_op=EXT_I, alub_sel=1, alu_op=ALU_OR`；`SEXT.ext`；`core.alu_c/rf_wD/rf_we1` | `ifetch_valid → ext → rs1|ext → ↑clk写rd、PC+4 → 下一条` |
| XORI | `CU.sext_op=EXT_I, alub_sel=1, alu_op=ALU_XOR`；`SEXT.ext`；`core.alu_c/rf_wD/rf_we1` | `ifetch_valid → ext → rs1^ext → ↑clk写rd、PC+4 → 下一条` |
| SLLI | `CU.alu_op=ALU_SLL, alub_sel=1`；`SEXT.ext[4:0]`；`core.alu_b[4:0]/alu_c`；`ALU.c` | `ifetch_valid → shamt=ext[4:0] → 左移 → ↑clk写rd、PC+4 → 下一条` |
| SRLI | `CU.alu_op=ALU_SRL, funct7[5]=0`；`SEXT.ext[4:0]`；`core.alu_c`；`ALU.c` | `ifetch_valid → shamt → 逻辑右移 → ↑clk写rd、PC+4 → 下一条` |
| SRAI | `CU.alu_op=ALU_SRA, funct7[5]=1`；`SEXT.ext[4:0]`；`core.alu_c`；`ALU.c` | `ifetch_valid → shamt → 算术右移 → ↑clk写rd、PC+4 → 下一条` |
| SLTI | `CU.alu_op=ALU_SLT, sext_op=EXT_I, alub_sel=1`；`SEXT.ext`；`ALU.$signed(a)<$signed(b)`；`core.alu_c/rf_wD` | `ifetch_valid → 立即数符号扩展 → 有符号比较 → 0/1写回 → ↑clk PC+4` |
| SLTIU | `CU.alu_op=ALU_SLTU, sext_op=EXT_I, alub_sel=1`；`SEXT.ext`；`ALU.a<b`；`core.alu_c/rf_wD` | `ifetch_valid → ext作为32位无符号数参与比较 → 0/1写回 → ↑clk PC+4` |

**Load/Store（8 条）**

Load 通用链：`ifetch_valid → core.alu_c=rs1+ext → core.mem_aligned/is_ld_st_req → ↑clk锁存 rf_wR_r/alu_c_r/ram_rop_r、ld_st_flag=1、daccess_ren有效 → daccess_rvalid → MEXT.ram_ext → core.rf_we1/rf_wD → ↑clk写rd且PC前进`。Store 通用链：`ifetch_valid → alu_c/da_wen/da_wdata → ↑clk daccess_wen/daccess_wdata、ld_st_flag=1 → daccess_wresp → inst_finished → ↑clk PC前进`。未对齐半字/字必须出现 `mem_aligned=0 → is_ld_st_req=0 → daccess_ren/wen=0 → rf_we1=0 → PC直接前进`。

| 指令 | 仿真重点信号（文件） | 对应时序逻辑 |
|---|---|---|
| LB | `CU.ram_r_op=RAM_EXT_B, rf_wsel=WB_RAM, sext_op=EXT_I`；`core.alu_c/alu_c_r, ram_rop/ram_rop_r, ld_st_flag, daccess_ren/addr/rvalid/rdata, ram_ext, rf_we1`；`MREQ.offset/da_ren`；`MEXT.byte_offs/real_din/ext` | `IF → 地址计算 → ↑clk发读请求并锁存偏移 → rvalid → 选中字节并符号扩展 → ↑clk写rd/更新PC → 下一次IF` |
| LBU | `CU.ram_r_op=RAM_EXT_BU`；`core` 同 LB；`MREQ.da_ren`；`MEXT.real_din/ext={24'h0,byte}` | `IF → 地址/读请求 → rvalid → 字节零扩展 → ↑clk写rd、PC前进 → 下一条` |
| LH | `CU.ram_r_op=RAM_EXT_H`；`core.mem_aligned/alu_c[0]/is_ld_st_req`；`MREQ.offset/da_ren`；`MEXT.byte_offs/real_din/ext` | `IF → 地址计算 → alu_c[0]=0才请求 → rvalid → 半字符号扩展 → ↑clk写rd/PC；未对齐则无请求直接PC+4` |
| LHU | `CU.ram_r_op=RAM_EXT_HU`；`core.mem_aligned/daccess_ren/rvalid/ram_ext`；`MREQ.da_ren`；`MEXT.ext={16'h0,half}` | `IF → 对齐检查 → 读响应 → 半字零扩展 → ↑clk写rd/PC；未对齐 → 抑制请求 → PC+4` |
| LW | `CU.ram_r_op=RAM_EXT_W`；`core.alu_c[1:0]/mem_aligned/daccess_ren/rdata/ram_ext/rf_we1`；`MREQ.da_ren`；`MEXT.ext` | `IF → 地址计算 → alu_c[1:0]=00才请求 → rvalid → 32位数据直通 → ↑clk写rd/PC；未对齐不写回` |
| SB | `CU.ram_w_op=RAM_WE_B, rf_we=0`；`core.alu_c/rf_rd2, daccess_wen/addr/wdata, ld_st_flag/wresp`；`MREQ.offset/da_wen/da_wdata` | `IF → 地址+Store数据 → da_wen=0001<<offset且数据左移8×offset → ↑clk发写请求 → wresp → ↑clk PC前进` |
| SH | `CU.ram_w_op=RAM_WE_H`；`core.mem_aligned/alu_c[0]/daccess_wen/wdata/wresp`；`MREQ.offset/da_wen/da_wdata` | `IF → alu_c[0]=0 → 低/高半字掩码0011/1100及数据移位 → ↑clk请求 → wresp → ↑clk PC；未对齐无请求` |
| SW | `CU.ram_w_op=RAM_WE_W`；`core.mem_aligned/alu_c[1:0]/daccess_wen/addr/wdata/wresp`；`MREQ.da_wen/da_wdata` | `IF → alu_c[1:0]=00 → da_wen=1111、wdata=rs2 → ↑clk请求 → wresp → ↑clk PC；未对齐无写请求` |

**分支、跳转和高位立即数（10 条）**

| 指令 | 仿真重点信号（文件） | 对应时序逻辑 |
|---|---|---|
| BEQ | `CU.npc_op=NPC_BRA, sext_op=EXT_B, alu_op=ALU_EQ, rf_we=0`；`SEXT.ext`；`core.rf_rd1/rf_rd2/br/npc/inst_finished`；`ALU.br`；`NPC.pc/offset/br/npc` | `ifetch_valid → rs1==rs2产生br → npc=br?pc+ext:pc4 → inst_finished → ↑clk PC←npc → 下一次取指` |
| BNE | `CU.alu_op=ALU_NE`；`core.br/npc`；`ALU.br=a!=b`；`NPC.npc` | `ifetch_valid → rs1!=rs2 → 选择目标/pc4 → ↑clk PC←npc → ifetch_req` |
| BLT | `CU.alu_op=ALU_LT`；`ALU.br=$signed(a)<$signed(b)`；`core.br/npc`；`NPC.npc` | `ifetch_valid → 有符号小于比较 → npc选择 → ↑clk更新PC → 下一条` |
| BGE | `CU.alu_op=ALU_GE`；`ALU.br=$signed(a)>=$signed(b)`；`core.br/npc`；`NPC.npc` | `ifetch_valid → 有符号大于等于比较 → npc选择 → ↑clk更新PC → 下一条` |
| BLTU | `CU.alu_op=ALU_LTU`；`ALU.br=a<b`；`core.br/npc`；`NPC.npc` | `ifetch_valid → 无符号小于比较 → npc选择 → ↑clk更新PC → 下一条` |
| BGEU | `CU.alu_op=ALU_GEU`；`ALU.br=a>=b`；`core.br/npc`；`NPC.npc` | `ifetch_valid → 无符号大于等于比较 → npc选择 → ↑clk更新PC → 下一条` |
| LUI | `CU.sext_op=EXT_U, rf_wsel=WB_EXT, rf_we=1`；`SEXT.ext={imm,12'h0}`；`core.rf_wD=ext/rf_we1/rf_wR`；`RF.regs[rd]` | `ifetch_valid → U立即数形成ext → rf_wD=ext → ↑clk写rd且PC+4 → 下一条` |
| AUIPC | `CU.sext_op=EXT_U, alua_sel=ALU_A_PC, alub_sel=ALU_B_EXT, alu_op=ALU_ADD`；`core.pc/ext/alu_a/alu_b/alu_c/rf_wD` | `ifetch_valid → ext → alu_a=pc、alu_b=ext → pc+ext → ↑clk写rd且PC+4 → 下一条` |
| JAL | `CU.sext_op=EXT_J, npc_op=NPC_JMP, rf_wsel=WB_PC4`；`SEXT.ext`；`NPC.pc4/npc=pc+offset`；`core.pc4/rf_wD/npc/rf_we1` | `ifetch_valid → 同时形成pc4和pc+J偏移 → rf_wD=pc4 → ↑clk写rd且PC←跳转目标 → 下一次取指` |
| JALR | `CU.sext_op=EXT_I, npc_op=NPC_JALR, rf_wsel=WB_PC4`；`core.rf_rd1/ext/pc4/npc/rf_wD`；`NPC.base/offset/npc=(base+offset)&~1` | `ifetch_valid → rs1+I立即数并清bit0 → rf_wD=pc4 → ↑clk写rd且PC←npc → 目标地址取指` |

**M 扩展（7 条）**

M 指令共同关注：`CU.is_mul/is_div、CU.alu_op`；`core.is_mul_div → core.mul_div_flag/core.rf_wR_r → core.mul_div_busy → core.rf_we1/core.rf_wD → RF.regs[rd]`；`ALU.op_r/active_op/busy/c`。共同多周期箭头为 `ifetch_valid → start → ↑clk锁存rd/op并置busy → 逐周期迭代 → busy↓且结果有效 → rf_we1=1/inst_finished=1 → ↑clk写rd且PC前进 → inst_finished_r → 下一次取指`，busy 期间 PC 和目的寄存器保持不变。

| 指令 | 仿真重点信号（文件） | 对应时序逻辑 |
|---|---|---|
| MUL | `CU.alu_op=ALU_MUL,is_mul=1`；`ALU.mul_start/u_mul.busy/mul_res/c=mul_res[31:0]`；`MUL.x/y/acc/multiplicand/multiplier_mag/count/z/busy`；`core.mul_div_flag/rf_wR_r/rf_we1` | `ifetch_valid → mul_start → ↑clk busy=1,count=0 → count 0→31移位累加 → busy↓、低32位有效 → ↑clk写rd/PC` |
| MULH | `CU.alu_op=ALU_MULH,is_mul=1`；`ALU.u_mul/mul_res[63:32]`；`MUL.negative/acc/count/z`；`core` 多周期标志/写回信号 | `ifetch_valid → 有符号乘法启动 → 32轮 → 64位符号积 → 取高32位 → ↑clk写rd/PC` |
| MULHU | `CU.alu_op=ALU_MULHU,is_mul=1`；`ALU.mulu_start/u_mulu/mulu_res[63:32]`；33位 `MUL.x/y/acc/count/z/busy`；`core.rf_wD` | `ifetch_valid → 33位零扩展无符号乘法启动 → count 0→32 → 取无符号积高32位 → ↑clk写rd/PC` |
| DIV | `CU.alu_op=ALU_DIV,is_div=1`；`ALU.div_start/abs_a/abs_b/div_q_neg/div_by_zero/dividend_r/u_div/div_quo/c`；`DIV.dividend/divisor/quotient/remainder/count/busy` | `ifetch_valid → 保存符号并启动绝对值除法 → 32轮恢复余数 → 商符号修正/除零返回FFFFFFFF → busy↓ → ↑clk写商/PC` |
| DIVU | `CU.alu_op=ALU_DIVU,is_div=1`；`ALU.divu_start/u_divu/divu_quo/c`；`DIV.x/y/quotient/remainder/count/busy`；`core.rf_we1` | `ifetch_valid → 无符号除法启动 → 32轮 → divu_quo有效 → busy↓ → ↑clk写商/PC` |
| REM | `CU.alu_op=ALU_REM,is_div=1`；`ALU.div_start/div_r_neg/div_by_zero/dividend_r/div_rem/c`；`DIV.remainder/count/busy`；`core.rf_wD` | `ifetch_valid → 有符号除法迭代 → 余数按被除数符号修正；除零返回原被除数 → busy↓ → ↑clk写余数/PC` |
| REMU | `CU.alu_op=ALU_REMU,is_div=1`；`ALU.divu_start/u_divu/divu_rem/c`；`DIV.remainder/count/busy`；`core.mul_div_flag/rf_we1` | `ifetch_valid → 无符号除法迭代 → divu_rem有效 → busy↓ → ↑clk写余数/PC → 下一次取指` |

波形判定的最后统一检查：普通/分支/跳转指令不应置 `ld_st_flag` 或 `mul_div_flag`；Load/Store 响应前 `pc` 必须保持；M 指令 `busy` 撤销前不得写 RF；所有写回都检查 `core.rf_we1 → RF.we → ↑clk → RF.regs[rd]`，所有 PC 更新都检查 `core.inst_finished → PC.fetch → ↑clk → PC.pc=NPC.npc`。
