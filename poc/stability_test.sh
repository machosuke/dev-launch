#!/bin/zsh

# Phase 0 安定性テスト
# 指定アプローチを N 回実行し、成功率を計測する
#
# Usage: ./stability_test.sh <script_path> [runs] [project_path]
# Example: ./stability_test.sh approach1_uri_scheme.swift 10

set -euo pipefail

SCRIPT=${1:?"Usage: $0 <script_path> [runs] [project_path]"}
N=${2:-10}
PROJECT=${3:-"/Users/machosuke/Desktop/claude_code/dev-launch"}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RESULTS_DIR="$SCRIPT_DIR/results"
LOG_FILE="$RESULTS_DIR/stability_$(date +%Y%m%d_%H%M%S).log"

# スクリプトパスの解決
if [[ ! "$SCRIPT" = /* ]]; then
    SCRIPT="$SCRIPT_DIR/$SCRIPT"
fi

if [[ ! -f "$SCRIPT" ]]; then
    echo "ERROR: Script not found: $SCRIPT"
    exit 1
fi

PASS=0
FAIL=0

echo "=== Stability Test ===" | tee "$LOG_FILE"
echo "Script: $SCRIPT" | tee -a "$LOG_FILE"
echo "Runs: $N" | tee -a "$LOG_FILE"
echo "Project: $PROJECT" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

for i in $(seq 1 "$N"); do
    echo "--- Run $i / $N ---" | tee -a "$LOG_FILE"

    OUTPUT=$(swift "$SCRIPT" "$PROJECT" 2>&1)
    echo "$OUTPUT" | tee -a "$LOG_FILE"

    if echo "$OUTPUT" | grep -q "SUCCESS"; then
        PASS=$((PASS + 1))
        echo "=> PASS" | tee -a "$LOG_FILE"
    else
        FAIL=$((FAIL + 1))
        echo "=> FAIL" | tee -a "$LOG_FILE"
    fi

    echo "" | tee -a "$LOG_FILE"

    # 最終回以外は待機
    if [[ $i -lt $N ]]; then
        echo "Waiting 30 seconds before next run..." | tee -a "$LOG_FILE"
        sleep 30
    fi
done

RATE=$((PASS * 100 / N))

echo "" | tee -a "$LOG_FILE"
echo "=== RESULT ===" | tee -a "$LOG_FILE"
echo "Passed: $PASS / $N ($RATE%)" | tee -a "$LOG_FILE"
echo "Failed: $FAIL / $N" | tee -a "$LOG_FILE"

if [[ $RATE -ge 90 ]]; then
    echo "VERDICT: GO" | tee -a "$LOG_FILE"
elif [[ $RATE -ge 70 ]]; then
    echo "VERDICT: CONDITIONAL GO (add retry logic)" | tee -a "$LOG_FILE"
else
    echo "VERDICT: NO-GO (use external terminal fallback)" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE"
