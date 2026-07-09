---
name: improve-codex
description: Audit a codebase with the improve skill, then implement the resulting plans with OpenAI Codex (`codex exec`) running as sandboxed, browser-free, CPU-capped executors in isolated git worktrees — with Claude reviewing every diff like a tech lead. Use when the user wants audit-and-implement in one flow, says "improve and implement", "run improve then codex", "have codex execute the plans", "implement plans/NNN with codex", or wants existing plans/ executed by codex instead of Claude subagents.
---

# Improve → Codex

Compose two roles: the **improve skill** (senior advisor — audits, writes
self-contained plans under `plans/`) and **`codex exec`** (cheap executor —
implements one plan per isolated worktree). You are the advisor and the
reviewer. Codex writes the code; you dispatch and judge it.

## Model roles

Each stage runs on the model whose strengths it needs. Overrides via env vars
are fine when the user asks; the defaults are the contract:

| Role | Model | Where |
|---|---|---|
| Plan author, dispatcher, final judge | You (Claude Fable) | improve skill, plan revisions, all verdicts |
| Plan scrutineer | `gpt-5.6-sol`, high effort | Phase 2, `run-codex-critic.sh plan`, read-only |
| Executor | `gpt-5.6-terra` | Phase 4, `run-codex-plan.sh` default `CODEX_MODEL` |
| Adversarial reviewers | Fable **and** `gpt-5.6-sol` high | Phase 5, two independent passes, both required |

The point of the split: the plan is authored and judged by one mind (yours),
but attacked twice by a different model family — once before execution while
fixing it is cheap, once after against the real diff.

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
  / `CODEX_EFFORT` for the executor runner. Critic passes have their own
  knobs (`CODEX_CRITIC_MODEL` / `CODEX_CRITIC_EFFORT`, default
  `gpt-5.6-sol` / `high`) — an executor downgrade does not downgrade the
  critics unless the user says so.

## Workflow

### Phase 1 — Dispatch the improve skill

Invoke the `improve` skill via the Skill tool, passing the user's focus and
effort args through. Let it run its full workflow — recon, audit, the user's
finding selection, plan writing. Don't shortcut its interaction points; the
selection step is where the user controls how much codex work gets queued.

When it finishes, the contract you inherit is: `plans/NNN-<slug>.md` files
plus `plans/README.md` with execution order, dependencies, and a status
column. That index drives everything below. The plans are yours — authored
by you (Fable) via the improve skill — which is exactly why they need a
hostile read from a different model before anything executes them.

### Phase 2 — Scrutinize plans with sol

Before any plan reaches an executor, run it past the critic. Per plan, from
the main tree (read-only — safe to run against the user's tree):

```bash
<this-skill-dir>/scripts/run-codex-critic.sh plan <plan-file> <main-tree> <scratch>/NNN-scrutiny.md
```

The critic is `gpt-5.6-sol` at high effort with the same browser/MCP guards
as the executor, in a read-only sandbox. It attacks the plan the way a
skeptical staff engineer would: assumptions the actual code contradicts,
ambiguity a literal-minded executor could implement two ways, done criteria
that can pass while the goal fails, scope errors, missing failure paths.

You judge its report — you are the plan's author and its critiques are input,
not orders. Fold in what survives your judgment by editing the plan file,
drop style noise silently, and record dismissed *substantive* points in the
plan (a short "Scrutiny notes" line is enough) so they're visible at review
time. A plan whose structural issues forced a real rewrite goes through
scrutiny once more; two NEEDS REVISION verdicts on the same plan means the
finding list goes to the user before dispatch, not a third loop.

Skip this phase only if the user explicitly asks for speed over safety;
say so in the dispatch announcement when you do.

### Phase 3 — Select and order

Read `plans/README.md`. Execution set = plans written this session (or the
ones the user named), in index order, honoring dependencies: a plan runs only
after everything in its "Depends on" row is DONE. Announce the set, the
concurrency, and the executor model before dispatching — this is the user's
last cheap moment to trim scope.

### Phase 4 — Execute with codex

Per plan, from the main tree:

1. **Worktree** (explicit base — never rely on tooling defaults for the base
   branch):
   ```bash
   git worktree add -b improve/<NNN>-<slug> <repo-parent>/<repo>-codex-<NNN> HEAD
   ```
   Record `git rev-parse HEAD` now — it's the `<base-ref>` for Phase 5's
   sol diff review.
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
   codex with the guard flags in the Hard Rules table. The executor model is
   `gpt-5.6-terra` unless `CODEX_MODEL` overrides it. The executor's report
   lands in the given output file. Run the script bare — piping its output
   (`| tail`, `| grep`) masks the timeout exit code (124) and swallows the
   stream; monitor progress with `git -C <worktree> status` instead.
4. Mark the plan IN PROGRESS in `plans/README.md` (you maintain the index —
   executors are told not to).

### Phase 5 — Review and verdict

Review each finished run like a tech lead. The full procedure and verdict
table live in the improve skill's reference — read
`references/closing-the-loop.md` inside the installed improve skill's
directory, sections "Review" and "Verdict", before the first review. Running
verification commands inside the worktree is fine — it's disposable; the
main tree is not.

Then harden the review with two independent adversarial passes — both run,
neither substitutes for the other:

1. **Fable pass (you).** If the host environment has an adversarial review
   skill (in this repo: `sirv-adversarial-review`; elsewhere, any available
   skill whose description covers adversarial or branch review), load it and
   run it read-only against the executor's worktree branch — review target is
   the executor's commits, base is the dispatch HEAD. If no such skill
   exists, do the adversarial pass yourself: attack the diff, don't re-check
   the plan.
2. **Sol pass.** Run the critic against the same branch:
   ```bash
   <this-skill-dir>/scripts/run-codex-critic.sh diff <base-ref> <worktree> <scratch>/NNN-adversarial.md
   ```
   `<base-ref>` is the commit the worktree was branched from (record it at
   worktree creation). This is `gpt-5.6-sol` at high effort, read-only.

Executors optimize for "plan satisfied"; both passes attack what that misses:
needless abstraction, second sources of truth, weak failure paths, tests that
mock the thing they claim to prove. You arbitrate: a finding confirmed by
either pass (verified by you against the actual diff) becomes REVISE feedback
verbatim, weighted like a failed done criterion. A finding both passes raise
independently is near-certainly real. Discard nothing silently — dismissed
findings get one line of reasoning in your review summary.

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
- **At most 2 codex instances at once** — executors and critics both count
  (each spawns a full node/tool chain; the point of this skill is not to melt
  the machine). Raise to 3–4 only if the user asks. Dependent plans wait for
  their dependency's APPROVE.
- **Keep every guard layer if you modify either runner script.** No codex
  run — executor or critic — may do heavy CPU work outside its job; above
  all, never launch browsers. Enforcement is layered:

| Layer | Mechanism | What it stops |
|---|---|---|
| Config | `-c 'mcp_servers={}'` + `-c 'plugins={}'` | Browser/chrome plugins and browser-backed MCP servers never load (verified: codex then has no browser-control tools); no npx-spawned MCP processes per run |
| Sandbox | `-s workspace-write` (executor) / `-s read-only` (critics) | Executor writes confined to the worktree; critics can't write at all |
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
- [ ] Both adversarial passes run against the worktree branch — yours
      (adversarial skill or your own attack on the diff) and sol's
      (`run-codex-critic.sh diff`); every confirmed finding folded into the
      verdict, every dismissed one reasoned about in the summary

Close out with a summary per plan: verdict, diff stat, branch, worktree path,
and anything notable from NOTES.
