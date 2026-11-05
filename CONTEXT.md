# Jonatas Workflow

Jonatas Workflow is Jonatas's workflow for agents on a Maestri canvas: how work is defined, batched into a round, dispatched, and merged. These are its words; the roles, the templates, the plans, the tickets and the commits use no others. Linear's own state names (Todo, In Progress, In Review, Done) stay as Linear writes them.

## Language

### The round

**Round**:
One batch of work. It opens when Jonatas says "go" over a written manifest and closes when every item on that manifest is merged or waiting Jonatas and no slice is held, or when Jonatas says "close the round".
_Avoid_: sprint, cycle, iteration, milestone

**Manifest**:
The ordered list of tickets a round runs: one cluster, in the order Jonatas gives, or the whole frontier in a high-autonomy round. The Definer writes it with Jonatas before "go".
_Avoid_: queue, plan, to-do list

**Cluster**:
Tickets connected by `blockedBy` edges or touching the same area or app, run as one manifest. Its size follows the connections, never a fixed number.
_Avoid_: bundle, epic, the three tickets

**Manifest item**:
One line of the manifest: a leaf ticket, or a parent whose unblocked children are its slices. A parent counts as one item.
_Avoid_: entry, task, story

**Slice**:
What one executor runs: one plan, one worktree, one PR.
_Avoid_: task, job, unit of work

**In flight**:
The state of a slice from dispatch until it is verified green or waiting Jonatas.
_Avoid_: running, active, in progress, WIP

**Waiting Jonatas**:
The state of an item whose next step is Jonatas's. A line for it exists in "for you", and its slot is free.
_Avoid_: blocked, blocked on Jonatas, stuck

**Held slice**:
A slice whose code paths share a source file with an earlier slice of the round. It is planned and dispatched only after the earlier slice's PR is merged; until then it is neither in flight nor waiting Jonatas, and it keeps the round open.
_Avoid_: blocked slice, queued slice, stacked slice

**Follow-up slice**:
A new slice on a ticket whose PR is already merged, dispatched in the same round to fix a defect in that PR's code. It is the same manifest item, not new work.
_Avoid_: hotfix, fix ticket, patch PR

**Concurrency limit**:
At most three slices in flight at once; four only when the fourth belongs to a ticket that already has a slice in flight.
_Avoid_: WIP limit, parallelism cap

**High-autonomy round**:
A round Jonatas asks for, whose manifest is the whole frontier the Definer closed with him, dispatched at once. The concurrency limit is suspended for that round alone.
_Avoid_: autonomous mode, yolo mode, full autonomy

**Emergency round**:
The emergency slice Jonatas opens for one production emergency: its ticket is appended to the round note, dispatched ahead of the manifest order inside the concurrency limit, and closes with the round it joined; with no round open it is a one-item manifest.
_Avoid_: hotfix round, incident, firefight

### The notes

**Round note**:
The standing note named "round" that holds the manifest of the open round. Outside a round its body reads "(no round open)".
_Avoid_: manifest note, dated round note, the round file

**State note**:
The "state · <date>" note written in the logs stack when a round closes: what merged, what waits Jonatas, what is blocked and why, what was measured, what did not finish, the manifest itself, and a short retro: what to keep and what to change in the workflow.
_Avoid_: handoff, report, summary

**Logs stack**:
The stack of notes that holds "log · <codename>", "state · <date>" and "definition · <date>". Measurements, history and status live there and nowhere else.
_Avoid_: archive, journal, history note

**Board**:
The standing note with one line per slice of the open round, in manifest order, under a first line that links the hand-test guide. It is emptied at round close.
_Avoid_: kanban, dashboard, status board

**For you**:
The standing note holding only what is still pending on Jonatas, one `- [ ]` checkbox per item. Jonatas ticks a line he did or answers it with `R: …`; the agent that wrote it records that on the ticket and deletes the line. No agent ever ticks a line for him.
_Avoid_: inbox, to-do, blockers, action items

**Findings**:
The standing note where each finding is one line. It only grows during a round, every line is marked at round close, and the Definer empties it with Jonatas after.
_Avoid_: issues note, bug list, parking lot

**How it works**:
The standing note that carries the rules of the workflow on the canvas, so the canvas explains itself.
_Avoid_: readme note, instructions, cheatsheet

