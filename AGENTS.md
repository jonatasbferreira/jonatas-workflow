# jonatas-workflow

Jonatas Workflow is Jonatas's project-agnostic workflow for agents on a Maestri canvas: the skillset, the terminal roles, the note templates and the setup script.

No package manager: Markdown and bash.

Tests: `bash test/setup-canvas-test.sh`.

Roles in `roles/`, note and preset templates in `templates/`, the glossary in `CONTEXT.md`, the decisions in `docs/adr/`, the workflow in `docs/workflow.md`. Use the glossary's words in code, notes, tickets and commits.

Edits to skills, roles and `AGENTS.md` follow the `writing-for-agents` skill: load it before the first edit.

Everything here is in English; only the Maestri terminal names (Definidor, Orquestrador) stay as they are.

Changes to the workflow go through this repository, then out through the rollout steps in `docs/workflow.md`. Never edit the workflow in the Maestri app or in `~/.claude` directly.
