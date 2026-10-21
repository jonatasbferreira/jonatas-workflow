# Reviews try to break the change

2026-09-30

Every gate asked whether the code does what the spec asked, so a case the spec never mentioned passed all of them, and the executor's own report was the only evidence its tests could fail. Two gates now try to break what they pass. The review has a third axis, attack, which looks for the input, sequence or state that produces a wrong result, with a lens per high-risk class; the concurrency lens names the room's bug family: a kill half-way, a lost response, a late event. The Orchestrator falsifies the tests itself, reverting the slice's change in the worktree and watching every new test go red. The Testing Plan is written as numbered cases, each a test whose name states it, so the acceptance criterion outlives the plan.

This comes from the unmerged branch `review-gaps` of 2026-09-16. Jonatas took these two groups and left out the silence pass before labelling, the thing to try that should fail in Test by hand, the case against on `Approve:` lines, and the `read the diff` clause.

Considered options: the reviewer delivering a failing test instead of prose, rejected for now because it costs a run per finding; mutation testing, left to the repositories under review.