**Review and merge line**:
The line in "for you" that hands Jonatas a verified, green PR: "Review and merge PR #N — <ticket> (unblocks: …) · testar: <guide section>"; the Definer's glossary PR writes "glossary" in place of the ticket and links no section. Jonatas answers it by merging, or with "R: changes: <what>", which re-dispatches the slice from its plan.
_Avoid_: approval, review request, merge task

**Define: line**:
The line in "for you" that sends a manifest ticket back to the Definer, naming what is missing. The ticket is skipped and resumes in the same round once the Definer has labelled it, or goes to the next manifest if the round closed first.
_Avoid_: blocker note, clarification, question

**Test by hand**:
The block that closes a slice plan and that the PR body carries: what Jonatas does to see the change working and what he must see, or why there is nothing to test by hand. It seeds the PR's section in the hand-test guide.
_Avoid_: manual test, QA, smoke test, Look line

**Hand-test guide**:
The artifact the Orchestrator publishes when a round opens, "Testes na mão · rodada <dd/mm>", linked from the board's first line: one section per PR that reached a Review and merge line, in the order to test and merge, each with what the ticket proposes, the commands that bring the environment up and which server it talks to, and the checkable steps with what Jonatas must see.
_Avoid_: test plan, QA script, testing doc, the artifact

### People and terminals

**Definer**:
The terminal Jonatas talks to. It defines, publishes tickets, applies the ready-for-agent label, and writes the manifest with him. Definidor on the canvas.
_Avoid_: planner, product manager, spec writer

**Front door**:
The Definer's standing as the single entry for everything Jonatas brings. Nothing enters the flow any other way.
_Avoid_: intake, triage, entry point

**Orchestrator**:
The terminal that runs the round: it dispatches the manifest in order, verifies what comes back, and never edits a repository; reverting a slice's change for a moment to watch its tests fail is verifying, not editing. Orquestrador on the canvas.
_Avoid_: manager, dispatcher, lead, queue runner

**Executor**:
The agent that runs one slice, from plan to PR, and dies with the PR.
_Avoid_: worker, implementer, dev agent

**Question round**:
One frontier of grilling questions, each with its recommended answer first: at most four to a call, the rest in the calls that follow.
_Avoid_: round (that is the batch of work), interview, Q&A session

**João's review**:
The review the bot posts on a PR in the shemaobt organisation once João is requested as reviewer, read thread by thread.
_Avoid_: bot review, Joãozinho, reviewer comments

**Cockpit**:
The read-only list of every running agent terminal in Maestri, across all workspaces, with the plan limits on top, in two views of the same data: the terminal list and the local page. It shows; it never acts on an agent.
_Avoid_: dashboard, monitor, control panel

### Work items

**Small ask**:
Something Jonatas wants that carries no open decision. The Definer closes it in one exchange, without a grilling session, and it waits for the next manifest.
_Avoid_: quick fix, tiny task, drive-by

**Finding**:
Something an agent noticed that belongs neither to the slice it is on nor to code this round changed: one line in the findings note until the round closes, never a ticket, a label, a plan change or a dispatch before that. A defect on a code path the slice's plan enumerates is the slice's to fix, and a defect in code the round changed goes back to the round; neither is a finding.
_Avoid_: issue, bug report, side quest, TODO

**Invariant**:
A rule about an interface that must hold after every event, including a kill, a lost response and a retry. Every ticket names its invariants, Jonatas decides them, and each one is a test in the acceptance criterion.
_Avoid_: constraint, assumption, edge case

**Async lifetime**:
A code path whose result depends on when things happen: a retry, a timer, a kill half-way, two callers at once. A ticket that touches one routes to opus, and an instruction that changes one gets its own attack pass.
_Avoid_: concurrency path, race, timing issue

**Origin**:
The PR that introduced a defect, traced in git, or "gap" when the behaviour was never handled. Never taken from what a ticket or a report says.
_Avoid_: root cause, culprit, pre-existing

**Hot file**:
A source file two or more of a round's defects trace to. The state note names it, and the Definer recommends a refactor of the hottest.
_Avoid_: hotspot, problem file, god file

**Backlog**:
Every ticket in Linear that nobody brought to the Definer. It is never listed, audited or dispatched.
_Avoid_: queue, pool, the rest of the tickets

**Production emergency**:
One of four measured facts, never a judgement: production is down or returning errors to users; production data is being lost or corrupted; a secret or personal data is exposed; money is being spent or charged wrongly.
_Avoid_: urgent, critical, incident, P0
