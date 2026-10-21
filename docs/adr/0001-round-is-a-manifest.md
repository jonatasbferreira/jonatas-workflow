# A round is a manifest

2026-09-08

Work used to reach the Orchestrator through the `ready-for-agent` label, so nobody could say what would run next or when a batch was over. A round is now one written manifest: at most three tickets, in order, in the standing `round` note, opened by Jonatas's "go" and closed when every item is merged or waiting Jonatas, with a state note and no dispatching after it. The Orchestrator dispatches nothing outside that note, so the batch has a start, an end and an author.

Considered options: a dated note per round, rejected because the Orchestrator can only wire notes it created; an evening routine that closes the round by the clock, rejected because a round ends when its manifest is done, not at 18:30.

2026-09-11: the one dispatch after the state note is the re-dispatch of a manifest item Jonatas answered with "R: changes:" on its Review and merge line. Its plan is on disk and it stays the round's item, so a code fix he asks for after close does not go back to the Definer.

2026-09-23: the three-ticket cap is gone. A manifest is one cluster: tickets connected by `blockedBy` edges or touching the same area or app, in the order Jonatas gives, as many as the connections hold. Five of the first twelve rounds already ran more than three, and Jonatas wants more parallelism among related tickets. The concurrency limit rises with it, to three slices in flight and a fourth only for a ticket that already has one.
