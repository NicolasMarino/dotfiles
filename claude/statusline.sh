#!/usr/bin/env bash
# Claude Code status line.
# Reads session JSON on stdin and renders two lines:
#   1. model, directory, git branch, session cost, lines changed, API time
#   2. context vs token budget, compactions,
#      5h and 7d rate-limit windows with pace markers, weekly forecast
#
# Field reference: https://code.claude.com/docs/en/statusline
#
# Environment:
#   CLAUDE_CTX_BUDGET          personal context budget in tokens (default 250000)

input=$(</dev/stdin)

esc=$'\033'
reset="${esc}[0m"
dim="${esc}[90m"
green="${esc}[32m"
yellow="${esc}[33m"
red="${esc}[31m"
cyan="${esc}[36m"
bold="${esc}[1m"

BUDGET=${CLAUDE_CTX_BUDGET:-250000}
[[ $BUDGET =~ ^[1-9][0-9]*$ ]] || BUDGET=250000

# One jq call. Fields are joined with the ASCII unit separator, not a tab:
# tab is IFS whitespace, so `read` would collapse an empty field and shift
# every value after it.
IFS=$'\x1f' read -r MODEL DIR SESSION CTX TOKENS COST ADDED REMOVED API_MS \
  FIVE_PCT FIVE_RESET WEEK_PCT WEEK_RESET TRANSCRIPT <<<"$(
  printf '%s' "$input" | jq -r '
    [ (.model.display_name // "claude"),
      (.workspace.current_dir // .cwd // ""),
      (.session_id // "nosession"),
      (.context_window.used_percentage // -1 | floor),
      # Same input-only sum Claude Code uses for used_percentage.
      (.context_window.current_usage
        | if type == "object"
          then (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
          else -1 end),
      (.cost.total_cost_usd // 0),
      (.cost.total_lines_added // 0 | floor),
      (.cost.total_lines_removed // 0 | floor),
      (.cost.total_api_duration_ms // 0 | floor),
      (.rate_limits.five_hour.used_percentage  // -1 | floor),
      (.rate_limits.five_hour.resets_at        // 0 | floor),
      (.rate_limits.seven_day.used_percentage  // -1 | floor),
      (.rate_limits.seven_day.resets_at        // 0 | floor),
      (.transcript_path // "")
    ] | map(tostring) | join("\u001f")'
)"

NOW=$(date +%s)
FIVE_HOUR_SECONDS=18000
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

# Budget thresholds line up with the /compact hint: red means act now.
budget_color() {
  local used=$1
  if ((used < 60)); then
    printf '%s' "$green"
  elif ((used < 80)); then
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

# 84000 -> 84k, 1250000 -> 1.2M
format_tokens() {
  local n=$1
  if ((n >= 1000000)); then
    printf '%d.%dM' $((n / 1000000)) $(((n % 1000000) / 100000))
  elif ((n >= 1000)); then
    printf '%dk' $(((n + 500) / 1000))
  else
    printf '%d' "$n"
  fi
}

# Pace marker for a rate-limit window: compares actual use with the share of
# the window already elapsed. ◆ = burning faster than linear, ◇ = under pace.
pace_marker() {
  local used=$1 resets_at=$2 window=$3 elapsed expected
  ((resets_at > 0)) || return 0
  elapsed=$((window - (resets_at - NOW)))
  ((elapsed > 0 && elapsed <= window)) || return 0
  expected=$((elapsed * 100 / window))
  if ((used > expected)); then
    printf ' %s◆%d%%%s' "$yellow" "$expected" "$reset"
  else
    printf ' %s◇%d%%%s' "$green" "$expected" "$reset"
  fi
}

# --- line 1: identity -------------------------------------------------------

# The git dir is resolved once per session and directory (worktrees have a
# .git file, not a directory). The branch is re-read only when HEAD changes:
# the cache is keyed on HEAD's content, read with a builtin, which costs no
# fork and has no one-second mtime granularity to miss a quick checkout.
BRANCH=""
if [ -n "$DIR" ]; then
  cache_dir="${TMPDIR:-/tmp}"
  dir_key="${DIR//[^A-Za-z0-9]/_}"
  ((${#dir_key} > 80)) && dir_key=${dir_key: -80}
  cache="${cache_dir%/}/cc-statusline-${SESSION}-${dir_key}"

  git_dir=""
  if [ -f "$cache.gitdir" ]; then
    read -r git_dir <"$cache.gitdir"
  else
    git_dir=$(git --no-optional-locks -C "$DIR" rev-parse --absolute-git-dir 2>/dev/null)
    printf '%s\n' "${git_dir:--}" >"$cache.gitdir" 2>/dev/null
  fi

  if [ -n "$git_dir" ] && [ "$git_dir" != "-" ] && [ -f "$git_dir/HEAD" ]; then
    read -r head <"$git_dir/HEAD"
    cached_head="" cached_branch=""
    if [ -f "$cache.branch" ]; then
      { read -r cached_head; read -r cached_branch; } <"$cache.branch"
    fi
    if [ -n "$cached_head" ] && [ "$cached_head" = "$head" ]; then
      BRANCH=$cached_branch
    else
      BRANCH=$(git --no-optional-locks -C "$DIR" branch --show-current 2>/dev/null)
      printf '%s\n%s\n' "$head" "$BRANCH" >"$cache.branch" 2>/dev/null
    fi
  fi
fi

line1="${bold}${cyan}${MODEL}${reset} ${dim}·${reset} ${DIR##*/}"
[ -n "$BRANCH" ] && line1+=" ${dim}·${reset} ${yellow}⎇ ${BRANCH}${reset}"
line1+=" ${dim}· \$$(printf '%.2f' "$COST")${reset}"

if ((ADDED > 0 || REMOVED > 0)); then
  line1+=" ${dim}· +${ADDED}/-${REMOVED}${reset}"
fi
if ((API_MS > 0)); then
  api_secs=$((API_MS / 1000))
  if ((api_secs < 60)); then
    line1+=" ${dim}· api ${api_secs}s${reset}"
  else
    line1+=" ${dim}· api $(format_duration "$api_secs")${reset}"
  fi
fi

# --- line 2: budget ---------------------------------------------------------

segments=()

if ((TOKENS >= 0)); then
  pct=$((TOKENS * 100 / BUDGET))
  color=$(budget_color "$pct")
  ctx_segment="${color}ctx $(format_tokens "$TOKENS")/$(format_tokens "$BUDGET") $(bar "$pct" 10) ${pct}%${reset}"
  ((pct >= 80)) && ctx_segment+=" ${red}${bold}/compact${reset}"
  segments+=("$ctx_segment")
elif ((CTX >= 0)); then
  # current_usage is null before the first call and right after /compact;
  # the model-window percentage is the best signal left.
  color=$(severity_color "$CTX")
  segments+=("${color}ctx $(bar "$CTX" 10) ${CTX}%${reset}")
fi

# Compactions this session: rg -c counts matching lines without parsing JSON.
# The quoted key/value pair only appears unescaped on real marker lines.
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && command -v rg >/dev/null 2>&1; then
  compactions=$(rg -c -F '"subtype":"compact_boundary"' "$TRANSCRIPT" 2>/dev/null)
  compactions=${compactions:-0}
  if ((compactions >= 3)); then
    segments+=("${red}⟲${compactions}${reset}")
  elif ((compactions == 2)); then
    segments+=("${yellow}⟲${compactions}${reset}")
  elif ((compactions == 1)); then
    segments+=("${dim}⟲${compactions}${reset}")
  fi
fi

if ((FIVE_PCT >= 0)); then
  color=$(severity_color "$FIVE_PCT")
  five_segment="${color}5h ${FIVE_PCT}%${reset}"
  five_segment+=$(pace_marker "$FIVE_PCT" "$FIVE_RESET" "$FIVE_HOUR_SECONDS")
  if ((FIVE_RESET > 0)); then
    five_segment+=" ${dim}($(format_duration $((FIVE_RESET - NOW))))${reset}"
  fi
  segments+=("$five_segment")
fi

if ((WEEK_PCT >= 0)); then
  color=$(severity_color "$WEEK_PCT")
  week_segment="${color}7d ${WEEK_PCT}%${reset}"
  week_segment+=$(pace_marker "$WEEK_PCT" "$WEEK_RESET" "$WEEK_SECONDS")
  segments+=("$week_segment")

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
