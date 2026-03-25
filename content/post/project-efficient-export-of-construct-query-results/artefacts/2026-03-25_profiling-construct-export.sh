#!/usr/bin/env bash
set -euo pipefail

# Configuration
# /home/userNoPriv/code/qlever/qlever-indices/dblp
SERVER_BIN="/home/userNoPriv/code/qlever/qlever-code/build-profile-20260325/qlever-server"
SERVER_PORT=7001
INDEX_BASENAME="/home/userNoPriv/code/qlever/qlever-indices/dblp/dblp"
SERVER_ARGS="-i $INDEX_BASENAME -p $SERVER_PORT" # add your index path etc. here
OUTPUT_DIR="./profiles"
WARMUP_WAIT=10 # seconds to wait for server to start
INDEX_DIR="/home/userNoPriv/code/qlever/qlever-indices/dblp/"

CONSTRUCT_QUERY="CONSTRUCT%20%7B%20%3Fs%20%3Fp%20%3Fo%20%7D%20WHERE%20%7B%20%3Fs%20%3Fp%20%3Fo%20%7D%20LIMIT%2010000000"
SELECT_QUERY="SELECT%20%3Fs%20%3Fp%20%3Fo%20WHERE%20%7B%20%3Fs%20%3Fp%20%3Fo%20%7D%20LIMIT%2010000000"

mkdir -p "$OUTPUT_DIR"

run_profile() {
  local label="$1" # e.g. "construct_warm"
  local query="$2"
  local warm="$3" # "warm" or "cold"

  echo "=== Profiling: $label ==="

  # Start a fresh server instance
  "$SERVER_BIN" $SERVER_ARGS &
  SERVER_PID=$!
  echo "Server started (PID $SERVER_PID), waiting $WARMUP_WAIT seconds..."
  sleep "$WARMUP_WAIT"

  # Warm or cold cache
  if [ "$warm" = "warm" ]; then
    echo "Warming cache..."
    curl -sf "http://localhost:$SERVER_PORT/?query=$query&action=sparql_query" >/dev/null
  else
    echo "Evicting vocabulary files from page cache..."
    echo "Pages resident before eviction:"
    vmtouch "$INDEX_DIR"
    vmtouch -e "$INDEX_DIR"
    echo "Pages resident after eviction:"
    vmtouch "$INDEX_DIR"
  fi

  # Record
  local perf_out="$OUTPUT_DIR/${label}.perf.data"
  perf record -g -F 997 --per-thread -p "$SERVER_PID" -o "$perf_out" &
  PERF_PID=$!
  sleep 1 # give perf time to attach to all threads
  echo "Recording... sending query."
  curl -sf "http://localhost:$SERVER_PORT/?query=$query&action=sparql_query" >/dev/null

  kill "$PERF_PID"
  wait "$PERF_PID" 2>/dev/null || true

  # Generate flamegraph
  echo "Generating flamegraph..."
  perf script -i "$perf_out" |
    "stackcollapse-perf.pl" |
    "flamegraph.pl" \
      >"$OUTPUT_DIR/${label}.svg"

  echo "Flamegraph written to $OUTPUT_DIR/${label}.svg"

  # Shut down server
  kill "$SERVER_PID"
  wait "$SERVER_PID" 2>/dev/null || true
  echo ""
}

run_profile "construct_warm" "$CONSTRUCT_QUERY" "warm"
run_profile "construct_cold" "$CONSTRUCT_QUERY" "cold"
run_profile "select_warm" "$SELECT_QUERY" "warm"
run_profile "select_cold" "$SELECT_QUERY" "cold"

echo "All profiles complete. Results in $OUTPUT_DIR/"
