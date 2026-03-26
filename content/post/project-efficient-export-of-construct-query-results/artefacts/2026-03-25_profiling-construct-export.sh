#!/usr/bin/env bash
set -euo pipefail

# Configuration
# /home/userNoPriv/code/qlever/qlever-indices/dblp
SERVER_BIN="/home/userNoPriv/code/qlever/qlever-code/build-profile-20260325/qlever-server"
SERVER_PORT=7001
INDEX_BASENAME="/home/userNoPriv/code/qlever/qlever-indices/dblp/dblp"
SERVER_ARGS="-i $INDEX_BASENAME -p $SERVER_PORT --default-query-timeout 3600s" # add your index path etc. here
OUTPUT_DIR="./profiles"
WARMUP_WAIT=10 # seconds to wait for server to start
INDEX_DIR="/home/userNoPriv/code/qlever/qlever-indices/dblp/"

# Configuration
LOG_DIR="./logs"

CONSTRUCT_QUERY="CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o } LIMIT 10000000"
SELECT_QUERY="SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10000000"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$LOG_DIR"

run_profile() {
  local label="$1" # e.g. "construct_warm"
  local query="$2"
  local warm="$3" # "warm" or "cold"

  echo "=== Profiling: $label ==="

  # Kill any existing process on the port before starting a fresh server
  if lsof -ti:$SERVER_PORT >/dev/null 2>&1; then
    echo "Killing existing process on port $SERVER_PORT..."
    lsof -ti:$SERVER_PORT | xargs kill -9
    sleep 1
  fi

  # Start a fresh server instance, redirect its output to a log file
  "$SERVER_BIN" $SERVER_ARGS >"$LOG_DIR/${label}_server.log" 2>&1 &
  SERVER_PID=$!
  echo "Server started (PID $SERVER_PID), waiting $WARMUP_WAIT seconds..."
  sleep "$WARMUP_WAIT"

  # Warm or cold cache
  if [ "$warm" = "warm" ]; then
    echo "Warming cache..."
    curl -f -G "http://localhost:$SERVER_PORT/" \
      --data-urlencode "query=$query" \
      --data-urlencode "action=sparql_query" \
      >/dev/null
  else
    echo "Evicting vocabulary files from page cache..."
    echo "Pages resident before eviction:"
    vmtouch "$INDEX_DIR" | tee "$LOG_DIR/${label}_vmtouch_before.txt"
    vmtouch -e "$INDEX_DIR"
    echo "Pages resident after eviction:"
    vmtouch "$INDEX_DIR" | tee "$LOG_DIR/${label}_vmtouch_after.txt"
  fi

  # Record
  local perf_out="$OUTPUT_DIR/${label}.perf.data"
  perf record --call-graph fp --freq=997 -p "$SERVER_PID" -o "$perf_out" &
  PERF_PID=$!
  sleep 1 # give perf time to attach to all threads
  echo "Recording... sending query."
  curl -sf -X POST "http://localhost:$SERVER_PORT/query" \
    -H "Content-Type: application/sparql-query" \
    -H "Accept: text/tab-separated-values" \
    --data-binary "$query" \
    --max-time 3600 \
    >/dev/null
  kill -SIGINT "$PERF_PID"
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
