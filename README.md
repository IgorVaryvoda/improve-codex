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
- fail closed when authentication, timeout support, or a nonce-verified critic
  verdict is missing.

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

Environment overrides:

- `CODEX_MODEL` (default `gpt-5.6-terra`)
- `CODEX_EFFORT` (default `medium`)
- `CODEX_CRITIC_MODEL` (default `gpt-5.6-sol`)
- `CODEX_CRITIC_EFFORT` (default `high`)
- `CODEX_NICE` (default `10`)
- `CODEX_TIMEOUT` (default `3600` seconds)

## License

MIT
