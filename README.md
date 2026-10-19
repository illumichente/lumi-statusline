# lumi-statusline

A status line for [Claude Code](https://code.claude.com) that shows context usage
in absolute numbers, subscription limits with countdowns, per-model weekly limits,
extra-usage credits, session stats and mode flags. One bash file, no dependencies
beyond `jq` and `curl`, no install magic.

```
Fable 5.1 [1m] │ ✍️ 25% 254k/1M >200k $$ │ my-app (main*) │ ● high │ ⚡fast · 🧠off │ «session name»
⏱ 1h12m │ +156/−23 │ $4.20 api-eq │ cache ● 91%

current ○○○○○○○○○○   4% ⟳ 11:00pm (32m)
weekly  ○○○○○○○○○○   7% ⟳ oct 20, 6:00am (7h32m)
fable   ●○○○○○○○○○  14% ⟳ oct 20, 6:00am (7h32m)
extra   ○○○○○○○○○○ $0.00/$200.00 ⟳ nov 1
```

## What each item means

**Line 1**

| Item | Meaning |
|---|---|
| `Fable 5.1 [1m]` | Current model. `[1m]` marks the 1M-token context variant. |
| `✍️ 25% 254k/1M` | Context window usage: percent and absolute tokens out of the window size. Counts input + cache write + cache read, not output. |
| `>200k $$` | Shown only on 1M models once input exceeds 200k tokens: long-context pricing is now in effect, limits burn faster. Time to `/compact`. |
| `my-app (main*)` | Working directory and git branch. Red `*` = uncommitted changes. |
| `● high` | Reasoning effort. Purple = high, red = xhigh/max, dim = medium/low. Reflects mid-session `/effort` changes. |
| `⚡fast · 🧠off` | Mode flags, shown only when non-default: fast mode on, extended thinking off, `⚡skip-perms` when started with `--dangerously-skip-permissions`. |
| `«session name»` | Name from `/rename` or `--name`, or the auto-generated title. Hidden when there is none. |

**Line 2**

| Item | Meaning |
|---|---|
| `⏱ 1h12m` | Wall-clock time the session has been running (accumulates across resumes). |
| `+156/−23` | Lines of code added / removed this session. |
| `$4.20 api-eq` | What the session would cost at API list price. On a subscription you don't pay this; it's a measure of how heavy the session is. Resets on `/clear`. |
| `cache ● 91%` | Prompt cache state. `●` warm = next request re-reads context cheaply; `○ cold` = the next request re-caches everything. The percent is the share of input tokens served from cache this session. |

**Limit lines**

| Line | Meaning |
|---|---|
| `current` | 5-hour subscription window: percent used, reset time, countdown. |
| `weekly` | 7-day window across all models. |
| `fable` / `opus` / … | Per-model weekly limit, one line per model Anthropic reports. Usually the one you hit first. |
| `extra` | Extra-usage credits spent beyond the plan and the monthly cap. Resets on the 1st. |

Colors: green < 50% < orange < 70% < yellow < 90% < red.

## Requirements

- macOS, Linux, or Windows with Git Bash (Claude Code on Windows runs status lines through Git Bash)
- Claude Code 2.1.251 or newer, claude.ai Pro / Max subscription (for the limit lines)
- `jq` and `curl`: `brew install jq` / `sudo apt install jq` / `winget install jqlang.jq`
- Windows: use Windows Terminal or another terminal with Unicode and 24-bit color; the legacy console
  renders the bars and icons poorly

## Install

```bash
git clone https://github.com/illumichente/lumi-statusline.git
cd lumi-statusline
./install.sh
```

The installer copies `statusline.sh` to `~/.claude/`, backs up any existing status line to
`statusline.sh.bak`, and sets `statusLine` in `~/.claude/settings.json` (with `refreshInterval: 30`
so countdowns tick while idle). Uninstall with `./install.sh --uninstall`.

On Windows run the three commands inside Git Bash, not PowerShell.

## Privacy, what the script touches

- **Reads** the JSON Claude Code pipes to it on stdin (model, context, cost, rate limits).
- **Reads** your Claude Code OAuth token from where Claude Code itself stores it: `$CLAUDE_CODE_OAUTH_TOKEN`
  if set, else the macOS Keychain entry `Claude Code-credentials`, else `~/.claude/.credentials.json`
  (Linux, Windows), else libsecret via `secret-tool`. It sends exactly one request with it, to
  `https://api.anthropic.com/api/oauth/usage`, at most once per 2 minutes. That is the same endpoint
  Claude Code's own `/usage` command uses. It is the only network call in the file. The token is never
  written to disk.
- **Writes** the API response to `~/.claude/cache/statusline-usage.json` with mode 600.
- Runs `git` in the current directory for the branch / dirty marker, and reads the parent process
  command line (`/proc` or `ps`) to detect `--dangerously-skip-permissions`.

The limit lines degrade gracefully: if the API call fails, `current` / `weekly` still come from stdin
and only the per-model and `extra` lines disappear.

## Tested on

macOS (Apple Silicon) and Linux (Ubuntu, uutils coreutils). Windows / Git Bash follows the same GNU
code path but has not been run by the author yet; if something looks off there, open an issue with the
output of `echo '{}' | bash ~/.claude/statusline.sh`.

## Credits

Layout and color scheme inspired by
[kamranahmedse/claude-statusline](https://github.com/kamranahmedse/claude-statusline) (MIT).
Rewritten from scratch.

## License

MIT
