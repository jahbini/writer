#!/usr/bin/env bash
# mem_sampler.sh — track memory pressure with a bounded footprint.
#
# 2026-09-13 rewrite: instead of an unbounded JSONL append, maintain a
# summary file that stores only the LOWEST and HIGHEST pressure sample
# per (pipe, step) window. File size = O(#distinct pipe/step pairs).
# Never grows without new work.
#
# "Pressure" here = compressed_mb + swap_used_mb. Compressor MB tells
# you the OS ran out of free pages and started compressing working
# sets; swap tells you the compressor spilled to disk. Their sum is a
# single monotone-under-strain scalar.
#
# Storage: ~/writer/logs/mem_pressure.json — a JSON object keyed by
# "pipe|step". Each value:
#   {
#     first_seen: ISO-8601,
#     last_seen:  ISO-8601,
#     samples:    N,
#     min:        <the whole sample record at the lowest pressure>,
#     max:        <the whole sample record at the highest pressure>
#   }
# Idle windows (no runner) are still tracked under the "idle|idle" key
# so you have baseline data.
#
# Deps: vm_stat, sysctl, pgrep, sed, awk, jq.

set -u

INTERVAL=${MEM_SAMPLE_INTERVAL:-5}
OUT=${MEM_SAMPLE_OUT:-$HOME/writer/logs/mem_pressure.json}
mkdir -p "$(dirname "$OUT")"

# Initialize summary file if absent.
[ -s "$OUT" ] || echo '{}' > "$OUT"

find_active_pipe() {
  local pdir p pid
  for pdir in "$HOME"/writer/pipes/*/state/ui-run.json; do
    [ -f "$pdir" ] || continue
    pid=$(sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$pdir" | head -1)
    [ -n "$pid" ] && [ "$pid" != "0" ] || continue
    kill -0 "$pid" 2>/dev/null || continue
    p=$(dirname "$(dirname "$pdir")")
    basename "$p"
    return 0
  done
  echo ''
}

find_running_step() {
  local pipe=$1
  [ -n "$pipe" ] || { echo ''; return; }
  local f name status
  for f in "$HOME"/writer/pipes/"$pipe"/state/step-*.json; do
    [ -f "$f" ] || continue
    status=$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)
    [ "$status" = "running" ] || continue
    name=$(basename "$f" .json)
    name=${name#step-}
    echo "$name"
    return 0
  done
  echo ''
}

while true; do
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  runners=$(pgrep -f 'coffee.*pipeline_runner.coffee' 2>/dev/null | wc -l | tr -d ' ')

  vmout=$(vm_stat)
  page_size=$(printf '%s' "$vmout" | awk 'NR==1 { for (i=1;i<=NF;i++) if ($i=="of") { print $(i+1); exit } }')
  [ -n "$page_size" ] || page_size=16384
  free_p=$(printf '%s' "$vmout"       | awk '/Pages free/ {gsub(/[^0-9]/,"",$3); print $3; exit}')
  active_p=$(printf '%s' "$vmout"     | awk '/Pages active/ {gsub(/[^0-9]/,"",$3); print $3; exit}')
  wired_p=$(printf '%s' "$vmout"      | awk '/Pages wired/ {gsub(/[^0-9]/,"",$4); print $4; exit}')
  compressed_p=$(printf '%s' "$vmout" | awk '/Pages occupied by compressor/ {gsub(/[^0-9]/,"",$5); print $5; exit}')
  free_mb=$(( ${free_p:-0}           * page_size / 1048576 ))
  active_mb=$(( ${active_p:-0}       * page_size / 1048576 ))
  wired_mb=$(( ${wired_p:-0}         * page_size / 1048576 ))
  compressed_mb=$(( ${compressed_p:-0} * page_size / 1048576 ))

  swapline=$(sysctl -n vm.swapusage 2>/dev/null)
  swap_used_mb=$(printf '%s' "$swapline" | awk '{ for(i=1;i<=NF;i++) if ($i=="used") { v=$(i+2); gsub(/M/,"",v); print v; exit } }')
  swap_free_mb=$(printf '%s' "$swapline" | awk '{ for(i=1;i<=NF;i++) if ($i=="free") { v=$(i+2); gsub(/M/,"",v); print v; exit } }')
  swap_used_mb=${swap_used_mb:-0}
  swap_free_mb=${swap_free_mb:-0}

  active_pipe=$(find_active_pipe)
  running_step=$(find_running_step "$active_pipe")
  key_pipe=${active_pipe:-idle}
  key_step=${running_step:-idle}
  key="${key_pipe}|${key_step}"

  # Build the sample as a JSON blob via jq (safer than shell string
  # concat — jq handles quoting/escaping and float math cleanly).
  sample=$(jq -n \
    --arg ts             "$now" \
    --argjson runners    "${runners:-0}" \
    --arg active_pipe    "${active_pipe}" \
    --arg running_step   "${running_step}" \
    --argjson free_mb    "${free_mb:-0}" \
    --argjson active_mb  "${active_mb:-0}" \
    --argjson wired_mb   "${wired_mb:-0}" \
    --argjson compressed "${compressed_mb:-0}" \
    --argjson swap_used  "${swap_used_mb:-0}" \
    --argjson swap_free  "${swap_free_mb:-0}" '
    {
      ts:            $ts,
      runners:       $runners,
      active_pipe:   (if $active_pipe  == "" then null else $active_pipe  end),
      running_step:  (if $running_step == "" then null else $running_step end),
      free_mb:       $free_mb,
      active_mb:     $active_mb,
      wired_mb:      $wired_mb,
      compressed_mb: $compressed,
      swap_used_mb:  $swap_used,
      swap_free_mb:  $swap_free,
      pressure:      ($compressed + $swap_used)
    }')

  # Read-modify-write. Atomic replace (tmp + mv) so any reader sees
  # either the pre-tick state or the post-tick state, never partial.
  tmp=$(mktemp "${OUT}.tmp.XXXXXX")
  jq --arg key "$key" --argjson sample "$sample" '
      def bump(prev; s):
        if prev == null then
          {first_seen: s.ts, last_seen: s.ts, samples: 1, min: s, max: s}
        else
          {
            first_seen: prev.first_seen,
            last_seen:  s.ts,
            samples:    (prev.samples + 1),
            min:  (if s.pressure < prev.min.pressure then s else prev.min end),
            max:  (if s.pressure > prev.max.pressure then s else prev.max end)
          }
        end;
      .[$key] = bump(.[$key]; $sample)
     ' "$OUT" > "$tmp" && mv "$tmp" "$OUT" || rm -f "$tmp"

  sleep "$INTERVAL"
done
