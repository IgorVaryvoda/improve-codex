---
name: improve-codex
description: Audit a codebase with improve, scrutinise plans with Sol, execute them through repo-local Symphony and Clanker Army when available or isolated Codex Terra worktrees otherwise, then run final adversarial review. Use when the user wants audit-and-implement in one flow, asks to run improve then Codex, or asks to implement existing plans with Codex.
---

# Improve to Codex

Compose four roles: the **improve skill** audits and writes self-contained
`plans/`; the current **Codex session** scrutinises, dispatches, and judges;
repo-local **Symphony and Clanker Army** own queued execution, worktree
isolation, and convergence when available; otherwise the bundled direct runner
owns one isolated worktree per plan. `codex exec` supplies the Terra
implementation and Sol criticism passes in either lane.

## Model roles

Defaults are the contract. Honor explicit user-requested environment overrides.

| Role | Model | Where |
| --- | --- | --- |
| Plan author, dispatcher, final judge | Current Codex session | improve, revisions, verdicts |
| Plan scrutineer | `gpt-5.6-sol`, high effort | Phase 2 critic, read-only |
| Executor | `gpt-5.6-terra` | Phase 4 Clanker worker or direct runner, workspace-write |
| Diff critic | `gpt-5.6-sol`, high effort | Phase 5 critic, read-only |

The plan author and final judge need independent attacks before execution and
against the final diff.

Requires the improve skill and the `codex` CLI. Repo-local Clanker/Symphony
commands are optional and select the preferred orchestration lane. Discover
and read `improve/SKILL.md` in this order: repo-owned
`.agents/skills/improve`, `.codex/skills/improve`, `.ai/skills/improve`, then
`~/.codex/skills/improve`, then `~/.agents/skills/improve`. If none exists,
stop and say so; installing it is the user's call. If the CLI is missing,
also stop and say so.

## Invocation forms

- Bare improve arguments run the full workflow.
- `execute` or named plans skip Phase 1 and run selected TODO plans.
- User model or effort requests set executor `CODEX_MODEL` / `CODEX_EFFORT`.
  Critic requests use `CODEX_CRITIC_MODEL` / `CODEX_CRITIC_EFFORT`; executor
  changes do not silently downgrade critics.

## Workflow

### Phase 1 — Dispatch improve

Load the discovered improve instruction file directly, pass through the
user's focus and effort, and preserve its recon, selection, and plan-writing
steps. Its output is self-contained `plans/NNN-<slug>.md` files and the
ordered `plans/README.md` index.

### Phase 2 — Scrutinize plans with Sol

Before execution, scrutinize each plan from the main tree:

```bash
<this-skill-dir>/scripts/run-codex-critic.sh plan <plan-file> <main-tree> <scratch>/NNN-scrutiny.md
```

Sol runs at high effort in a read-only sandbox. It attacks assumptions the
code contradicts, ambiguity, passable-but-insufficient done criteria, scope
errors, and missing failure paths. Judge its report: incorporate valid
findings into the plan, silently drop style noise, and record dismissed
substantive findings in a short scrutiny note.

Scrutiny is capped at two rounds per plan. A structural rewrite gets one more
scrutiny pass and no more. If the second round still returns `NEEDS REVISION`
on substantive grounds, the plan itself is the defect: split it or replace it
per "Reaching the review cap" below, rather than opening a third scrutiny loop
or handing the same plan to the user unchanged. Skip scrutiny only on an
explicit user request for speed over safety, and announce that skip before
dispatch.

### Phase 3 — Select and order

Read `plans/README.md`, select session or user-named plans in index order,
and honour dependencies. Every selected plan must declare concrete in-scope
paths, at least one bounded automation-safe validation command, a fully parsed
dependency list, and a planned-at commit. Revise a plan before compilation if
its dependency prose, scope, or validation is ambiguous. Announce the set,
execution lane, concurrency, integration or worker branches, worktrees, and
Terra executor model before dispatching.

### Phase 4 — Choose and run the execution lane

Prefer the Symphony/Clanker lane only when the target repository exposes all
of these contracts:

- a plan compiler command such as `improve-codex:clanker`;
- a Symphony command such as `codex:symphony`;
- a serialized improve profile such as `WORKFLOW.improve.md`;
- the compiler's documented target-branch and integration-base metadata.

Read the repo-owned workflow instructions before invoking those commands. If
any contract is absent, use the portable direct Terra lane. Never invent
equivalent package scripts or copy Studio-specific orchestration into another
repository.

#### Symphony and Clanker lane

Record the current base, create a linked integration worktree, and never run
plan-backed Symphony from the primary checkout. Use a sibling path outside the
repo. Freshly authored or scrutinised plans may be uncommitted in the primary
tree, so copy the selected plan files into the integration worktree before
compilation and stage them with the compiled artifact:

