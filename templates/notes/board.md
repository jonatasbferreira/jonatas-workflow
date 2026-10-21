# board

A first line `testes · <url>`, the round's hand-test guide, then one line per slice of the open round, in manifest order: `<codename> · <ticket> · <state> · <model>`. States: held behind PR #N, recon, grilling, implementing, reviewing, PR open, CI, verified, waiting Jonatas, merged. The concurrency limit: at most three slices in flight, a fourth only when it belongs to a ticket already in flight. The Orchestrator edits by substring and empties the board at round close; history goes to the `state ·` note, the manifest is in the `round` note.

(no slice in flight)
