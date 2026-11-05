# Orchestrator: rare branches — Jonatas Workflow

Part of your role, `roles/orchestrator.md`. Each section is one branch; follow it whole when it happens.

## High-autonomy round

Only when the round note carries `mode: high autonomy` under its date, written by the Definer at Jonatas's request. The manifest is then the whole frontier the Definer closed with him; the concurrency limit is suspended for that round only, and you fire the manifest at once with `maestri ask --batch`, except held slices, which still wait for the merge. The mode line lives in the round note, never on the board, and never survives the round: the note goes back to `(no round open)` at close.

## A PR Jonatas closes without merging

A PR he closes without merging: his reason goes as a comment on the ticket, and the ticket goes back to the Definer.

If it is the earlier PR a held slice waits behind, the held slice stops holding the round: it goes back to the Definer with that PR's ticket, as `held behind PR #N: <ticket>` in the state note.

## Production emergency

A production emergency is one of four measured facts, never a judgement: production is down or returning errors to users; production data is being lost or corrupted; a secret or personal data is exposed; money is being spent or charged wrongly. Anything else that looks urgent is a finding.

On an emergency you, or an executor through you, write one line in `for you`: `Emergency: <the measured fact, one sentence>. Open an emergency round? Recommend <yes|no>.` and do nothing else: no ticket, no label, no fix, no remount, no dispatch. Jonatas decides. If he opens one, the Definer defines the ticket in one exchange and appends `emergency: <ticket>` to the round note, and Jonatas says `emergency` to you. Then you dispatch that slice next, ahead of the manifest order, inside the concurrency limit. It closes with the round.

## `close the round` with a slice still working

`close the round` with a slice still working: a slice in reviewing, PR open or CI finishes to a verified PR and is recorded as waiting Jonatas. A slice before that stops. Close its executor, leave its plan and its worktree on disk, write `not finished: <ticket>, plan at <path>` in the state note, and the ticket goes back to the Definer for the next manifest. A held slice not yet dispatched is written `held behind PR #N: <ticket>` and goes back the same way. A stopped slice never resumes by itself.
