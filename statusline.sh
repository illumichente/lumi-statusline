#!/bin/bash
# Lumi statusline for Claude Code. Own code, no external updates.
# Input: Claude Code status JSON on stdin (see docs/en/statusline).
# Network: one GET to api.anthropic.com/api/oauth/usage (extra usage +
# per-model weekly limit), cached in ~/.claude/cache with mode 600.
# Runs on macOS, Linux and Windows (Git Bash). Needs bash, jq, curl.
set -f

input=$(cat)
[ -z "$input" ] && { printf "Claude"; exit 0; }

# ── Colors ──────────────────────────────────────────────
blue=$'\033[38;2;0;153;255m'
orange=$'\033[38;2;255;176;85m'
green=$'\033[38;2;0;175;80m'
cyan=$'\033[38;2;86;182;194m'
red=$'\033[38;2;255;85;85m'
yellow=$'\033[38;2;230;200;0m'
white=$'\033[38;2;220;220;220m'
magenta=$'\033[38;2;180;140;255m'
dim=$'\033[2m'
reset=$'\033[0m'
sep=" ${dim}│${reset} "

# ── Portability (BSD vs GNU userland) ───────────────────
if date -j -r 0 +%s >/dev/null 2>&1; then BSD_DATE=1; else BSD_DATE=0; fi

epoch_fmt() {   # epoch strftime-format
    if [ "$BSD_DATE" = 1 ]; then date -j -r "$1" +"$2" 2>/dev/null
    else date -d "@$1" +"$2" 2>/dev/null; fi
}
file_mtime() {   # GNU stat -f means "file system", so pick by userland, not by failure
    if [ "$BSD_DATE" = 1 ]; then stat -f %m "$1" 2>/dev/null
    else stat -c %Y "$1" 2>/dev/null; fi
}
next_month_first() {
    if [ "$BSD_DATE" = 1 ]; then date -v+1m -v1d +"%b %-d" 2>/dev/null
    else date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null; fi
}
parent_cmdline() {  # for the --dangerously-skip-permissions flag
    if [ -r "/proc/$PPID/cmdline" ]; then tr '\0' ' ' < "/proc/$PPID/cmdline" 2>/dev/null
    else ps -o args= -p "$PPID" 2>/dev/null; fi
}

# ── Helpers ─────────────────────────────────────────────
color_for_pct() {
    local p=${1%%.*}; p=${p:-0}
    if   [ "$p" -ge 90 ]; then printf '%s' "$red"
    elif [ "$p" -ge 70 ]; then printf '%s' "$yellow"
    elif [ "$p" -ge 50 ]; then printf '%s' "$orange"
    else printf '%s' "$green"; fi
}

build_bar() {   # pct width
    local p=${1%%.*} w=$2; p=${p:-0}
    [ "$p" -lt 0 ] && p=0; [ "$p" -gt 100 ] && p=100
    local filled=$(( p * w / 100 )) i f="" e=""
    for ((i=0; i<filled; i++)); do f+="●"; done
    for ((i=filled; i<w; i++)); do e+="○"; done
    printf '%s%s%s%s%s' "$(color_for_pct "$p")" "$f" "$dim" "$e" "$reset"
}

fmt_tokens() {  # 25000 -> 25k, 1000000 -> 1M, 1234567 -> 1.2M
    local n=${1:-0}
    if   [ "$n" -ge 1000000 ]; then awk -v n="$n" 'BEGIN{v=n/1000000; printf (v==int(v))?"%dM":"%.1fM", v}'
    elif [ "$n" -ge 1000 ];    then printf '%dk' $(( (n + 500) / 1000 ))
    else printf '%d' "$n"; fi
}

fmt_clock() {   # epoch -> 11:00pm | oct 20, 6:00am  (second arg "date" adds the day)
    local e=$1 s
    [ -z "$e" ] || [ "$e" = "null" ] || [ "$e" = "0" ] && return
    if [ "$2" = "date" ]; then s=$(epoch_fmt "$e" "%b %-d, %l:%M%p")
    else s=$(epoch_fmt "$e" "%l:%M%p"); fi
    printf '%s' "$s" | sed 's/  */ /g; s/^ //' | tr '[:upper:]' '[:lower:]'
}

