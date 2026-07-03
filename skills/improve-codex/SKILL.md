---
name: improve-codex
description: Audit a codebase with the improve skill, then implement the resulting plans with OpenAI Codex (`codex exec`) running as sandboxed, browser-free, CPU-capped executors in isolated git worktrees — with Claude reviewing every diff like a tech lead. Use when the user wants audit-and-implement in one flow, says "improve and implement", "run improve then codex", "have codex execute the plans", "implement plans/NNN with codex", or wants existing plans/ executed by codex instead of Claude subagents.
---

# Improve → Codex

Compose two roles: the **improve skill** (senior advisor — audits, writes
self-contained plans under `plans/`) and **`codex exec`** (cheap executor —
implements one plan per isolated worktree). You are the advisor and the
reviewer. Codex writes the code; you dispatch and judge it.

Requires the `improve` skill and the `codex` CLI. If the improve skill isn't
installed (look for `improve/SKILL.md` under `~/.claude/skills/` or the
project's `.claude/skills/`), install it before Phase 1:

```bash
npx skills add https://github.com/shadcn/improve --skill improve
```

If the `codex` CLI is missing, stop and say so — installing and
authenticating it is the user's call.

## Invocation Forms

- Bare / with improve args (`deep`, `quick security`, …) → full workflow.
  Args pass through verbatim to the improve skill.
- `execute` or "run the existing plans" → skip Phase 1; execute the TODO
  plans already in `plans/README.md`.
- Specific plans (`execute 012 014`) → skip Phase 1; execute only those.
- Model/effort hints ("with gpt-5.4-mini", "low effort") → set `CODEX_MODEL`
  / `CODEX_EFFORT` for the runner script.

## Workflow

### Phase 1 — Dispatch the improve skill

Invoke the `improve` skill via the Skill tool, passing the user's focus and
effort args through. Let it run its full workflow — recon, audit, the user's
finding selection, plan writing. Don't shortcut its interaction points; the
selection step is where the user controls how much codex work gets queued.

When it finishes, the contract you inherit is: `plans/NNN-<slug>.md` files
plus `plans/README.md` with execution order, dependencies, and a status
column. That index drives everything below.

### Phase 2 — Select and order

Read `plans/README.md`. Execution set = plans written this session (or the
ones the user named), in index order, honoring dependencies: a plan runs only
after everything in its "Depends on" row is DONE. Announce the set, the
concurrency, and the executor model before dispatching — this is the user's
last cheap moment to trim scope.

### Phase 3 — Execute with codex

Per plan, from the main tree:

1. **Worktree** (explicit base — never rely on tooling defaults for the base
   branch):
   ```bash
   git worktree add -b improve/<NNN>-<slug> <repo-parent>/<repo>-codex-<NNN> HEAD
   ```
2. **Dependencies**: a fresh worktree has no `node_modules`/build artifacts.
   Cheapest path is a hardlink clone from the main tree
   (`cp -al <main>/node_modules <worktree>/node_modules`); fall back to the
   plan's install command if the layout doesn't support it. Doing this
   yourself saves the executor a full install per worktree.
3. **Run** the bundled runner (background Bash, one call per plan):
   ```bash
   <this-skill-dir>/scripts/run-codex-plan.sh <plan-file> <worktree> <scratch>/NNN-report.md
   ```
   The script inlines the plan into the prompt from the main tree (uncommitted
   plans are fine), prepends the executor preamble + resource rules, and runs
   codex with the guard flags in the Hard Rules table. The executor's report
   lands in the given output file. Run the script bare — piping its output
   (`| tail`, `| grep`) masks the timeout exit code (124) and swallows the
   stream; monitor progress with `git -C <worktree> status` instead.
4. Mark the plan IN PROGRESS in `plans/README.md` (you maintain the index —
   executors are told not to).

### Phase 4 — Review and verdict

Review each finished run like a tech lead. The full procedure and verdict
table live in the improve skill's reference — read
`references/closing-the-loop.md` inside the installed improve skill's
directory, sections "Review" and "Verdict", before the first review. Running
verification commands inside the worktree is fine — it's disposable; the
main tree is not.

Then harden the review adversarially: if the host environment has an
adversarial review skill (in this repo: `sirv-adversarial-review`; elsewhere,
any available skill whose description covers adversarial or branch review),
load it and run it read-only against the executor's worktree branch — review
target is the executor's commits, base is the dispatch HEAD. Executors
optimize for "plan satisfied"; the adversarial pass attacks what that misses:
needless abstraction, second sources of truth, weak failure paths, tests that
mock the thing they claim to prove. Its confirmed findings become REVISE
feedback verbatim, weighted like a failed done criterion. If no such skill is
available, your tech-lead pass stands alone.

- **APPROVE** → index row DONE; keep the worktree/branch for the user.
- **REVISE** → write specific feedback to a file, re-run the runner script
  with it as the 4th argument (same worktree — the executor builds on its
  previous attempt). Max 2 revision rounds, then BLOCK.
- **BLOCK** → index row BLOCKED with reason; refine the plan with what was
  learned.

A codex run that exits nonzero, times out, or produces no report file is a
failed run, not a verdict — inspect the worktree diff before deciding
whether anything is salvageable.

## Hard Rules

- **Never edit source code yourself in this flow** — codex is the executor;
  you dispatch and review. Plan files and `plans/README.md` are yours.
- **Never merge, push, or commit to the user's branch.** Approved work stays
  on its worktree branch; integration is the user's decision. Offer
  `git worktree remove` cleanup only after the user has integrated.
- **At most 2 codex instances at once** (each spawns a full node/tool chain;
  the point of this skill is not to melt the machine). Raise to 3–4 only if
  the user asks. Dependent plans wait for their dependency's APPROVE.
- **Keep every guard layer if you modify the runner script.** The executor
  must never do heavy CPU work outside the plan — above all, never launch
  browsers. Enforcement is layered:

| Layer | Mechanism | What it stops |
|---|---|---|
| Config | `-c 'mcp_servers={}'` + `-c 'plugins={}'` | Browser/chrome plugins and browser-backed MCP servers never load (verified: codex then has no browser-control tools); no npx-spawned MCP processes per run |
| Sandbox | `-s workspace-write` | Writes confined to the worktree |
| Prompt | RESOURCE RULES block | No playwright/puppeteer/agent-browser, no `playwright install`, no dev servers/storybook/watch mode, no E2E, focused test runs only |
| Scheduling | `nice -n 10`, ≤2 concurrent, `timeout` (default 1h) | Whatever still runs stays deprioritized, bounded, and can't hang forever |

Browser-dependent verification is deliberately excluded from codex's job: the
executor skips it and flags it in NOTES; it becomes review-time work for you
or the user, on their terms.

## Verification

Before rendering a verdict on any codex run, all of these — done yourself in
the worktree, never trusted from the executor's report:

- [ ] Every done criterion in the plan re-run and passing
- [ ] `git -C <worktree> diff --stat` shows only in-scope files (any file
      outside scope fails review, full stop)
- [ ] Full diff read and judged against the plan's "Why this matters" and
      the repo conventions it names
- [ ] New tests read — they assert real behavior, not trivially-green stubs
- [ ] Executor NOTES checked for skipped browser verifications and
      undocumented deviations (documented deviations are judged on merit)
- [ ] Adversarial review skill run against the worktree branch when one is
      available in the environment; confirmed findings folded into the verdict

Close out with a summary per plan: verdict, diff stat, branch, worktree path,
and anything notable from NOTES.
