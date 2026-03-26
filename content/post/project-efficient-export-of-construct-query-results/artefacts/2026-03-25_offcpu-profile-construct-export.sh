#!/usr/bin/env bash
set -euo pipefail

# Configuration — identical to 2026-03-25_profiling-construct-export.sh
SERVER_BIN="/home/userNoPriv/code/qlever/qlever-code/build-profile-20260325/qlever-server"
SERVER_PORT=7001
INDEX_BASENAME="/home/userNoPriv/code/qlever/qlever-indices/dblp/dblp"
SERVER_ARGS="-i $INDEX_BASENAME -p $SERVER_PORT --default-query-timeout 3600s"
OUTPUT_DIR="./diskio-profiles"
LOG_DIR="./logs"
INDEX_DIR="/home/userNoPriv/code/qlever/qlever-indices/dblp/"

CONSTRUCT_QUERY="CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o } LIMIT 10000000"
SELECT_QUERY="SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10000000"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$LOG_DIR"

# Read /proc/$pid/io and return a named field value.
# Fields of interest:
#   rchar      — total bytes passed to read() syscalls (includes page cache hits)
#   read_bytes — bytes actually fetched from the block device (i.e. from disk,
#                NOT served from the OS page cache). This is the key metric:
#                a value of zero means every read was served from memory.
#   syscr      — number of read syscalls issued
read_proc_io_field() {
  local pid=$1
  local field=$2
  grep "^${field}:" /proc/${pid}/io 2>/dev/null | awk '{print $2}'
}

# Read major and minor page fault counts from /proc/$pid/stat.
# A major fault (field 12) means the kernel had to fetch a page from disk.
# A minor fault (field 10) means the page was already in memory.
read_page_faults() {
  local pid=$1
  local type=$2 # "major" or "minor"
  if [ "$type" = "major" ]; then
    awk '{print $12}' /proc/${pid}/stat 2>/dev/null
  else
    awk '{print $10}' /proc/${pid}/stat 2>/dev/null
  fi
}

