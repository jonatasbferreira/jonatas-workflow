# jonatas-workflow

Jonatas's workflow for agents inside Maestri: the skillset, the terminal roles, the scripts and the templates. It is project-agnostic. Adapted for Linux from Henok's `batuta` (github.com/henokteixeira/batuta, kept as the `upstream` remote), without Nori.

## Layout

- `skillset/` — what `bin/install` links into `~/.claude`: `AGENTS.md` becomes the global `CLAUDE.md`, `skills/` go to `~/.claude/skills/` (the Maestri ones excepted: the app installs its own) and `subagents/` go to `~/.claude/agents/`.
- `roles/` — the three Maestri roles. The preset in the app is only a pointer; the truth lives here.
  - `definer.md` — the front door. Everything Jonatas brings enters here, and the findings the last round left it reads itself: ideas, defects, small asks with no open decision, tickets other people opened that he wants worked, and the order of the next round. Grills, writes glossary and ADRs, publishes specs and defined tickets to Linear, applies `ready-for-agent` (only the Definer ever applies it), and writes the manifest in the `round` note with Jonatas, in the order Jonatas gives. Never chooses the order itself, never starts a round.
  - `orchestrator.md` — runs one round: the tickets on the manifest, in that order, and nothing else. Writes the slice plan, recruits executors, verifies against spec and tests, watching the tests fail itself and trying to break the change. Inside the concurrency limit: at most three slices in flight, four only when the fourth belongs to a ticket that already has one. From Jonatas it hears only "go", "close the round", "emergency", and his answers to the lines it wrote in `for you`; anything else gets one line back: take it to the Definer. Never edits a repository.
  - `executor.md` — one plan, one worktree, TDD with manual falsification, a PR for Jonatas to merge. Closed once its PR is verified green.
- `bin/` — scripts:
  - `install` — links `skillset/` into `~/.claude` and adds the Notification hook to `~/.claude/settings.json`. Idempotent; rerun after adding a skill.
  - `setup-canvas` — creates and wires the five standing notes and installs the routines. Rerun it in the Orchestrator terminal after any change to a routine prompt or to the `how it works` template: it recreates what is missing and refreshes those; the other notes hold live content and are never overwritten.
  - `cockpit` — the Cockpit: a read-only list of every running agent terminal in Maestri, all workspaces, with the plan limits on top; refreshes every 5 seconds, `--once` prints once, `--json` prints one snapshot, `--serve [port]` shows the same data on a local page at `http://127.0.0.1:4317`, with the Round panel on top; while it serves, `--refresh-rounds` keeps a local cache of what comes from GitHub through `gh`, every two minutes, outside the 5-second refresh. `cockpit-statusline` is the Claude Code status line that records the Claude limits it reads; `CLAUDE_HOME=<dir> cockpit-install` adds it to that account's `settings.json`, once per account (`~/.claude`, `~/.claude-rea`, `~/.claude-personal`).
  - `notify-maestri.sh` — Claude Code Notification hook for Linux (`notify-send`): inside Maestri, clicking the notification raises the Maestri window.
- `templates/` — initial content of the canvas notes and the preset text.
- `docs/workflow.md` — how a round runs, from the manifest to Jonatas's merge and the state note.
- `docs/adr/` — the decisions that shaped the workflow. Read them before changing a role.
- `CONTEXT.md` — the glossary of the workflow itself: round, manifest, cluster, slice, finding, concurrency limit.
- `test/` — `bash test/setup-canvas-test.sh`, `bash test/cockpit-test.sh` (needs Google Chrome).
- `archive/notes/` — the notes from the old workspaces, exported on 2026-09-08, to be mined for ADRs and glossary entries.

## How the work splits

Definition before dispatch, one round at a time. Jonatas brings everything to the Definer: ideas, defects, small asks with no open decision, tickets other people opened that he wants worked, and the order of the next round. The Definer defines, publishes the tickets, applies `ready-for-agent` (nobody else ever does), and writes the manifest with Jonatas: one cluster of connected tickets, in the order Jonatas gives. It never chooses the order itself and never starts a round. Nothing else enters the flow, and nobody audits a backlog.

With the manifest in the `round` note, Jonatas says "go" to the Orchestrator, which dispatches only those tickets, in that order, inside the concurrency limit: at most three slices in flight, four only when the fourth belongs to a ticket that already has one. It writes plans whose Testing Plan is untouchable and recruits executors with a model and effort chosen per ticket. The executor grills only implementation decisions, waits instead of assuming, and delivers a PR assigned to Jonatas, with evidence and a Test by hand block. Verification is against the spec, not only against the tests: the Orchestrator watches the tests fail with the change reverted, a review axis tries to break the change, and the Orchestrator answers every thread of João's review, posts its own review on the PR and adds the PR's section to the round's hand-test guide. Jonatas tests by hand from that section and merges every PR himself. What turns up along the way is a finding: one line in the `findings` note, never a ticket, a label, a plan change or a dispatch in the round it appeared, however urgent. The exception is a production emergency, one of four measured facts: one "Emergency:" line in `for you`, and Jonatas decides whether to open an emergency round. The round closes with the `state · <date>` note, and after it the Orchestrator dispatches nothing until Jonatas types `/clear`.

Details in `docs/workflow.md` and in the roles.

## Installing on a new machine

```
git clone <this repository> ~/code/jonatas-workflow
~/code/jonatas-workflow/bin/install
```

`bin/install` links the global `CLAUDE.md`, the skills and the subagents into `~/.claude` and points the Notification hook at `bin/notify-maestri.sh`. Then, in Maestri, create the three roles with the text in `templates/presets.md`. With the roles in place, run `bin/setup-canvas` in the Orchestrator terminal, with Maestro Mode on: it creates and wires the five standing notes and installs the routines.

## Creating a workspace

1. In Maestri, create the workspace rooted at the project's folder (for Shema: `~/code/shema`).
2. Create two terminals: **Definidor** with the Definidor preset, started with `claude --model opus --effort high`, and **Orquestrador** with the Orquestrador preset, started with `claude --model opus --effort high`. Toggle Maestro Mode on the Orquestrador. Connect the two.
3. In the Orquestrador terminal run `~/code/jonatas-workflow/bin/setup-canvas`. It creates the notes `round`, `board`, `for you`, `findings` and `how it works`, wires them to the Definidor, and schedules the three routines.
4. Executors are recruited by the Orquestrador itself, with the Executor preset. You never create them by hand.
