#!/usr/bin/env bash
# Claude Code status line.
# Reads session JSON on stdin and renders two lines:
#   1. model, directory, git branch, session cost
#   2. context health bar, 5h window remaining, 7d window used, weekly forecast
#
# Field reference: https://code.claude.com/docs/en/statusline

input=$(</dev/stdin)

esc=$'\033'
reset="${esc}[0m"
dim="${esc}[90m"
green="${esc}[32m"
yellow="${esc}[33m"
red="${esc}[31m"
cyan="${esc}[36m"
bold="${esc}[1m"

IFS=$'\t' read -r MODEL DIR SESSION CTX COST FIVE_PCT FIVE_RESET WEEK_PCT WEEK_RESET <<<"$(
  printf '%s' "$input" | jq -r '
    [ (.model.display_name // "claude"),
      (.workspace.current_dir // .cwd // ""),
      (.session_id // "nosession"),
      (.context_window.used_percentage // -1 | floor),
      (.cost.total_cost_usd // 0),
      (.rate_limits.five_hour.used_percentage  // -1 | floor),
      (.rate_limits.five_hour.resets_at        // 0),
      (.rate_limits.seven_day.used_percentage  // -1 | floor),
      (.rate_limits.seven_day.resets_at        // 0)
    ] | @tsv'
)"

NOW=$(date +%s)
WEEK_SECONDS=604800

# Draws a filled/empty block bar for a 0-100 percentage.
bar() {
  local pct=$1 width=$2 filled i out=""
  ((pct < 0)) && pct=0
  ((pct > 100)) && pct=100
  filled=$((pct * width / 100))
  for ((i = 0; i < width; i++)); do
    if ((i < filled)); then out+="█"; else out+="░"; fi
  done
  printf '%s' "$out"
}

# Green while there is room, yellow when it gets tight, red when it is critical.
severity_color() {
  local used=$1
  if ((used < 50)); then
    printf '%s' "$green"
  elif ((used < 75)); then
    printf '%s' "$yellow"
  else
    printf '%s' "$red"
  fi
}

format_duration() {
  local secs=$1
  ((secs < 0)) && secs=0
  local days=$((secs / 86400))
  local hours=$(((secs % 86400) / 3600))
  local mins=$(((secs % 3600) / 60))
  if ((days > 0)); then
    printf '%dd%dh' "$days" "$hours"
  elif ((hours > 0)); then
    printf '%dh%02dm' "$hours" "$mins"
  else
    printf '%dm' "$mins"
  fi
}

# --- line 1: identity -------------------------------------------------------

BRANCH=""
if [ -n "$DIR" ]; then
  cache="${TMPDIR:-/tmp}/cc-statusline-${SESSION}.branch"
  if [ -f "$cache" ] && (($(date +%s) - $(stat -f %m "$cache" 2>/dev/null || echo 0) < 5)); then
    read -r BRANCH <"$cache"
  else
    BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
    printf '%s\n' "$BRANCH" >"$cache" 2>/dev/null
  fi
fi

line1="${bold}${cyan}${MODEL}${reset} ${dim}·${reset} ${DIR##*/}"
[ -n "$BRANCH" ] && line1+=" ${dim}·${reset} ${yellow}⎇ ${BRANCH}${reset}"
line1+=" ${dim}· \$$(printf '%.2f' "$COST")${reset}"

# --- line 2: budget ---------------------------------------------------------

segments=()

if ((CTX >= 0)); then
  color=$(severity_color "$CTX")
  ctx_segment="${color}ctx $(bar "$CTX" 10) ${CTX}%${reset}"
  ((CTX >= 80)) && ctx_segment+=" ${red}${bold}/clear${reset}"
  segments+=("$ctx_segment")
fi

if ((FIVE_PCT >= 0)); then
  remaining=$((100 - FIVE_PCT))
  color=$(severity_color "$FIVE_PCT")
  five_segment="${color}5h ${remaining}% left${reset}"
  if ((FIVE_RESET > 0)); then
    five_segment+=" ${dim}($(format_duration $((FIVE_RESET - NOW))))${reset}"
  fi
  segments+=("$five_segment")
fi

if ((WEEK_PCT >= 0)); then
  color=$(severity_color "$WEEK_PCT")
  segments+=("${color}7d ${WEEK_PCT}%${reset}")

  # Linear forecast: extrapolate current burn rate to the end of the window.
  if ((WEEK_RESET > 0)); then
    elapsed=$((WEEK_SECONDS - (WEEK_RESET - NOW)))
    if ((elapsed > 3600)); then
      projected=$((WEEK_PCT * WEEK_SECONDS / elapsed))
      if ((projected >= 100)); then
        forecast_color="$red"
      elif ((projected >= 85)); then
        forecast_color="$yellow"
      else
        forecast_color="$green"
      fi
      segments+=("${forecast_color}→ ~${projected}% by reset${reset}")
    fi
  fi
fi

printf '%s\n' "$line1"
if ((${#segments[@]} > 0)); then
  line2=$(
    IFS='|'
    printf '%s' "${segments[*]}"
  )
  printf '%s\n' "${line2//|/ ${dim}·${reset} }"
else
  printf '%s\n' "${dim}waiting for first API response…${reset}"
fi
