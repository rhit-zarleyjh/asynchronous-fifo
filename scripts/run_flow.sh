#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 MODULE"
    exit 1
fi

MODULE="$1"

RTL="rtl/${MODULE}.sv"
TB="tb/${MODULE}_tb.sv"
TB_TOP="${MODULE}_tb"
SIM="obj_dir/V${MODULE}_tb"
NETLIST="results/synth_${MODULE}.v"
SEED=${2:-1}

if [ ! -f "$RTL" ]; then
    echo "Missing RTL: $RTL"
    exit 1
fi

if [ ! -f "$TB" ]; then
    echo "Missing testbench: $TB"
    exit 1
fi

mkdir -p results

echo "[1/4] Linting $MODULE"
if ! verilator --lint-only "$RTL" > results/lint.log 2>&1; then
    cat results/lint.log
    exit 1
fi

echo "[2/4] Building simulation"
if ! verilator --binary --timing --assert --trace \
    "$RTL" \
    "$TB" \
    --top-module "$TB_TOP" > results/build.log 2>&1; then
    cat results/build.log
    exit 1
fi

echo "[3/4] Running simulation (seed=$SEED)"
if ! "./$SIM" +verilator+seed+"$SEED" > results/sim.log 2>&1; then
    cat results/sim.log
    exit 1
fi

echo "[4/4] Synthesizing $MODULE"
if ! yosys -p "read_verilog -sv $RTL; synth -top $MODULE; write_verilog $NETLIST" \
    > results/synthesis.log 2>&1; then
    cat results/synthesis.log
    exit 1
fi

echo "PASS: $MODULE"