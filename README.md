# improve-codex

An agent skill that audits your codebase with [improve](https://github.com/shadcn/improve), then hands every plan to [OpenAI Codex](https://developers.openai.com/codex/cli) executors that are sandboxed, browser-free, and CPU-capped — one isolated git worktree per plan, with your main agent reviewing each diff like a tech lead.

```
you           →  /improve-codex               (capable model: audits, then reviews)
plans/        →  001-fix-n-plus-one.md        (self-contained specs, via improve)
codex exec    →  one guarded worktree per plan (cheap executor, implements + commits)
review        →  APPROVE / REVISE / BLOCK      (done criteria re-run, scope checked, diff read)
```

The division of labor: your expensive model does the parts where intelligence compounds — understanding the codebase, writing the spec, judging the result. Codex does the typing. Nothing lands on your branch without a review, and nothing gets merged at all: approved work waits on its worktree branch for you.

## Install

```bash
npx skills add igorvaryvoda/improve-codex
```

Prerequisites:

- The [improve](https://github.com/shadcn/improve) skill. If it's missing, the skill will tell your agent to install it:
  ```bash
  npx skills add https://github.com/shadcn/improve --skill improve
  ```
- The [Codex CLI](https://developers.openai.com/codex/cli) (`codex`), installed and authenticated.

## Usage

```
/improve-codex                    full audit → plans → codex implements → review
/improve-codex deep security      args pass through to improve verbatim
/improve-codex execute            skip the audit; run existing TODO plans from plans/README.md
/improve-codex execute 012 014    run specific plans only
/improve-codex ... low effort     hints map to CODEX_MODEL / CODEX_EFFORT for the executors
```

## Why the guardrails exist

`codex exec` inherits your full `~/.codex` config — including browser plugins (`browser@openai-bundled`, `chrome@openai-bundled`, `browser-use`) and any browser-backed MCP servers you have configured. A fleet of executors that can each spawn Chrome, start dev servers, or run E2E suites is how a background "code fix" melts a workstation. The bundled runner strips all of it, in layers:

| Layer | Mechanism | What it stops |
|---|---|---|
| Config | `-c 'mcp_servers={}'` + `-c 'plugins={}'` | Browser/chrome plugins and browser-backed MCP servers never load (verified: codex then reports no browser-control tools); no npx-spawned MCP processes per run |
| Sandbox | `-s workspace-write` | Writes confined to the worktree |
| Prompt | RESOURCE RULES block | No playwright/puppeteer/headless browsers, no `playwright install`, no dev servers, no storybook, no watch mode, no E2E; focused test runs only |
| Scheduling | `nice -n 10`, ≤2 concurrent executors, `timeout` (default 1h) | Whatever still runs stays deprioritized, bounded, and can't hang forever |

Note that `--ignore-user-config` does **not** disable codex plugins — the two `-c` overrides are what actually remove the browser tooling.

Browser-dependent verification isn't lost, just moved: executors skip it, flag it in their report NOTES, and it becomes review-time work for the main agent or for you, on your terms.

## How it works

1. **Dispatch improve** — the improve skill runs its full workflow (recon, audit, your finding selection) and writes self-contained plans to `plans/`.
2. **Select and order** — plans execute in index order, honoring the dependency graph in `plans/README.md`.
3. **Execute** — per plan: a fresh worktree branched off the current HEAD, `node_modules` hardlink-cloned from the main tree when possible, then `scripts/run-codex-plan.sh` inlines the plan into a guarded `codex exec` prompt. The executor implements, verifies each step, and commits in its worktree. At most two executors run at once.
4. **Review** — the main agent re-runs every done criterion itself, checks scope with `git diff --stat`, reads the full diff, and audits new tests. Verdicts: APPROVE (branch kept for you), REVISE (feedback file, same worktree, max 2 rounds), BLOCK (plan refined with what was learned). Merging is always your decision — the skill never merges, pushes, or commits to your branch.

## The runner

`skills/improve-codex/scripts/run-codex-plan.sh <plan-file> <worktree> <report-out> [feedback-file]`

Environment overrides: `CODEX_MODEL` (default: your config's model), `CODEX_EFFORT` (default `medium` — plans are fully specified, execution rarely needs more), `CODEX_NICE` (default 10), `CODEX_TIMEOUT` (default 3600s — a run that hits it usually means a non-exiting command slipped through; investigate rather than raising it).

## License

MIT
