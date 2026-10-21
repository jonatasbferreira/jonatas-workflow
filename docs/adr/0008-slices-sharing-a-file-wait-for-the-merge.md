# Slices sharing a file wait for the merge

2026-09-28

Two slices whose code paths share a source file run in series: the later one is planned and dispatched only after the earlier one's PR is merged, from the updated main, and its plan tests the transitions between the two. This holds in a high-autonomy round too, and a held slice keeps the round open until it has run, so the evening check does not close the round over it. In the round of ENG-1112, six stacked slices of one 4,700-line session notifier ran in high autonomy and merged within about two hours; each was right on its own paths, and seven of the thirteen bugs of the next round came from the transitions between them. Held slices cost throughput, since each waits on Jonatas's merge.

Considered options: dispatching the later slice once the earlier one is verified green, stacked on its branch, rejected because that is how ENG-1112 left the transitions without an owner.
