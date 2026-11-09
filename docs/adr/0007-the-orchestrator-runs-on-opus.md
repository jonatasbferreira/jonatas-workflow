# The Orchestrator runs on Opus

2026-09-23

The Orchestrator moves from Fable 5.1 to Opus 5.5, both at effort `high`; the Definer stays on Fable. Anthropic's launch of Opus 5.5 puts it ahead of Fable 5.1 on agentic coding and terminal work (Terminal-Bench 4.0 66.4% against 55.8%, CursorBench 4.0 57.8% against 51.8%) and at a lower price, while saying that in its own use the gap is narrower than the scores suggest. The Orchestrator's work is long, agentic and tool-heavy, the kind those benchmarks measure, and it was the second-largest spend of the workflow (3.6M output tokens on Fable from 09-08 to 09-23); a slip there is still caught by verification and by Jonatas's merge. The Definer's work is judgement no benchmark measures, its spend is the smallest, and a wrong definition spreads to every ticket of a round, so it keeps the stronger model.

Considered options: both on Opus, rejected until rounds with the Orchestrator on Opus show no more rework (`R: changes`, failed verifications) than on Fable; both on Fable, rejected because it pays Fable's price for work Opus does as well.

Superseded on the Definer by ADR 0012: the Definer runs on Opus too.
