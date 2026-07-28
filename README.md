# improve-codex

A Codex skill that turns an `improve` audit into reviewed implementation work.

It separates planning, execution, and criticism:

```text
current Codex session  -> audit, plan, dispatch, final verdict
gpt-5.6-sol            -> hostile plan scrutiny and final diff criticism
gpt-5.6-terra          -> sandboxed implementation
Symphony/Clanker       -> serialized execution and convergence when the repo supports it
direct runner          -> portable isolated-worktree fallback
```

## Install

```bash
npx skills add igorvaryvoda/improve-codex
```

Prerequisites:

- the [improve](https://github.com/shadcn/improve) skill;
- an installed and authenticated [Codex CLI](https://developers.openai.com/codex/cli).

Symphony and Clanker Army are optional. The skill uses them only when the target
repository already exposes a reviewed compiler command, Symphony command,
serialized workflow profile, and integration metadata contract. It does not
copy Sirv Studio orchestration into unrelated repositories.

## Usage

```text
$improve-codex
$improve-codex deep security
$improve-codex execute
$improve-codex execute 012 014
```

Bare arguments pass through to `improve`. `execute` skips the audit and runs
existing TODO plans. Model and effort requests map to the executor; critic
settings remain independent.

## Workflow

1. Run `improve` and write self-contained numbered plans.
2. Scrutinize each plan with Sol in a read-only, browser-free critic process.
3. Select plans in dependency order and choose the execution lane.
4. Prefer repo-local Symphony/Clanker orchestration when its complete contract
   exists. Otherwise run one guarded Terra executor per isolated worktree.
5. Re-run done criteria and require both an advisor pass and a Sol diff pass.
6. Return APPROVE, REVISE, or BLOCK. The skill never merges or pushes approved
   implementation branches.
7. Cap review at two rounds per plan. A plan that still has major blockers
   after the second round is split into smaller plans or retired and
   re-approached — never sent through a third round.

## Portable runner guardrails

The bundled direct runner and critic:

- disable MCP servers and plugins;
- disable browser, app, hook, computer-use, and multi-agent feature surfaces
  while preserving the operator's provider routing, shell environment policy,
  and exec-policy rules;
- run in workspace-write or read-only sandboxes;
- prohibit browsers, dev servers, watch mode, Storybook, and E2E suites;
- run under `nice` and a mandatory `timeout` or `gtimeout`;
- validate the report destination and environment overrides before spending
  executor time, and refuse to overwrite an earlier round's report;
- fail closed when authentication, timeout support, an executor `STATUS` line,
  or a nonce-verified critic verdict is missing — a run that exits zero without
  a usable report is a failed run, and no partial report is left behind.

Browser-dependent verification stays with the main session or user after the
executor reports it as skipped.

## Runners

Executor:

```bash
skills/improve-codex/scripts/run-codex-plan.sh \
  <plan-file> <worktree> <report-out> [feedback-file]
```

Critic:

```bash
skills/improve-codex/scripts/run-codex-critic.sh plan \
  <plan-file> <worktree> <report-out>

skills/improve-codex/scripts/run-codex-critic.sh diff \
  <base-ref> <worktree> <report-out>
```

Critic findings are tagged `[BLOCKER]`, `[MAJOR]`, or `[MINOR]`; `NEEDS
REVISION` means at least one blocker or major finding stands, and surviving
those in round two is what triggers a split or retirement. Give every round its
own `<report-out>` path (`NNN-adversarial-r1.md`, then `-r2.md`) — the runners
refuse to clobber an existing report, because comparing rounds is how a finding
that survived its own fix is spotted.

Environment overrides:

- `CODEX_MODEL` (default `gpt-5.6-terra`)
- `CODEX_EFFORT` (default `medium`)
- `CODEX_CRITIC_MODEL` (default `gpt-5.6-sol`)
- `CODEX_CRITIC_EFFORT` (default `high`)
- `CODEX_NICE` (default `10`)
- `CODEX_TIMEOUT` (default `3600` seconds)

## Development

CI lints every script with shellcheck, checks that the runner entrypoints stay
executable, validates the plugin manifests, and runs the runner test suite.
Run it locally with:

```bash
shellcheck -x skills/improve-codex/scripts/*.sh tests/run-tests.sh tests/stub-bin/codex
tests/run-tests.sh
```

The suite drives both runners against a stubbed `codex` CLI
(`tests/stub-bin/codex`) and asserts the guardrails above: argument and
override validation, refusal to clobber round reports, fail-closed report and
nonce-verdict handling, and that a failed run leaves no partial report behind.

## License

MIT
