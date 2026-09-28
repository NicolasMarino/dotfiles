#!/usr/bin/env bash
# Claude Code subagent status line.
# Reads {columns, tasks[]} on stdin and writes one {"id","content"} JSON line
# per subagent row: name, tokens against the personal budget, then the
# description, truncated to the row width. Rows without a tokenCount are left
# out so Claude Code keeps its default rendering for them.
#
# Contract: https://code.claude.com/docs/en/statusline#subagent-status-lines
#
# Environment:
#   CLAUDE_CTX_BUDGET   personal context budget in tokens (default 250000)

BUDGET=${CLAUDE_CTX_BUDGET:-250000}
[[ $BUDGET =~ ^[1-9][0-9]*$ ]] || BUDGET=250000

jq -c --argjson budget "$BUDGET" '
  def esc($c): "\u001b[\($c)m";
  def fmt:
    if . >= 1000000 then "\(. / 1000000 | floor).\((. % 1000000) / 100000 | floor)M"
    elif . >= 1000 then "\((. + 500) / 1000 | floor)k"
    else "\(. | floor)" end;
  # Same thresholds as the main status line; past budget is always red.
  def color($pct):
    if $pct < 60 then esc("32") elif $pct < 80 then esc("33") else esc("31") end;

  (.columns // 80) as $cols
  | .tasks // [] | .[]
  | select(.id != null and (.tokenCount | type) == "number")
  | (.tokenCount * 100 / $budget | floor) as $pct
  | "\(.name // .type // "agent")" as $name
  | "\(.tokenCount | fmt)/\($budget | fmt) \($pct)%" as $usage
  | ($cols - ($name | length) - ($usage | length) - 6) as $room
  | (.description // "") as $desc
  | (if $room < 4 or $desc == "" then ""
     elif ($desc | length) > $room then " · " + $desc[0:$room - 1] + "…"
     else " · " + $desc end) as $tail
  | { id,
      content: "\(esc("1"))\($name)\(esc("0")) \(color($pct))\($usage)\(esc("0"))\(esc("90"))\($tail)\(esc("0"))" }
'
