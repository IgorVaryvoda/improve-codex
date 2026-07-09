#!/usr/bin/env bash
# Run a read-only `codex exec` critic pass — either scrutinizing an
# implementation plan before dispatch, or adversarially reviewing an
# executor's diff after it. Same browser/MCP/plugin guards as
# run-codex-plan.sh, but the sandbox is read-only: the critic inspects,
# never writes.
#
# Usage:
#   run-codex-critic.sh plan <plan-file> <workdir>  <report-out>
#   run-codex-critic.sh diff <base-ref>  <worktree> <report-out>
#
#   plan mode: <plan-file> is inlined into the prompt; <workdir> is the tree
#              the critic reads to check the plan's assumptions against real
#              code (normally the main tree).
#   diff mode: the critic reviews `git diff <base-ref>...HEAD` inside
#              <worktree> (the executor's worktree; base-ref is the commit
#              the worktree was branched from).
#
# Environment overrides:
#   CODEX_CRITIC_MODEL   model id (default: gpt-5.6-sol)
#   CODEX_CRITIC_EFFORT  reasoning effort (default: high — critique is where
#                        the second model earns its keep)
#   CODEX_NICE           niceness for the codex process tree (default: 10)
#   CODEX_TIMEOUT        hard wall-clock cap in seconds (default: 1800)
set -euo pipefail

mode=$1
target=$2
workdir=$3
out_file=$4

case "$mode" in
  plan|diff) ;;
  *) echo "unknown mode: $mode (want plan|diff)" >&2; exit 2 ;;
esac
[[ -d "$workdir" ]] || { echo "workdir not found: $workdir" >&2; exit 2; }
if [[ "$mode" == plan ]]; then
  [[ -f "$target" ]] || { echo "plan file not found: $target" >&2; exit 2; }
else
  git -C "$workdir" rev-parse --verify --quiet "$target^{commit}" >/dev/null \
    || { echo "base ref not found in worktree: $target" >&2; exit 2; }
fi

model=${CODEX_CRITIC_MODEL:-gpt-5.6-sol}
effort=${CODEX_CRITIC_EFFORT:-high}
niceness=${CODEX_NICE:-10}
timeout_s=${CODEX_TIMEOUT:-1800}

prompt_file=$(mktemp)
trap 'rm -f "$prompt_file"' EXIT

shared_rules() {
  cat <<'RULES'
RESOURCE RULES — you are running read-only on a shared developer workstation:
- You may read files and run read-only inspection commands (git log/diff/show,
  grep, ls, cat). The sandbox blocks writes; do not fight it.
- Never launch, install, or drive a browser. Never start a dev server, watch
  mode, or any process that does not exit on its own.
- Do not run test suites or builds — reason from the code and the diff.

Report only what you can point to concrete evidence for (a file, a line, a
command output from this session). No style nitpicks, no speculative
"consider..." items — every issue must come with a failure you can describe.
RULES
}

{
  if [[ "$mode" == plan ]]; then
    cat <<'PREAMBLE'
You are a skeptical staff engineer reviewing an implementation plan before it
is handed to a cheaper executor model. The executor follows the plan
literally — every gap you miss becomes its bug. You have read access to the
repository this plan targets; verify the plan's claims against the actual
code instead of taking them on faith.

Attack, in order of importance:
- Assumptions the code contradicts: named files/functions/behaviors that do
  not exist or do not work as the plan states.
- Ambiguity a literal-minded executor could implement two different ways.
- Done criteria that can pass while the actual goal fails.
- Scope errors: files the plan will need but does not list, or listed files
  it should not touch.
- Missing failure paths: what the plan does when a step's assumption breaks.
- Verification steps that do not prove what they claim to prove.

PREAMBLE
    shared_rules
    cat <<'REPORT'

Reply with exactly this report format:

VERDICT: SOUND | NEEDS REVISION
ISSUES: numbered; per issue — severity (BLOCKER|MAJOR|MINOR), the plan
  section it is in, what is wrong, the evidence, and a concrete fix
CHECKED: which of the plan's claims you verified against the code
REPORT
    echo
    echo "== IMPLEMENTATION PLAN UNDER REVIEW =="
    cat "$target"
  else
    cat <<PREAMBLE
You are an adversarial reviewer of a diff produced by an executor model that
optimizes for "plan satisfied". Your job is to attack what that framing
misses. The diff under review is: git diff $target...HEAD in the current
directory (the executor's commits are on HEAD). Start by running that diff
and git log $target..HEAD, then read every changed file in full context.

Attack, in order of importance:
- Behavior changes outside the diff's evident intent.
- Failure paths: errors swallowed, partial writes, missing rollback.
- Tests that mock or stub the very thing they claim to prove.
- Second sources of truth: state or config duplicated instead of derived.
- Needless abstraction: indirection the change does not earn.
- Conventions the surrounding code follows and the diff breaks.

PREAMBLE
    shared_rules
    cat <<'REPORT'

Reply with exactly this report format:

FINDINGS: numbered; per finding — severity (BLOCKER|MAJOR|MINOR), file:line,
  the failure scenario, and the evidence. If nothing survives your own
  skepticism, reply exactly: NO FINDINGS
REPORT
  fi
} > "$prompt_file"

# Same guard layers as the executor runner, minus write access entirely:
# -s read-only means the critic cannot modify the tree it is judging.
exec nice -n "$niceness" timeout -k 30 "$timeout_s" codex exec \
  -C "$workdir" \
  -s read-only \
  -c 'mcp_servers={}' \
  -c 'plugins={}' \
  -c "model_reasoning_effort=\"$effort\"" \
  --ephemeral \
  --output-last-message "$out_file" \
  -m "$model" \
  - < "$prompt_file"
