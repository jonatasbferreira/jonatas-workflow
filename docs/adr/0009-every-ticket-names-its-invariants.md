# Every ticket names its invariants

2026-09-28

A ticket is defined only when it names the interface it touches and its invariants, decided with Jonatas, each invariant a test in the acceptance criterion. Small asks included: for them it is part of the one exchange. Jonatas owns the interfaces and the invariants; the agents own the implementation. About 40% of September's bug tickets were state and lifecycle defects in one module that nobody owned as a model, and each fix added another flag. Definition sessions get longer.

Considered options: invariants only for items that touch a state lifecycle, a contract between app and server or a module's interface, and invariants only for items with a spec, both rejected by Jonatas in favour of every ticket.