```bash
git rev-parse HEAD
git worktree add -b codex/improve-817-818-integration \
  <repo-parent>/<repo>-improve-817-818-integration <recorded-base-ref>

mkdir -p <integration-worktree>/plans
cp plans/817-example.md plans/818-dependent-example.md \
  <integration-worktree>/plans/

cd <integration-worktree>
npm run improve-codex:clanker -- \
  --plan plans/817-example.md \
  --plan plans/818-dependent-example.md \
  --output docs/plans/improve-817-818-clanker.md \
  --target-branch codex/improve-817-818-integration

git add plans/817-example.md plans/818-dependent-example.md \
  docs/plans/improve-817-818-clanker.md
git commit -m "docs(workflow): stage reviewed improve plans"

npm run codex:symphony -- \
  --workflow WORKFLOW.improve.md \
  --plan docs/plans/improve-817-818-clanker.md \
  --plan-tag improve-ready \
  --dry-run
```

Run the compiler and both Symphony commands from `<integration-worktree>`.
The compiler records that worktree's immutable HEAD as the integration base
and verifies completed dependency evidence against it. Inspect the dry run,
confirm `git status --porcelain` is empty, then repeat it with `--once` instead
of `--dry-run`. The compiled frontmatter is the target-branch source of truth;
Symphony rejects a conflicting CLI target, the wrong current branch, a primary
checkout, or a dirty integration worktree before launching. Plan-backed
dispatch blocks through Autopilot worker completion, convergence, the
post-convergence gate, and review before handing the configured tracker task
to review, when a tracker is configured.

The repo-owned improve profile should pin one tracker task and one Clanker
batch at a time, at most two Terra passes, medium reasoning effort, and the
Codex provider.
`CODEX_MODEL` and `CODEX_EFFORT` override only the executor. The compiler fails
closed on broad scope, partial dependency parsing, cycles, unsafe or dropped
validation, and missing target metadata. Use `--completed-plan <NNN>@<SHA>`
only when that landed commit is an ancestor of the integration base; the
compiler verifies and records the evidence.

Older improve plans may hard-code the direct runner's branch and worktree
names. Their exact branch/worktree setup instructions and STOP conditions that
only assert those obsolete names are superseded by Clanker's worker branch and
compiled integration target. Product constraints, code-drift checks, and every
other STOP condition still apply.

Mark selected plans IN PROGRESS in `plans/README.md`; workers never maintain
the improve index.
Monitor with Symphony, the repository's tracker, and the Clanker supervisor
surfaces. Do not launch Symphony, Clanker, or another orchestrator from inside
a worker.

#### Portable direct Terra lane

Use the bundled direct runner when the user explicitly requests it or the
repo-local Symphony/Clanker contract is incomplete. Independent plans may use
separate explicit-base worktrees, with at most two runners active. A plan with
selected dependencies must not start again from the original HEAD: either run
the connected dependency chain serially in one dedicated integration worktree,
or create its worktree from the approved dependency branch's HEAD. Record the
base ref for every review. For the serial integration-worktree form:

```bash
git worktree add -b improve/<first>-<last>-integration \
  <repo-parent>/<repo>-codex-<first>-<last> HEAD
git -C <worktree> rev-parse HEAD
<this-skill-dir>/scripts/run-codex-plan.sh \
  <first-plan-file> <worktree> <scratch>/<first>-report.md
# Review and APPROVE the dependency before dispatching the next plan.
git -C <worktree> rev-parse HEAD
<this-skill-dir>/scripts/run-codex-plan.sh \
  <dependent-plan-file> <worktree> <scratch>/<dependent>-report.md
```

Keep all runner guard layers. Terra remains the default unless `CODEX_MODEL`
overrides it, and a nonzero or reportless run remains a failed run. Never
dispatch a dependent plan until its dependency is approved and present in the
dependent plan's worktree history.

### Phase 5 — Review and verdict

Before review, read the discovered improve skill's `references/closing-the-loop.md`
sections "Review" and "Verdict". Re-run done criteria against the converged
integration branch or direct worker branch. Require
`git status --porcelain` to be empty before either adversarial pass: staged,
unstaged, or untracked implementation means REVISE, because the retained
branch must contain everything being approved. Then require two independent
adversarial passes. A Clanker worker review is useful execution evidence, but
it does not replace either close-out pass:

1. **Advisor pass.** Run an available adversarial review skill read-only
   against the execution branch and its recorded base ref. If absent, the
   current Codex session attacks the diff itself rather than rechecking plan.
2. **Sol pass.** Run:
   ```bash
   <this-skill-dir>/scripts/run-codex-critic.sh diff <base-ref> <execution-worktree> <scratch>/NNN-adversarial.md
   ```

Neither pass substitutes for the other. Confirm each finding against the
actual diff. Confirmed findings become verbatim REVISE feedback; record one
line of reasoning for every dismissed substantive finding.

