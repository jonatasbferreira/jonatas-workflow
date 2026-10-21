# round

The manifest of the open round, written by the Definer with Jonatas before "go": a first line `round · <date>`, then the tickets of one cluster in the order they run, one per line, `1. ENG-905 (leaf)`, `2. ENG-894 (parent, 4 leaves)`. A cluster is tickets connected by `blockedBy` edges or touching the same area or app; its size follows those connections, not a fixed number. A parent counts as one item; its unblocked children are its slices. The Orchestrator dispatches nothing outside it. A high-autonomy round lists the whole frontier and says `mode: high autonomy` under the date. An emergency is appended as `emergency: <ticket>`. Closed rounds live in the `state ·` notes.

(no round open)
