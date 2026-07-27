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
#   last-message-out file to receive codex's final report. Must not already
#                    exist: review is capped at two rounds and each round's
#                    report is evidence for the next decision, so pass a
#                    round-suffixed path (NNN-report-r1.md, then -r2.md).
#                    Written only after the report is validated, so a failed
#                    run leaves no partial report behind.
#   feedback-file    optional reviewer feedback for a REVISE round
#
# Environment overrides:
#   CODEX_MODEL    model id (default: gpt-5.6-terra)
#   CODEX_EFFORT   reasoning effort: low|medium|high|xhigh (default: medium —
#                  plans are fully specified, so execution rarely needs more)
#   CODEX_NICE     niceness for the codex process tree (default: 10)
#   CODEX_TIMEOUT  hard wall-clock cap in seconds (default: 3600). A run that
#                  hits this almost always means a command that never exits
#                  (watch mode, dev server) slipped through — investigate,
#                  don't just retry with a bigger number.
set -euo pipefail

plan_file=${1:-}
worktree=${2:-}
out_file=${3:-}
feedback_file=${4:-}

[[ -n "$plan_file" && -n "$worktree" && -n "$out_file" ]] || {
  echo "usage: $0 <plan-file> <worktree-dir> <last-message-out> [feedback-file]" >&2
  exit 2
}

[[ -f "$plan_file" ]] || { echo "plan file not found: $plan_file" >&2; exit 2; }
[[ -d "$worktree/.git" || -f "$worktree/.git" ]] || { echo "not a git worktree: $worktree" >&2; exit 2; }
[[ -z "$feedback_file" || -f "$feedback_file" ]] || {
  echo "feedback file not found: $feedback_file" >&2
  exit 2
}

model=${CODEX_MODEL:-gpt-5.6-terra}
effort=${CODEX_EFFORT:-medium}
niceness=${CODEX_NICE:-10}
timeout_s=${CODEX_TIMEOUT:-3600}

[[ "$timeout_s" =~ ^[0-9]+$ && "$timeout_s" -gt 0 ]] || {
  echo "CODEX_TIMEOUT must be a positive integer number of seconds: $timeout_s" >&2
  exit 2
}
[[ "$niceness" =~ ^-?[0-9]+$ ]] || { echo "CODEX_NICE must be an integer: $niceness" >&2; exit 2; }

# Check the report destination before spending an hour of executor time on it.
out_dir=$(dirname "$out_file")
[[ -d "$out_dir" ]] || { echo "report directory not found: $out_dir" >&2; exit 2; }
[[ ! -e "$out_file" ]] || {
  echo "report already exists: $out_file" >&2
  echo "use a round-suffixed path (…-r2.md) so the earlier round stays reviewable" >&2
  exit 2
}

prompt_file=$(mktemp)
report_tmp=$(mktemp "$out_dir/.improve-codex-report.XXXXXX")

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  rm -f "$prompt_file" "$report_tmp"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

{
  cat <<'PREAMBLE'
You are the executor for the implementation plan below. Follow it step by
step. Run every verification command and confirm the expected result before
moving on. Touch only the files listed as in scope. If any STOP condition in
the plan occurs, stop immediately and report. Do not improvise around
obstacles.

Commit your work in this worktree before you report. Follow the plan's git
workflow section when it has one; otherwise make focused commits with
conventional messages. Either way `git status --porcelain` must be empty when
you finish — staged, unstaged, or untracked implementation fails review no
matter how good the code is, because only committed work can be approved. Do
NOT push, do NOT open pull requests, and do NOT switch branches.
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
timeout_cmd=()
if command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout -k 30 "$timeout_s")
elif command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout -k 30 "$timeout_s")
else
  echo "ERROR: no timeout/gtimeout binary; refusing to run without a wall-clock cap" >&2
  exit 127
fi
# Hand the prompt over as an open fd and unlink it immediately, so plan text
# never lingers on disk if the run is killed.
exec 3<"$prompt_file"
rm -f "$prompt_file"

set +e
nice -n "$niceness" "${timeout_cmd[@]}" codex exec \
  -C "$worktree" \
  -s workspace-write \
  -c 'mcp_servers={}' \
  -c 'plugins={}' \
  -c "model_reasoning_effort=\"$effort\"" \
  --disable apps \
  --disable enable_mcp_apps \
  --disable hooks \
  --disable browser_use \
  --disable browser_use_external \
  --disable browser_use_full_cdp_access \
  --disable in_app_browser \
  --disable computer_use \
  --disable multi_agent \
  --disable multi_agent_v2 \
  --ephemeral \
  --output-last-message "$report_tmp" \
  -m "$model" \
  - <&3
codex_status=$?
set -e
if [[ $codex_status -ne 0 ]]; then
  exit "$codex_status"
fi

# A run that exits 0 without a usable report is still a failed run: fail closed
# here rather than leaving the reviewer to notice an empty or truncated file.
[[ -s "$report_tmp" ]] || { echo "ERROR: executor produced no report" >&2; exit 1; }
if ! awk '
  {
    line = $0
    gsub(/[*`]/, "", line)
    sub(/^[[:space:]]+/, "", line)
    if (line !~ /^STATUS[[:space:]]*:/) next
    body = toupper(substr(line, index(line, ":") + 1))
    gsub(/[^A-Z]+/, " ", body)
    sub(/^ /, "", body)
    sub(/ $/, "", body)
    # Both words means the report format line was echoed, not answered.
    if (body ~ /^COMPLETE/ && body !~ /STOPPED/) found = 1
    else if (body ~ /^STOPPED/ && body !~ /COMPLETE/) found = 1
  }
  END { exit !found }
' "$report_tmp"; then
  echo "ERROR: executor report has no 'STATUS: COMPLETE' or 'STATUS: STOPPED' line;" >&2
  echo "treat this as a failed run and inspect the worktree diff" >&2
  exit 1
fi

mv -f "$report_tmp" "$out_file"