fmt_countdown() {   # epoch -> 2h13m | 1d 8h | 45m
    local e=$1 d
    [ -z "$e" ] || [ "$e" = "null" ] || [ "$e" = "0" ] && return
    d=$(( e - $(date +%s) )); [ "$d" -le 0 ] && { printf 'now'; return; }
    if   [ "$d" -ge 86400 ]; then printf '%dd %dh' $(( d / 86400 )) $(( (d % 86400) / 3600 ))
    elif [ "$d" -ge 3600 ];  then printf '%dh%02dm' $(( d / 3600 )) $(( (d % 3600) / 60 ))
    else printf '%dm' $(( d / 60 )); fi
}

fmt_duration() {    # ms -> 1h12m | 7m | 30s
    local s=$(( ${1:-0} / 1000 ))
    if   [ "$s" -ge 3600 ]; then printf '%dh%02dm' $(( s / 3600 )) $(( (s % 3600) / 60 ))
    elif [ "$s" -ge 60 ];   then printf '%dm' $(( s / 60 ))
    else printf '%ds' "$s"; fi
}

iso_to_epoch() {    # 2026-10-19T21:00:00.415177+00:00 -> epoch (UTC only, as the API returns)
    [ -z "$1" ] && return
    local s=${1%%.*}; s=${s%%+*}; s=${s%%Z}
    if [ "$BSD_DATE" = 1 ]; then env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$s" +%s 2>/dev/null
    else env TZ=UTC date -d "${s/T/ }" +%s 2>/dev/null; fi
}

