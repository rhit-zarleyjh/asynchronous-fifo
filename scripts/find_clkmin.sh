#!/usr/bin/env bash
set -euo pipefail

DESIGN="$1"
PRECISION="${2:-0.01}"
LOW="${3:-1.0}"
HIGH="${4:-3.0}"

get_slack() {
    local period="$1"

    ./scripts/run_timing.sh "$DESIGN" "$period" \
        | awk '/=== OVERALL WORST SETUP PATHS ===/{flag=1; next} flag && /slack/{print $1; exit}'
}

LOW_SLACK=$(get_slack "$LOW")
HIGH_SLACK=$(get_slack "$HIGH")

echo "Checking bounds:"
echo "  LOW  ${LOW} ns -> slack ${LOW_SLACK} ns"
echo "  HIGH ${HIGH} ns -> slack ${HIGH_SLACK} ns"

if (( $(echo "$LOW_SLACK >= 0" | bc -l) )); then
    echo "Error: LOW bound must fail timing."
    exit 1
fi

if (( $(echo "$HIGH_SLACK < 0" | bc -l) )); then
    echo "Error: HIGH bound must pass timing."
    exit 1
fi

while (( $(echo "$HIGH - $LOW > $PRECISION" | bc -l) )); do
    MID=$(echo "scale=6; ($LOW + $HIGH) / 2" | bc)

    SLACK=$(get_slack "$MID")

    echo "Testing ${MID} ns -> slack ${SLACK} ns"

    if (( $(echo "$SLACK >= 0" | bc -l) )); then
        HIGH="$MID"
    else
        LOW="$MID"
    fi
done

INTERVAL=$(echo "scale=6; $HIGH - $LOW" | bc)

CLKMIN=$(printf "%.2f" "$HIGH")
FMAX=$(echo "scale=2; 1000 / $HIGH" | bc)

echo
echo "Clock-period threshold:"
echo "  failing bound:   ${LOW} ns"
echo "  passing bound:   ${HIGH} ns"
echo "  interval width:  ${INTERVAL} ns"
echo "  target precision: ${PRECISION} ns"

echo
echo "Estimated result:"
echo "  minimum passing period: ~${CLKMIN} ns"
echo "  maximum frequency:      ~${FMAX} MHz"