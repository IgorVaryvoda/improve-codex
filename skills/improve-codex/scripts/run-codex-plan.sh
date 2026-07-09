#!/usr/bin/env bash
# Run one improve-skill plan through `codex exec` inside an isolated git
# worktree, with every browser/MCP/plugin surface disabled and CPU priority
# lowered. The plan file is inlined into the prompt from the MAIN tree, so it
# does not need to be committed for the worktree to see it.
#
# Usage:
#   run-codex-plan.sh <plan-file> <worktree-dir> <last-message-out> [feedback-file]
#
#   plan-file        path to plans/NNN-slug.md in the main working tree
#   worktree-dir     existing git worktree the executor may write to
#   last-message-out file to receive codex's final report
#   feedback-file    optional reviewer feedback for a REVISE round
#
# Environment overrides:
#   CODEX_MODEL    model id (default: gpt-5.6-terra — the executor tier;
#                  scrutiny/review runs use run-codex-critic.sh instead)
#   CODEX_EFFORT   reasoning effort: low|medium|high|xhigh (default: medium —
#                  plans are fully specified, so execution rarely needs more)
#   CODEX_NICE     niceness for the codex process tree (default: 10)
#   CODEX_TIMEOUT  hard wall-clock cap in seconds (default: 3600). A run that
#                  hits this almost always means a command that never exits
#                  (watch mode, dev server) slipped through — investigate,
#                  don't just retry with a bigger number.
set -euo pipefail

plan_file=$1
worktree=$2
out_file=$3
feedback_file=${4:-}

[[ -f "$plan_file" ]] || { echo "plan file not found: $plan_file" >&2; exit 2; }
[[ -d "$worktree/.git" || -f "$worktree/.git" ]] || { echo "not a git worktree: $worktree" >&2; exit 2; }

model=${CODEX_MODEL:-gpt-5.6-terra}
effort=${CODEX_EFFORT:-medium}
niceness=${CODEX_NICE:-10}
timeout_s=${CODEX_TIMEOUT:-3600}

prompt_file=$(mktemp)
trap 'rm -f "$prompt_file"' EXIT

{
  cat <<'PREAMBLE'
You are the executor for the implementation plan below. Follow it step by
step. Run every verification command and confirm the expected result before
moving on. Touch only the files listed as in scope. If any STOP condition in
the plan occurs, stop immediately and report. Do not improvise around
obstacles.

Commit your work in this worktree following the plan's git workflow section,
but do NOT push, do NOT open pull requests, and do NOT switch branches.
One override: SKIP any instruction in the plan to update plans/README.md —
your reviewer maintains that index.

RESOURCE RULES — this machine is a shared developer workstation. Violating
any of these fails review regardless of code quality:
- Never launch, install, or drive a browser. No playwright, puppeteer,
  chromium, chrome, agent-browser, headless browsers, screenshots, or
  `playwright install`.
- Never start a long-running process: no dev servers, no storybook, no watch
  mode, nothing that does not exit on its own.
- No E2E or browser-based integration suites. If a verification step in the
  plan needs a browser, skip it and record that in NOTES for the reviewer.
- Run only the commands the plan's command table names, scoped the way the
  plan scopes them. Prefer focused test runs over whole-repo suites.
- Install dependencies only if the plan's command table says to.

Before reporting, audit every claim in your report against an actual command
result from this session — only report what you can point to evidence for;
if a verification failed or was skipped, say so plainly.

When finished, reply with exactly this report format:

STATUS: COMPLETE | STOPPED
STEPS: per step — done/skipped + verification command result
STOPPED BECAUSE: (only if STOPPED) which STOP condition, what was observed
FILES CHANGED: list
NOTES: deviations, surprises, judgment calls, skipped browser verifications
PREAMBLE
  echo
  if [[ -n "$feedback_file" ]]; then
    echo "== REVIEWER FEEDBACK — a previous attempt was reviewed in this same"
    echo "worktree; its work is present. Address every point below. =="
    cat "$feedback_file"
    echo
  fi
  echo "== IMPLEMENTATION PLAN =="
  cat "$plan_file"
} > "$prompt_file"

# -c 'mcp_servers={}' and -c 'plugins={}' clear every MCP server and plugin
# from the user config — including browser/chrome plugins and browser-backed
# MCP servers. Verified: with these set, codex reports no browser-control
# tools. -s workspace-write confines writes to the worktree.
exec nice -n "$niceness" timeout -k 30 "$timeout_s" codex exec \
  -C "$worktree" \
  -s workspace-write \
  -c 'mcp_servers={}' \
  -c 'plugins={}' \
  -c "model_reasoning_effort=\"$effort\"" \
  --ephemeral \
  --output-last-message "$out_file" \
  -m "$model" \
  - < "$prompt_file"