# ── Parse stdin in one jq pass ──────────────────────────
IFS=$'\x1f' read -r model_name ctx_size in_tok cc_tok cr_tok ctx_pct over200k cwd \
    effort fast thinking session_name cost dur_ms lines_add lines_del \
    cache_warm cache_hit cache_seen fh_pct fh_reset sd_pct sd_reset < <(
    echo "$input" | jq -r '[
        (.model.display_name // "Claude"),
        (.context_window.context_window_size // 200000),
        (.context_window.current_usage.input_tokens // 0),
        (.context_window.current_usage.cache_creation_input_tokens // 0),
        (.context_window.current_usage.cache_read_input_tokens // 0),
        (.context_window.used_percentage // "" | tostring),
        (.exceeds_200k_tokens // false),
        (.workspace.current_dir // .cwd // ""),
        (.effort.level // ""),
        (.fast_mode // false),
        (.thinking.enabled | tostring),
        (.session_name // ""),
        (.cost.total_cost_usd // 0),
        (.cost.total_duration_ms // 0),
        (.cost.total_lines_added // 0),
        (.cost.total_lines_removed // 0),
        (.prompt_cache.warm | tostring),
        (.prompt_cache.hit_ratio // ""),
        (.prompt_cache.caching_observed | tostring),
        (.rate_limits.five_hour.used_percentage // ""),
        (.rate_limits.five_hour.resets_at // ""),
        (.rate_limits.seven_day.used_percentage // ""),
        (.rate_limits.seven_day.resets_at // "")
    ] | map(tostring) | join("\u001f")')

# ── Context: percent + absolute ─────────────────────────
ctx_used=$(( in_tok + cc_tok + cr_tok ))
[ "$ctx_size" -le 0 ] 2>/dev/null && ctx_size=200000
if [ -n "$ctx_pct" ]; then ctx_pct=${ctx_pct%%.*}; else ctx_pct=$(( ctx_used * 100 / ctx_size )); fi
ctx_color=$(color_for_pct "$ctx_pct")
ctx_seg="✍️ ${ctx_color}${ctx_pct}%${reset} ${white}$(fmt_tokens "$ctx_used")${dim}/${reset}${white}$(fmt_tokens "$ctx_size")${reset}"
if [ "$over200k" = "true" ] && [ "$ctx_size" -gt 200000 ]; then
    ctx_seg+=" ${red}>200k \$\$${reset}"      # long-context pricing tier is on
fi

# ── Directory + git ─────────────────────────────────────
[ -z "$cwd" ] && cwd=$(pwd)
dir_seg="${cyan}$(basename "$cwd")${reset}"
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    br=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    dirty=""; [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ] && dirty="${red}*"
    [ -n "$br" ] && dir_seg+=" ${green}(${br}${dirty}${green})${reset}"
fi

# ── Effort ──────────────────────────────────────────────
case "$effort" in
    max|xhigh) effort_seg="${red}● ${effort}${reset}" ;;
    high)      effort_seg="${magenta}● ${effort}${reset}" ;;
    medium)    effort_seg="${dim}◑ ${effort}${reset}" ;;
    low)       effort_seg="${dim}◔ ${effort}${reset}" ;;
    *)         effort_seg="" ;;
esac

# ── Mode flags (shown only when non-default) ────────────
flags=()
[ "$fast" = "true" ] && flags+=("${yellow}⚡fast${reset}")
[ "$thinking" = "false" ] && flags+=("${dim}🧠off${reset}")
if [[ "$(parent_cmdline)" == *"--dangerously-skip-permissions"* ]]; then
    flags+=("${red}⚡skip-perms${reset}")
fi
flags_seg=""; for f in "${flags[@]}"; do flags_seg+="${flags_seg:+ · }$f"; done

# ── Line 1 ──────────────────────────────────────────────
line1="${blue}${model_name}${reset}${sep}${ctx_seg}${sep}${dir_seg}"
[ -n "$effort_seg" ] && line1+="${sep}${effort_seg}"
[ -n "$flags_seg" ]  && line1+="${sep}${flags_seg}"
[ -n "$session_name" ] && line1+="${sep}${dim}«${reset}${white}${session_name}${reset}${dim}»${reset}"

# ── Line 2: session stats ───────────────────────────────
line2="${dim}⏱${reset} ${white}$(fmt_duration "$dur_ms")${reset}"
line2+="${sep}${green}+${lines_add}${reset}${dim}/${reset}${red}−${lines_del}${reset}"
line2+="${sep}${white}\$$(printf '%.2f' "$cost")${reset} ${dim}api-eq${reset}"
if [ "$cache_seen" = "true" ]; then
    hit=""; [ -n "$cache_hit" ] && hit=$(awk -v h="$cache_hit" 'BEGIN{printf "%d%%", h*100}')
    if [ "$cache_warm" = "true" ]; then line2+="${sep}${dim}cache${reset} ${green}●${reset} ${white}${hit}${reset}"
    else line2+="${sep}${dim}cache ○ cold${reset}"; fi
fi

# ── Usage API (extra usage + per-model weekly; rates fallback) ──
cache_dir="$HOME/.claude/cache"
cache_file="$cache_dir/statusline-usage.json"
cache_max_age=120
usage=""
if [ -f "$cache_file" ] && [ $(( $(date +%s) - $(file_mtime "$cache_file") )) -lt "$cache_max_age" ]; then
    usage=$(cat "$cache_file")
else
    # Token sources, first hit wins: env, macOS Keychain, ~/.claude/.credentials.json
    # (Linux, Windows), libsecret (some Linux setups).
    token="${CLAUDE_CODE_OAUTH_TOKEN:-}"
    if [ -z "$token" ] && command -v security >/dev/null 2>&1; then
        token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
                | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    fi
    if [ -z "$token" ] && [ -r "$HOME/.claude/.credentials.json" ]; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
    fi
    if [ -z "$token" ] && command -v secret-tool >/dev/null 2>&1; then
        token=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null \
                | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    fi
    if [ -n "$token" ]; then
        resp=$(curl -s --max-time 4 \
            -H "Accept: application/json" \
            -H "Authorization: Bearer $token" \
            -H "User-Agent: lumi-statusline/1.0" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        unset token
        if echo "$resp" | jq -e '.five_hour' >/dev/null 2>&1; then
            usage="$resp"
            mkdir -p "$cache_dir"; umask 077
            printf '%s' "$usage" > "$cache_file"; chmod 600 "$cache_file"
        fi
    fi
    [ -z "$usage" ] && [ -f "$cache_file" ] && usage=$(cat "$cache_file")   # stale beats nothing
fi

# Rates: stdin is primary, API is fallback (before first API response in a session)
if [ -z "$fh_pct" ] && [ -n "$usage" ]; then
    fh_pct=$(echo "$usage" | jq -r '.five_hour.utilization // empty')
    fh_reset=$(iso_to_epoch "$(echo "$usage" | jq -r '.five_hour.resets_at // empty')")
    sd_pct=$(echo "$usage" | jq -r '.seven_day.utilization // empty')
    sd_reset=$(iso_to_epoch "$(echo "$usage" | jq -r '.seven_day.resets_at // empty')")
fi

# ── Rate lines ──────────────────────────────────────────
rate_line() {   # label pct reset_epoch clock_style
    local label=$1 pct=${2%%.*} e=$3 style=$4 clock cd
    [ -z "$pct" ] && return
    printf '%s%-7s%s %s %s%3d%%%s' "$white" "$label" "$reset" "$(build_bar "$pct" 10)" "$(color_for_pct "$pct")" "$pct" "$reset"
    clock=$(fmt_clock "$e" "$style"); cd=$(fmt_countdown "$e")
    [ -n "$clock" ] && printf ' %s⟳%s %s%s%s %s(%s)%s' "$dim" "$reset" "$white" "$clock" "$reset" "$dim" "$cd" "$reset"
}

lines=()
r=$(rate_line "current" "$fh_pct" "$fh_reset" time); [ -n "$r" ] && lines+=("$r")
r=$(rate_line "weekly"  "$sd_pct" "$sd_reset" date); [ -n "$r" ] && lines+=("$r")

if [ -n "$usage" ]; then
    # Per-model weekly limits (limits[] kind=weekly_scoped, scope.model.display_name)
    while IFS=$'\x1f' read -r mname mpct mreset; do
        [ -z "$mname" ] && continue
        r=$(rate_line "$(echo "$mname" | tr '[:upper:]' '[:lower:]')" "$mpct" "$(iso_to_epoch "$mreset")" date)
        [ -n "$r" ] && lines+=("$r")
    done < <(echo "$usage" | jq -r '.limits[]? | select(.kind=="weekly_scoped")
        | [(.scope.model.display_name // "model"), (.percent // 0), (.resets_at // "")] | map(tostring) | join("\u001f")')

    # Extra usage (credits beyond the plan), amounts in minor units
    if [ "$(echo "$usage" | jq -r '.extra_usage.is_enabled // false')" = "true" ]; then
        IFS=$'\x1f' read -r x_used x_limit x_dec < <(echo "$usage" | jq -r '.extra_usage
            | [(.used_credits // 0), (.monthly_limit // 0), (.decimal_places // 2)] | map(tostring) | join("\u001f")')
        x_pct=$(awk -v u="$x_used" -v l="$x_limit" 'BEGIN{printf "%d", (l>0)? u*100/l : 0}')
        x_used_fmt=$(awk -v v="$x_used" -v d="$x_dec" 'BEGIN{printf "%.2f", v/(10^d)}')
        x_limit_fmt=$(awk -v v="$x_limit" -v d="$x_dec" 'BEGIN{printf "%.2f", v/(10^d)}')
        x_reset=$(next_month_first | tr '[:upper:]' '[:lower:]')
        lines+=("$(printf '%s%-7s%s %s %s$%s%s/%s$%s%s %s⟳%s %s%s%s' \
            "$white" "extra" "$reset" "$(build_bar "$x_pct" 10)" \
            "$(color_for_pct "$x_pct")" "$x_used_fmt" "$dim" "$white" "$x_limit_fmt" "$reset" \
            "$dim" "$reset" "$white" "$x_reset" "$reset")")
    fi
fi

# ── Output ──────────────────────────────────────────────
printf '%s\n%s\n' "$line1" "$line2"
if [ ${#lines[@]} -gt 0 ]; then
    printf '\n'
    printf '%s\n' "${lines[@]}"
fi
exit 0
