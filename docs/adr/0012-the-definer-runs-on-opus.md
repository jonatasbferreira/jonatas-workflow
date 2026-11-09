# The Definer runs on Opus

2026-11-09

The Definer moves from Fable 5.1 to Opus 5.5, still at effort `high`, so both terminals now start with `claude --model opus --effort high`. ADR 0007 kept the Definer on Fable because its work is judgement no benchmark measures and a wrong definition spreads to every ticket of a round, and it put off both terminals on Opus until rounds with the Orchestrator on Opus showed it held up. Jonatas judged, from the rounds run with the Orchestrator on Opus, that Opus is good enough for the Definer's judgement as well. This reverses ADR 0007 on the Definer; its decision for the Orchestrator stands.
