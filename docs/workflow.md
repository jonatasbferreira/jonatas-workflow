# How the Jonatas Workflow runs

Written on 2026-09-08, the night the workflow was assembled. Read this before opening the canvas.

## In one sentence

Define before dispatching: you and the Definer close the business rule and the decisions in batches and write the manifest of the next round, one cluster of connected tickets in order; the Orchestrator runs only that manifest through disposable executors and stops at verified PRs; you merge every one of them; nobody assumes, everybody asks and waits.

## The canvas

One workspace for Shema, called **Shema**, rooted at `~/code/shema`. In it:

- **Definidor** (the Definer) — the terminal you talk to, and the front door. Everything you want enters here: ideas, defects, small asks with no open decision, tickets other people opened that you want worked, and the order of the next round; the findings the last round left it reads itself. It defines, and it writes the manifest with you. Opus, effort `high`: `claude --model opus --effort high`.
- **Orquestrador** (the Orchestrator) — the terminal that runs the round: only the tickets on the manifest, in that order. From you it hears "go", "close the round", "emergency", and your answers to the lines it wrote in `for you`. Opus, effort `high`: `claude --model opus --effort high`. Needs **Maestro Mode on** to recruit executors: toggle it on the terminal the first time.
- Five standing notes with fixed names: **round** (the manifest; outside a round its body reads `(no round open)`), **board** (a first line linking the round's hand-test guide, then one line per slice of the open round, in manifest order: `<codename> · <ticket> · <state> · <model> · <points>`, points being the ticket's estimate (the Linear estimate, or the GitHub `estimate:N` label), `?` when it has none; emptied at round close), **for you** (only what is still pending on you), **findings** (what showed up outside the slice and outside the code the round changed, one line each), and **how it works** (the short version of this file). The **logs** stack holds `log · <codename>`, `state · <date>` and `definition · <date>`; you almost never open it. `bin/setup-canvas`, run in the Orchestrator terminal with Maestro Mode on, creates and wires the five notes and schedules the routines; a missing standing note is fixed by rerunning it, never by creating it by hand.
- Three routines: **morning state** daily at 08:30, **evening round check** daily at 18:30, **for you reminder** on weekdays at noon. They read the round note and the latest state note, report on the board, clean `for you` of what you already ticked or answered, and push you the reminder; the morning state also dispatches a held slice whose earlier PR has merged, and the evening check also closes the round, but only when every manifest item is merged or waiting Jonatas and no slice is held. A routine never opens a round and never closes one by the clock.

The old workspaces are in the **Arquivo** folder inside the Shema YWAM group, intact, with their terminals and notes. Delete them whenever you like; the notes are exported in `jonatas-workflow/archive/notes/`. The **teste** workspace in "Arquivo (apagar)" was the mould and can be deleted. **Quick Sermon** was not touched.

## A round, in short

You bring everything to the Definer, which grills, defines and writes the manifest with you in the `round` note. You `/clear` the Orchestrator and say "go"; it publishes the round's hand-test guide, the `Testes na mão` page, and runs only that manifest, through executors, to verified PRs, each with João's review answered and its section in the guide: what the ticket proposes, how to bring the environment up, and the steps with what you must see. You answer `for you`, test each PR from its section and merge every PR. The round closes with a `state · <date>` note; then a new manifest, `/clear` and "go" again. The notes are the memory; the session is not.

Your side of it, step by step, is the `how it works` note. The rules live in the role files, which are the source of truth: `roles/definer.md`, `roles/orchestrator.md`, `roles/executor.md`, and their rare branches in `roles/definer-rare-cases.md` and `roles/orchestrator-rare-cases.md`.

## Mid-round asks and emergencies

Anything new mid-round goes to the Definer and waits for the next manifest; the Orchestrator answers it with one line: take it to the Definer. A production emergency is one of four measured facts, and reaches you as one `Emergency:` line in `for you` with a recommendation; you decide. The rules: `how it works` and the emergency sections of the rare-cases files.

## High-autonomy round

Only when you ask the Definer, never the default: it closes everything you brought, and the Orchestrator fires the whole manifest at once, the concurrency limit suspended for that round, except held slices, which still wait for the merge. The rules: the rare-cases files.

## Models

The Definer and the Orchestrator on Opus, both with effort `high`; executors on the cheapest model the ticket allows, effort starting low. The routing table is in `roles/orchestrator.md`, the reasons in `docs/adr/`.

## Where everything lives

- `~/code/jonatas-workflow` — this repository: skillset, roles, scripts, templates. Forked from `henokteixeira/batuta`, kept as the `upstream` remote.
- `~/.claude/CLAUDE.md` — a link to `jonatas-workflow/skillset/AGENTS.md`, made by `bin/install`. `~/.claude/skills/*` and `~/.claude/agents/*` are links too, except the Maestri skills, which the app installs.
- Roles in Maestri (`Definidor`, `Orquestrador`, `Executor`) — only pointers to `jonatas-workflow/roles/*.md`. Edit the file, not the preset.
- Linear, team Engineering — labels `ready-for-agent` and `ready-for-human`; only the Definer ever applies `ready-for-agent`, and every ticket it labels, with either label, is assigned to you. Tickets other people open there enter the flow only when you bring them to the Definer; nothing in Linear is listed, audited or dispatched because it is sitting there.

## Notification

The Claude Code Notification hook in `~/.claude/settings.json` points to `jonatas-workflow/bin/notify-maestri.sh`, a `notify-send` script: inside Maestri, clicking the notification raises the Maestri window; outside it, it is a plain desktop notification.

## After editing the workflow

- `skillset/AGENTS.md`, a skill or a subagent: nothing to run, they are links. A new skill or subagent needs one `bin/install`.
- A role file in `jonatas-workflow/roles/`: type `/clear` in that terminal. The preset re-reads the file at the next session.
- `templates/hand-test.html`: nothing to run; the Orchestrator reads it when the next round opens.
- A note template or a routine prompt: rerun `bin/setup-canvas` in the Orchestrator terminal. It recreates any missing standing note, refreshes `how it works` from its template and refreshes the routine prompts; `board`, `for you`, `findings` and `round` hold live content and are never overwritten, so a change to their templates reaches only a new workspace.

## Git identity

Never override the git author: the global config is `jonatas <jonatas.brito.ferreira@gmail.com>`, and `gh` is logged in as `jonatasbferreira`, so `--assignee @me` on GitHub and assignee `me` on Linear are you.
