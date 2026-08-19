#!/usr/bin/env bash
set -euo pipefail

DESIGN="$1"
PERIOD="${2:-5.0}"

RTL="rtl/${DESIGN}.sv"
LIBERTY="lib/NangateOpenCellLibrary_typical.lib"
NETLIST="results/${DESIGN}_netlist.v"
SYNTH_LOG="results/${DESIGN}_synth.log"
STA_LOG="results/${DESIGN}_sta.log"
SDC="constraints/mac.sdc"

mkdir -p results

echo "Synthesizing ${DESIGN}"

yosys -p "
    read_verilog -sv ${RTL}
    hierarchy -check -top ${DESIGN}

    proc
    opt
    fsm
    opt
    memory
    opt

    techmap
    opt

    dfflibmap -liberty ${LIBERTY}
    abc -liberty ${LIBERTY}

    clean
    stat -liberty ${LIBERTY}

    write_verilog -noattr -noexpr ${NETLIST}
" | tee "${SYNTH_LOG}"

echo
echo "Running STA for ${DESIGN}"

sta <<EOF | tee "${STA_LOG}" | grep -E \
"=== |Startpoint:|Endpoint:|data arrival time|data required time|slack"
read_liberty ${LIBERTY}
read_verilog ${NETLIST}
link_design ${DESIGN}
create_clock -name clk -period ${PERIOD} [get_ports clk]
read_sdc ${SDC}

puts ""
puts "=== OVERALL WORST SETUP PATHS ==="
report_checks \
    -path_delay max \
    -group_count 1 \
    -digits 3

puts ""
puts "=== INPUT -> REGISTER SETUP PATHS ==="
report_checks \
    -path_delay max \
    -from [get_ports {a b c d e}] \
    -to [all_registers] \
    -group_count 1 \
    -fields {input_pins} \
    -digits 3

puts ""
puts "=== REGISTER -> REGISTER SETUP PATHS ==="
report_checks \
    -path_delay max \
    -from [all_registers] \
    -to [all_registers] \
    -group_count 1 \
    -fields {input_pins} \
    -digits 3
EOF