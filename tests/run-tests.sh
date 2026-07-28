#!/usr/bin/env bash
# Test suite for the improve-codex runner scripts. Drives run-codex-plan.sh and
# run-codex-critic.sh against the stubbed codex CLI in tests/stub-bin, checking
# the guardrails the docs promise: argument and override validation, refusal to
# clobber round reports, fail-closed report/verdict handling, and that a failed
# run leaves no partial report behind.
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
scripts="$root/skills/improve-codex/scripts"
export PATH="$root/tests/stub-bin:$PATH"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

# run <name> <expected-exit> <cmd...> — run a command, compare its exit status.
run() {
  local name=$1 want=$2 got=0
  shift 2
  "$@" >"$tmp/stdout" 2>"$tmp/stderr" || got=$?
  if [[ "$got" -eq "$want" ]]; then
    pass=$((pass + 1))
    echo "ok: $name"
  else
    fail=$((fail + 1))
    echo "FAIL: $name (exit $got, wanted $want)"
    sed 's/^/    stderr: /' "$tmp/stderr"
  fi
}

# check <name> <cmd...> — assert a follow-up condition on the last run's state.
check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1))
    echo "ok: $name"
  else
    fail=$((fail + 1))
    echo "FAIL: $name"
  fi
}

no_partials() {
  [[ -z $(find "$1" -name '.improve-codex-*' -print -quit) ]]
}

stderr_has() {
  grep -q "$1" "$tmp/stderr"
}

# --- fixture: a plain git repo doubles as the worktree ---
repo="$tmp/repo"
git init -q "$repo"
mkdir -p "$repo/plans"
printf '# Plan 001\n\nRename the widget and update its tests.\n' > "$repo/plans/001-test.md"
git -C "$repo" add plans
git -C "$repo" -c user.email=tests@example.invalid -c user.name=tests \
  commit -qm "test fixture"
base=$(git -C "$repo" rev-parse HEAD)

out="$tmp/out"
mkdir -p "$out"
plan="$scripts/run-codex-plan.sh"
critic="$scripts/run-codex-critic.sh"

echo "== run-codex-plan.sh =="

run "plan: usage error on missing args" 2 "$plan" "$repo/plans/001-test.md"
run "plan: missing plan file rejected" 2 "$plan" "$repo/plans/nope.md" "$repo" "$out/r.md"
run "plan: non-worktree dir rejected" 2 "$plan" "$repo/plans/001-test.md" "$tmp" "$out/r.md"
run "plan: missing feedback file rejected" 2 \
  "$plan" "$repo/plans/001-test.md" "$repo" "$out/r.md" "$tmp/no-feedback.md"
run "plan: missing report directory rejected" 2 \
  "$plan" "$repo/plans/001-test.md" "$repo" "$tmp/nowhere/r.md"
run "plan: bad CODEX_TIMEOUT rejected" 2 \
  env CODEX_TIMEOUT=soon "$plan" "$repo/plans/001-test.md" "$repo" "$out/r.md"
run "plan: bad CODEX_NICE rejected" 2 \
  env CODEX_NICE=gentle "$plan" "$repo/plans/001-test.md" "$repo" "$out/r.md"
run "plan: config-breaking CODEX_EFFORT rejected" 2 \
  env CODEX_EFFORT='low" model="x' "$plan" "$repo/plans/001-test.md" "$repo" "$out/r.md"

run "plan: COMPLETE report accepted" 0 \
  env CODEX_STUB_MODE=complete CODEX_STUB_PROMPT_COPY="$tmp/prompt-1.txt" \
  "$plan" "$repo/plans/001-test.md" "$repo" "$out/001-report-r1.md"
check "plan: report written to destination" grep -q '^STATUS: COMPLETE' "$out/001-report-r1.md"
check "plan: prompt inlines the plan text" grep -q 'Rename the widget' "$tmp/prompt-1.txt"
check "plan: no stray temp reports" no_partials "$out"

run "plan: existing report refused" 2 \
  env CODEX_STUB_MODE=complete "$plan" "$repo/plans/001-test.md" "$repo" "$out/001-report-r1.md"
check "plan: refusal names round-suffixed paths" stderr_has 'round-suffixed'

printf '[MAJOR] the rename missed the tests.\n' > "$tmp/feedback.md"
run "plan: STOPPED report accepted with feedback" 0 \
  env CODEX_STUB_MODE=stopped CODEX_STUB_PROMPT_COPY="$tmp/prompt-2.txt" \
  "$plan" "$repo/plans/001-test.md" "$repo" "$out/001-report-r2.md" "$tmp/feedback.md"