run_diskio_profile() {
  local label="$1" # e.g. "construct_warm"
  local query="$2" # plain SPARQL query string
  local warm="$3"  # "warm" or "cold"

  local results_file="$OUTPUT_DIR/${label}_diskio.txt"

  echo "=== Disk I/O Measurement: $label ===" | tee "$results_file"

  # Kill any existing process on the port before starting a fresh server
  if lsof -ti:$SERVER_PORT >/dev/null 2>&1; then
    echo "Killing existing process on port $SERVER_PORT..."
    lsof -ti:$SERVER_PORT | xargs kill -9
    sleep 1
  fi

  # Start a fresh server instance
  "$SERVER_BIN" $SERVER_ARGS >"$LOG_DIR/${label}_diskio_server.log" 2>&1 &
  SERVER_PID=$!
  echo "Server started (PID $SERVER_PID)" | tee -a "$results_file"

  # Wait for server to be ready by polling
  local attempts=0
  while ! curl -sf "http://localhost:$SERVER_PORT/" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ $attempts -gt 60 ]; then
      echo "ERROR: Server not ready after 60 seconds"
      kill "$SERVER_PID" 2>/dev/null || true
      exit 1
    fi
    sleep 1
  done
  echo "Server ready." | tee -a "$results_file"

  # Warm or cold cache
  if [ "$warm" = "warm" ]; then
    echo "Warming cache..." | tee -a "$results_file"
    curl -sf -X POST "http://localhost:$SERVER_PORT/query" \
      -H "Content-Type: application/sparql-query" \
      -H "Accept: text/tab-separated-values" \
      --data-binary "$query" \
      >/dev/null
    echo "Warmup done." | tee -a "$results_file"
  else
    echo "Evicting vocabulary files from page cache..." | tee -a "$results_file"
    echo "Pages resident before eviction:" | tee -a "$results_file"
    vmtouch "$INDEX_DIR" | tee "$LOG_DIR/${label}_diskio_vmtouch_before.txt" | tee -a "$results_file"
    vmtouch -e "$INDEX_DIR"
    echo "Pages resident after eviction:" | tee -a "$results_file"
    vmtouch "$INDEX_DIR" | tee "$LOG_DIR/${label}_diskio_vmtouch_after.txt" | tee -a "$results_file"
  fi

  # Read /proc counters BEFORE the query
  local rchar_before read_bytes_before syscr_before majflt_before minflt_before
  rchar_before=$(read_proc_io_field "$SERVER_PID" "rchar")
  read_bytes_before=$(read_proc_io_field "$SERVER_PID" "read_bytes")
  syscr_before=$(read_proc_io_field "$SERVER_PID" "syscr")
  majflt_before=$(read_page_faults "$SERVER_PID" "major")
  minflt_before=$(read_page_faults "$SERVER_PID" "minor")

  echo "" | tee -a "$results_file"
  echo "--- /proc counters before query ---" | tee -a "$results_file"
  echo "  rchar (total bytes read incl. cache): $rchar_before" | tee -a "$results_file"
  echo "  read_bytes (bytes from disk):         $read_bytes_before" | tee -a "$results_file"
  echo "  syscr (read syscall count):           $syscr_before" | tee -a "$results_file"
  echo "  major page faults (disk fetches):     $majflt_before" | tee -a "$results_file"
  echo "  minor page faults (memory hits):      $minflt_before" | tee -a "$results_file"

  # Run the measured query and time it
  echo "" | tee -a "$results_file"
  echo "Sending measured query..." | tee -a "$results_file"
  local start_ms end_ms wall_ms
  start_ms=$(date +%s%3N)
  curl -sf -X POST "http://localhost:$SERVER_PORT/query" \
    -H "Content-Type: application/sparql-query" \
    -H "Accept: text/tab-separated-values" \
    --data-binary "$query" \
    >/dev/null
  end_ms=$(date +%s%3N)
  wall_ms=$((end_ms - start_ms))

  # Read /proc counters AFTER the query
  local rchar_after read_bytes_after syscr_after majflt_after minflt_after
  rchar_after=$(read_proc_io_field "$SERVER_PID" "rchar")
  read_bytes_after=$(read_proc_io_field "$SERVER_PID" "read_bytes")
  syscr_after=$(read_proc_io_field "$SERVER_PID" "syscr")
  majflt_after=$(read_page_faults "$SERVER_PID" "major")
  minflt_after=$(read_page_faults "$SERVER_PID" "minor")

  echo "" | tee -a "$results_file"
  echo "--- /proc counters after query ---" | tee -a "$results_file"
  echo "  rchar (total bytes read incl. cache): $rchar_after" | tee -a "$results_file"
  echo "  read_bytes (bytes from disk):         $read_bytes_after" | tee -a "$results_file"
  echo "  syscr (read syscall count):           $syscr_after" | tee -a "$results_file"
  echo "  major page faults (disk fetches):     $majflt_after" | tee -a "$results_file"
  echo "  minor page faults (memory hits):      $minflt_after" | tee -a "$results_file"

  # Compute deltas
  local delta_rchar delta_read_bytes delta_syscr delta_majflt delta_minflt
  delta_rchar=$((rchar_after - rchar_before))
  delta_read_bytes=$((read_bytes_after - read_bytes_before))
  delta_syscr=$((syscr_after - syscr_before))
  delta_majflt=$((majflt_after - majflt_before))
  delta_minflt=$((minflt_after - minflt_before))

  echo "" | tee -a "$results_file"
  echo "--- Delta (attributable to this query) ---" | tee -a "$results_file"
  echo "  Wall-clock time:                      ${wall_ms} ms" | tee -a "$results_file"
  echo "  rchar delta (total reads incl. cache): $(numfmt --to=iec $delta_rchar 2>/dev/null || echo "$delta_rchar bytes")" | tee -a "$results_file"
  echo "  read_bytes delta (actual disk reads):  $(numfmt --to=iec $delta_read_bytes 2>/dev/null || echo "$delta_read_bytes bytes")" | tee -a "$results_file"
  echo "  syscr delta (read syscalls):           $delta_syscr" | tee -a "$results_file"
  echo "  major page fault delta (disk fetches): $delta_majflt" | tee -a "$results_file"
  echo "  minor page fault delta (memory hits):  $delta_minflt" | tee -a "$results_file"
  echo "" | tee -a "$results_file"

  # Copy server log
  if [ -f "$LOG_DIR/${label}_diskio_server.log" ]; then
    cp "$LOG_DIR/${label}_diskio_server.log" "$OUTPUT_DIR/${label}_diskio_server.log"
  fi

  # Shut down server
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  echo "Results saved to $results_file"
  echo ""
}

run_diskio_profile "construct_warm" "$CONSTRUCT_QUERY" "warm"
run_diskio_profile "construct_cold" "$CONSTRUCT_QUERY" "cold"
run_diskio_profile "select_warm" "$SELECT_QUERY" "warm"
run_diskio_profile "select_cold" "$SELECT_QUERY" "cold"

# Print a comparison summary across all four runs
echo "=========================================="
echo "Summary: actual disk reads per query run"
echo "=========================================="
printf "%-20s %15s %15s %15s\n" "Run" "read_bytes" "major_faults" "wall_ms"
for label in construct_warm construct_cold select_warm select_cold; do
  local_file="$OUTPUT_DIR/${label}_diskio.txt"
  if [ -f "$local_file" ]; then
    rb=$(grep "read_bytes delta" "$local_file" | grep -o '[0-9]*' | head -1)
    mf=$(grep "major page fault delta" "$local_file" | grep -o '[0-9]*' | head -1)
    wt=$(grep "Wall-clock time" "$local_file" | grep -o '[0-9]*' | head -1)
    printf "%-20s %15s %15s %15s\n" "$label" "${rb:-N/A}" "${mf:-N/A}" "${wt:-N/A}"
  fi
done

echo ""
echo "All disk I/O profiles complete. Results in $OUTPUT_DIR/"
