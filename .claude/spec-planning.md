# Spec Planning (Claude Code)

Claude Code writes OpenSpec changes, checks them with the user, reviews the
PRs the OpenCode orchestrator opens, and archives finished changes. It does
not write firmware code; the OpenCode agents in [.opencode/agents/](../.opencode/agents/) do.

## How to Work

- Decide, don't narrate. If two options are both reasonable, take the simpler
  one, mark it `(planner decision)` in `design.md`, and move on.
- If only the user can answer (hardware, scope, priorities), add it to the
  change's `design.md` under Open Questions and carry on with everything it
  doesn't block.
- Keep replies to the user short unless they ask for more.
- Delegate large reads (datasheets, web pages, wide searches, full logs) to a
  sub-agent and keep only its answer.

## 1. Idea → Change

1. Explore with `/openspec-explore` when the scope is unclear. Check what
   already exists with `openspec list --specs` and
   `openspec show <spec> --type spec`.
2. Create the change with `/openspec-propose` (it writes `proposal.md`,
   delta `specs/`, `design.md` and `tasks.md`). `openspec/config.yaml`
   injects the project's rules into each artifact; follow them, in
   particular:
   - `design.md` is binding for the OpenCode agents: exact signatures,
     constants, payload layouts, file paths and test names. They run on small
     local models and must never have to infer one.
   - One task = one `developer` run (at most 40 steps): one module or
     concern, about 5 files at most, with its own tests, leaving
     `tools/check.sh` passing.
   - HIL checks are plain bullets under `## HIL checks (user)`, never tasks.
   - Mark a task `[reasoning]` when it needs the `reasoner` instead of the
     local `planner`.
3. Run `openspec validate <change> --strict` and fix everything it reports.
4. Ask the user to approve the change, and **stop** until they do.

## 2. Hand Off to the Orchestrator

1. In Orca, create a worktree for the change (branch named after it, e.g.
   `add-uart-link`).
2. Start OpenCode there with `tools/opencode.sh` (default agent:
   `orchestrator`) and the prompt `Apply OpenSpec change <change-id>.`
3. The orchestrator plans, implements, reviews and commits each task, runs
   the whole-change audit and reviews, pushes the branch and opens a PR. It
   stops early only for the reasons in `openspec/config.yaml`
   (`operations.apply.guidance`), marking the Orca board "needs you".

Don't start a change until the changes it depends on are archived.

## 3. Review the PR

When the PR is open (or the orchestrator stopped):

1. `openspec status --change <change>`: every task is ticked.
2. `tools/diff.sh origin/main...<branch>` and per-file diffs: the code
   follows `design.md` and `AGENTS.md`; unexpected files are explained.
3. `tools/check.sh all --all-files` ends with `VERIFY PASS`.
4. Send fixes back as a new orchestrator prompt in the same worktree, or
   approve.

## 4. Archive

After the user has merged the PR and confirmed the `## HIL checks (user)`
list on the rover:

1. On `main`: `/openspec-archive-change <change>`. It merges the delta specs
   into `openspec/specs/` and moves the change to
   `openspec/changes/archive/`.
2. Update the change's row in [docs/roadmap.md](../docs/roadmap.md).
3. Commit only if the user asks.
