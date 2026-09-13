#!/usr/bin/env bash
# kag_survey.sh — cross-pipe survey of KAG (keyword/headline) coverage
# and consensus.
#
# Usage:
#   kag_survey.sh                          # summary of every pipe's KAG coverage
#   kag_survey.sh --story <story_id>       # per-story keyword agreement across pipes
#   kag_survey.sh --top-agreed [N]         # keywords that the most pipes agree on
#   kag_survey.sh --unique <pipe>          # keywords only that pipe surfaced (per story)
#   kag_survey.sh --emotion-quality        # per-pipe discrimination score (rank models
#                                          # by how well they distinguish emotions)
#
# Reads every ~/writer/pipes/*/runtime.sqlite. Read-only.
#
# Why: each pipe runs a different model. Same 169 stories → same KAG
# extraction task, different outputs. If models converge on the same
# keywords, that's a confidence signal for the story's true content.
# If they diverge wildly, we know KAG is noisy for that story.

set -u

MODE=${1:-summary}
shift || true

# Enumerate pipes that have a runtime.sqlite AND at least one kag row.
list_pipes_with_kag() {
  local d p db n
  for d in "$HOME"/writer/pipes/*/; do
    p=$(basename "$d")
    db=$d/runtime.sqlite
    [ -f "$db" ] || continue
    n=$(sqlite3 "$db" "SELECT COUNT(*) FROM kag_entries" 2>/dev/null || echo 0)
    [ "$n" -gt 0 ] || continue
    printf '%s\n' "$p"
  done
}

summary() {
  printf '%-55s %8s %10s %10s\n' 'pipe' 'stories' 'distinct_kw' 'total_kag'
  printf '%-55s %8s %10s %10s\n' '----' '-------' '-----------' '---------'
  local p db stories kw entries
  while read -r p; do
    db=$HOME/writer/pipes/$p/runtime.sqlite
    stories=$(sqlite3 "$db" 'SELECT COUNT(DISTINCT story_id) FROM kag_entries')
    kw=$(sqlite3 "$db" 'SELECT COUNT(DISTINCT keyword) FROM kag_entries')
    entries=$(sqlite3 "$db" 'SELECT COUNT(*) FROM kag_entries')
    printf '%-55s %8s %10s %10s\n' "$p" "$stories" "$kw" "$entries"
  done < <(list_pipes_with_kag)
}

# Build a single sqlite temp DB that UNIONs every pipe's (story_id, keyword, pipe)
# into one table. Reused by the agreement queries.
build_unified() {
  local tmp=/tmp/kag_unified.sqlite
  rm -f "$tmp"
  sqlite3 "$tmp" "CREATE TABLE kag (pipe TEXT, story_id TEXT, keyword TEXT)"
  local p db
  while read -r p; do
    db=$HOME/writer/pipes/$p/runtime.sqlite
    sqlite3 "$db" -separator $'\t' "SELECT story_id, LOWER(keyword) FROM kag_entries WHERE keyword IS NOT NULL AND LENGTH(TRIM(keyword))>0" \
      | awk -v p="$p" -F'\t' '{gsub(/'\''/, "'\'''\'''\''", $1); gsub(/'\''/, "'\'''\'''\''", $2); printf "INSERT INTO kag VALUES ('\''%s'\'', '\''%s'\'', '\''%s'\'');\n", p, $1, $2}' \
      | sqlite3 "$tmp"
  done < <(list_pipes_with_kag)
  printf '%s' "$tmp"
}

story_agreement() {
  local sid=$1
  [ -n "$sid" ] || { echo "usage: kag_survey.sh --story <story_id>" >&2; exit 2; }
  local u=$(build_unified)
  echo "keywords for story_id='$sid' — pipes agreeing on each"
  printf '%-40s %5s  %s\n' 'keyword' 'n' 'pipes'
  printf '%-40s %5s  %s\n' '-------' '---' '-----'
  sqlite3 -separator $'\t' "$u" \
    "SELECT keyword, COUNT(DISTINCT pipe) AS n, GROUP_CONCAT(DISTINCT pipe) AS pipes
       FROM kag WHERE story_id='$sid' GROUP BY keyword ORDER BY n DESC, keyword" \
    | awk -F'\t' '{printf "%-40s %5s  %s\n", $1, $2, $3}'
}

top_agreed() {
  local N=${1:-30}
  local u=$(build_unified)
  echo "Top $N (story,keyword) pairs by number of pipes that surfaced them"
  printf '%-60s %-40s %5s\n' 'story_id' 'keyword' 'n_pipes'
  printf '%-60s %-40s %5s\n' '--------' '-------' '-------'
  sqlite3 -separator $'\t' "$u" \
    "SELECT story_id, keyword, COUNT(DISTINCT pipe) AS n
       FROM kag GROUP BY story_id, keyword ORDER BY n DESC, story_id, keyword LIMIT $N" \
    | awk -F'\t' '{printf "%-60s %-40s %5s\n", $1, $2, $3}'
}

unique_to() {
  local target=$1
  [ -n "$target" ] || { echo "usage: kag_survey.sh --unique <pipe>" >&2; exit 2; }
  local u=$(build_unified)
  echo "keywords that ONLY $target surfaced, per story"
  printf '%-60s %s\n' 'story_id' 'keyword'
  printf '%-60s %s\n' '--------' '-------'
  sqlite3 -separator $'\t' "$u" \
    "SELECT story_id, keyword FROM kag
      WHERE pipe='$target'
      GROUP BY story_id, keyword
      HAVING COUNT(DISTINCT pipe) = 1
      ORDER BY story_id, keyword" \
    | awk -F'\t' '{printf "%-60s %s\n", $1, $2}'
}

emotion_quality() {
  # Per pipe, compute discrimination signals:
  #   distinct  — how many of the 17 emotion categories the pipe used
  #   top1_pct  — % of pipe's kag entries on its single most-common keyword
  #               (>40% suggests the model collapses to one emotion)
  #   top3_pct  — combined share of the top 3 keywords
  #               (>75% means only 3 emotions in real use)
  #   neutral_pct — share classified "neutral"
  #                 (high = model refuses to commit)
  #   per_story  — mean kag entries per story
  #                 (very low = model outputs empty / refusals)
  #   coverage   — stories with any kag / total stories
  #
  # A model that FAILS at emotion recognition typically shows:
  #   distinct < 8   OR
  #   top1_pct > 40  OR
  #   top3_pct > 80  OR
  #   neutral_pct > 40  OR
  #   per_story < 4
  # Weeding by these thresholds is the point.
  printf '%-55s %8s %8s %8s %10s %10s %9s\n' \
    'pipe' 'distinct' 'top1_pct' 'top3_pct' 'neutral_pct' 'per_story' 'coverage'
  printf '%-55s %8s %8s %8s %10s %10s %9s\n' \
    '----' '--------' '--------' '--------' '-----------' '---------' '--------'
  local p db distinct entries top1 top3 neutral stories_with stories_total per_story
  while read -r p; do
    db=$HOME/writer/pipes/$p/runtime.sqlite
    distinct=$(sqlite3 "$db" 'SELECT COUNT(DISTINCT keyword) FROM kag_entries WHERE keyword IS NOT NULL')
    entries=$(sqlite3   "$db" 'SELECT COUNT(*) FROM kag_entries WHERE keyword IS NOT NULL')
    [ "${entries:-0}" -gt 0 ] || { echo "$p: no keywords"; continue; }
    top1=$(sqlite3 "$db" "SELECT COUNT(*)*100.0/${entries} FROM kag_entries WHERE keyword=(SELECT keyword FROM kag_entries WHERE keyword IS NOT NULL GROUP BY keyword ORDER BY COUNT(*) DESC LIMIT 1)")
    top3=$(sqlite3 "$db" "SELECT SUM(n)*100.0/${entries} FROM (SELECT COUNT(*) AS n FROM kag_entries WHERE keyword IS NOT NULL GROUP BY keyword ORDER BY n DESC LIMIT 3)")
    neutral=$(sqlite3 "$db" "SELECT COUNT(*)*100.0/${entries} FROM kag_entries WHERE LOWER(keyword)='neutral'")
    stories_with=$(sqlite3 "$db" 'SELECT COUNT(DISTINCT story_id) FROM kag_entries')
    stories_total=$(sqlite3 "$db" 'SELECT COUNT(*) FROM stories')
    [ "${stories_with:-0}" -gt 0 ] || per_story=0 || true
    per_story=$(awk -v e="$entries" -v s="$stories_with" 'BEGIN { if (s==0) print "0.0"; else printf "%.1f", e/s }')
    coverage=$(awk -v w="$stories_with" -v t="$stories_total" 'BEGIN { if (t==0) print "n/a"; else printf "%d/%d", w, t }')
    printf '%-55s %8s %8.1f %8.1f %10.1f %10s %9s\n' \
      "$p" "$distinct" "$top1" "$top3" "$neutral" "$per_story" "$coverage"
  done < <(list_pipes_with_kag)
  echo
  echo "Weeding rule of thumb:"
  echo "  distinct<8 | top1>40 | top3>80 | neutral>40 | per_story<4 → suspect model"
}

case "$MODE" in
  summary)            summary ;;
  --story)            story_agreement "${1:-}" ;;
  --top-agreed)       top_agreed "${1:-30}" ;;
  --unique)           unique_to "${1:-}" ;;
  --emotion-quality)  emotion_quality ;;
  *)
    echo "unknown mode: $MODE" >&2
    echo "modes: summary | --story <id> | --top-agreed [N] | --unique <pipe> | --emotion-quality" >&2
    exit 2
    ;;
esac
