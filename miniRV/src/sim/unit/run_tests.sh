#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
RTL="$ROOT/src/rtl"
UNIT="$ROOT/src/sim/unit"
BUILD="${TMPDIR:-/tmp}/minirv-unit"
mkdir -p "$BUILD"

run_test() {
    local name=$1
    shift
    iverilog -g2012 -I "$RTL" -s "$name" -o "$BUILD/$name.vvp" "$@" "$UNIT/$name.sv"
    vvp "$BUILD/$name.vvp"
}

case "${1:-all}" in
    decode) run_test tb_decode_datapath "$RTL/defines.vh" "$RTL/Controller.v" "$RTL/SEXT.v" "$RTL/NPC.v" "$RTL/multiplier.v" "$RTL/divider.v" "$RTL/ALU.v" ;;
    memory) run_test tb_memory "$RTL/defines.vh" "$RTL/MREQ.v" "$RTL/MEXT.v" ;;
    multiplier) run_test tb_multiplier "$RTL/multiplier.v" ;;
    divider) run_test tb_divider "$RTL/divider.v" ;;
    alu_muldiv) run_test tb_alu_muldiv "$RTL/defines.vh" "$RTL/multiplier.v" "$RTL/divider.v" "$RTL/ALU.v" ;;
    hazard) run_test tb_hazard_unit "$RTL/HazardUnit.v" ;;
    core) run_test tb_cpu_core "$RTL/defines.vh" "$RTL/PC.v" "$RTL/NPC.v" "$RTL/RF.v" "$RTL/SEXT.v" "$RTL/Controller.v" "$RTL/HazardUnit.v" "$RTL/MREQ.v" "$RTL/MEXT.v" "$RTL/multiplier.v" "$RTL/divider.v" "$RTL/ALU.v" "$RTL/cpu_core.v" ;;
    all)
        "$0" decode
        "$0" memory
        "$0" multiplier
        "$0" divider
        "$0" alu_muldiv
        "$0" hazard
        "$0" core
        ;;
    *) echo "unknown test: $1" >&2; exit 2 ;;
esac