- **APPROVE**: mark DONE and retain the integration worktree and branch.
- **REVISE**: write verbatim feedback and rerun the affected batch once.
- **BLOCK**: mark BLOCKED and refine the plan with what was learned.

A nonzero, timed-out, or reportless executor run is a failed run, not a
verdict. Inspect its diff before deciding whether it is salvageable. A failed
run does not consume a review round, because nothing was reviewed.

### Reaching the review cap — split or re-approach

Reachable from Phase 2 scrutiny and Phase 5 review alike. A review round is one
complete review of a plan: in Phase 5, done criteria plus both adversarial
passes; in Phase 2, one Sol scrutiny pass. **Two rounds per plan is the
ceiling** — the initial review, and one review of the revision. There is no
third round, so a second round that still finds major blockers never issues
REVISE again.

Major blockers are done criteria that will not pass, diffs that keep escaping
declared scope, a design the code contradicts, or the same finding surviving
its own fix. Cosmetic residue is not a blocker; take it as REVISE inside the
cap or as a follow-up plan.

When round two ends on major blockers, stop dispatching that plan. Retain its
branch and worktree as evidence when execution has already run, mark the plan
BLOCKED in `plans/README.md`, and treat the plan as the defect rather than the
executor. Then choose one:

1. **Split.** The approach holds but the plan is too large or too coupled for
   one executor pass. Carve it into smaller plans, each with its own concrete
   scope, done criteria, and bounded validation command, ordered by dependency.
   Any part that already verifies clean and stands alone stays APPROVE on its
   retained branch, unmerged as always; re-plan only the parts that blocked.
2. **Nuke and re-approach.** The blockers are the approach — the plan fights
   the codebase, its premises were wrong, or the diff proved the design
   unworkable. Retire the plan (BLOCKED, with the reason recorded) and author a
   replacement that takes a different route, informed by what the two rounds
   revealed. Discard the failed branch's implementation rather than salvaging
   it.

Prefer splitting when the blockers are localized; re-approach when they are
structural. Replacement plans re-enter the flow at Phase 2 with a fresh round
counter and Sol's own two-round scrutiny cap; they are new plans, not a third
round on the old one.

Announce the choice, the blockers that forced it, and the resulting plan set.
Escalate to the user instead of choosing only when the blockers need a decision
that is not yours to make — a product tradeoff, an external dependency, or a
constraint the plans cannot resolve. Record that as BLOCKED with the specific
question.

## Hard rules

- Never edit source code in this flow; executors implement while the current
  Codex session owns plans, dispatch, and review.
- Never merge, push, or commit to the user's branch. Approved work remains on
  the dedicated integration branch for a separate landing step.
- Two rounds per plan is a hard ceiling for both plan scrutiny and execution
  review. A plan still holding major blockers after round two is split or
  retired; it is never sent through a third round.
- In the orchestration lane, keep the repo-owned improve profile serialized.
  Dependencies wait for approval and no worker may recursively start agent
  orchestration.
- Keep every guard layer in both runners. No runner launches browsers, heavy
  unrelated work, dev servers, Storybook, watch mode, or E2E suites.

| Layer | Mechanism | Purpose |
| --- | --- | --- |
| Config | Empty MCP/plugins plus disabled browser, app, hook, computer, and multi-agent features | Remove extra tool and fan-out surfaces while preserving trusted provider, environment, and exec-policy configuration |
| Sandbox | `workspace-write` executor, `read-only` critic | Constrain writes |
| Prompt | Resource rules | Prohibit browser and long-running work |
| Scheduling | `nice -n 10`, timeout or gtimeout, max 2 | Bound and deprioritize work |

Both runners must fail closed with a clear diagnostic when neither `timeout`
nor `gtimeout` exists. Browser-dependent verification is excluded from an
executor's job and must be noted for later review.

The documented runner paths are executable entrypoints: invoke them directly
so an accidental loss of execute permission fails fast rather than being
masked by a shell wrapper.

## Verification

Before a verdict, independently verify:

- [ ] Every done criterion passes.
- [ ] `git -C <execution-worktree> status --porcelain` is empty, so all
      approved implementation is committed.
- [ ] `git -C <execution-worktree> diff --stat <base-ref>...HEAD` contains
      only in-scope paths.
- [ ] The full diff and new tests are judged against the plan and conventions.
- [ ] Executor notes, browser skips, and deviations are reviewed.
- [ ] Both adversarial passes run: advisor and Sol diff; confirmed findings
      affect the verdict and dismissed findings are reasoned in the summary.
- [ ] No plan is on a third review round; any plan that hit the cap with major
      blockers was split or retired rather than reviewed again.

Summarize verdict, review rounds used, diff stat, execution branch, worktree,
tracker state when present, and notable notes per plan. When a plan hit the
review cap, state whether it was split or retired, and name the successor
plans.