check "plan: prompt carries reviewer feedback" grep -q 'the rename missed the tests' "$tmp/prompt-2.txt"
check "plan: feedback prompt flags the REVISE round" grep -q 'REVIEWER FEEDBACK' "$tmp/prompt-2.txt"

run "plan: report without STATUS line fails" 1 \
  env CODEX_STUB_MODE=no-status "$plan" "$repo/plans/001-test.md" "$repo" "$out/bad-1.md"
check "plan: no report left after STATUS failure" test ! -e "$out/bad-1.md"
run "plan: echoed report format rejected" 1 \
  env CODEX_STUB_MODE=echoed-format "$plan" "$repo/plans/001-test.md" "$repo" "$out/bad-2.md"
run "plan: empty report fails" 1 \
  env CODEX_STUB_MODE=empty-report "$plan" "$repo/plans/001-test.md" "$repo" "$out/bad-3.md"
run "plan: codex exit status propagated" 3 \
  env CODEX_STUB_MODE=exit-fail "$plan" "$repo/plans/001-test.md" "$repo" "$out/bad-4.md"
check "plan: failed runs leave no partial reports" no_partials "$out"
# shellcheck disable=SC2016 # $1 is for the inner bash, not this shell
check "plan: failed runs leave no report files" \
  bash -c '! ls "$1"/bad-*.md 2>/dev/null' _ "$out"

echo "== run-codex-critic.sh =="

run "critic: unknown mode rejected" 2 "$critic" review "$repo/plans/001-test.md" "$repo" "$out/c.md"
run "critic: plan outside worktree rejected" 2 "$critic" plan "$tmp/feedback.md" "$repo" "$out/c.md"
run "critic: invalid diff base rejected" 2 "$critic" diff not-a-ref "$repo" "$out/c.md"
run "critic: config-breaking CODEX_CRITIC_EFFORT rejected" 2 \
  env CODEX_CRITIC_EFFORT='high" foo="bar' "$critic" plan "$repo/plans/001-test.md" "$repo" "$out/c.md"

run "critic: nonce-matched APPROVE accepted" 0 \
  env CODEX_STUB_MODE=approve "$critic" plan "$repo/plans/001-test.md" "$repo" "$out/001-scrutiny-r1.md"
check "critic: report written to destination" grep -q 'APPROVE' "$out/001-scrutiny-r1.md"
run "critic: existing report refused" 2 \
  env CODEX_STUB_MODE=approve "$critic" plan "$repo/plans/001-test.md" "$repo" "$out/001-scrutiny-r1.md"

run "critic: diff mode with valid base accepted" 0 \
  env CODEX_STUB_MODE=approve "$critic" diff "$base" "$repo" "$out/001-adversarial-r1.md"

run "critic: wrong nonce fails closed" 1 \
  env CODEX_STUB_MODE=wrong-nonce "$critic" plan "$repo/plans/001-test.md" "$repo" "$out/cbad-1.md"
run "critic: hedged verdict fails closed" 1 \
  env CODEX_STUB_MODE=hedged-verdict "$critic" plan "$repo/plans/001-test.md" "$repo" "$out/cbad-2.md"
run "critic: double verdict fails closed" 1 \
  env CODEX_STUB_MODE=double-verdict "$critic" plan "$repo/plans/001-test.md" "$repo" "$out/cbad-3.md"
run "critic: empty report fails" 1 \
  env CODEX_STUB_MODE=empty-report "$critic" plan "$repo/plans/001-test.md" "$repo" "$out/cbad-4.md"
run "critic: codex exit status propagated" 3 \
  env CODEX_STUB_MODE=exit-fail "$critic" plan "$repo/plans/001-test.md" "$repo" "$out/cbad-5.md"
check "critic: failed runs leave no partial reports" no_partials "$out"
# shellcheck disable=SC2016 # $1 is for the inner bash, not this shell
check "critic: failed runs leave no report files" \
  bash -c '! ls "$1"/cbad-*.md 2>/dev/null' _ "$out"

run "critic: untagged NEEDS REVISION still succeeds" 0 \
  env CODEX_STUB_MODE=revision-untagged "$critic" plan "$repo/plans/001-test.md" "$repo" "$out/001-scrutiny-r2.md"
check "critic: untagged NEEDS REVISION warns" stderr_has 'WARNING: NEEDS REVISION'
run "critic: tagged NEEDS REVISION succeeds" 0 \
  env CODEX_STUB_MODE=revision-tagged "$critic" diff "$base" "$repo" "$out/001-adversarial-r2.md"
# shellcheck disable=SC2016 # $1 is for the inner bash, not this shell
check "critic: tagged NEEDS REVISION does not warn" \
  bash -c '! grep -q WARNING "$1"' _ "$tmp/stderr"

echo
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
