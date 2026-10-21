# Jonatas merges every PR

2026-09-08

No agent merges. A verified, green PR becomes a "Review and merge PR #N" line in "for you" and its item is waiting Jonatas; the Orchestrator learns of the merge from GitHub, never by asking Jonatas. The merge is the last point where a human sees the change, so it stays with him.

Considered options: an agent merging once it has verified the PR, rejected because a green PR is verified, not reviewed.

2026-09-11: the Orchestrator posts its verification as a review on the PR and the ticket goes In Review. That review is an agent's: it is what Jonatas reads before merging, and it does not replace him.

2026-09-30: the review opens with a one-line verdict and folds its evidence under `<details>`; the PR body carries no evidence (ADR 0010).
