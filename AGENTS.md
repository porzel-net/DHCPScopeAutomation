# Clean Code Multi-Agent Setup

## Purpose

- Use multi-agent workflows to keep the main thread focused on requirements, decisions, and final output.
- Prefer parallel read-only work for exploration, architecture, review, and verification.
- Use exactly one writing agent for production code changes unless the task is explicitly split into disjoint files.

## Default Orchestration

1. `explorer` maps the affected code paths, data flow, and ownership boundaries.
2. `architect` turns the findings into a minimal change plan with clear acceptance criteria.
3. `implementer` owns the code changes and follows the agreed seam.
4. `reviewer` checks correctness, regressions, edge cases, and missing tests.
5. `test_guard` validates only the changed behavior and reports any failing command with the exact command and outcome.

## Clean Code Rules

- Optimize for small, composable changes over broad refactors.
- Preserve module boundaries; do not mix domain logic, I/O, and UI glue in one place.
- Prefer explicit names and narrow interfaces over clever abstractions.
- Remove dead branches and duplicated logic near the touched code when it is safe and local.
- Add or update tests for behavior changes before closing the task.
- If architecture is unclear, stop implementation and ask `architect` to resolve the boundary first.

## Multi-Agent Safety

- Parallel agents should be read-only by default.
- Only `implementer` may edit source files unless the parent task explicitly assigns disjoint write scopes.
- If multiple writing agents are ever used, each must own a disjoint file set and must not rewrite the other agent's work.
- Sub-agents return summaries, not raw logs, unless the parent explicitly asks for evidence.

## Done When

- The change is minimal, readable, and locally coherent.
- Tests or validation commands for the changed behavior have been run or a concrete blocker is reported.
- `reviewer` has checked the final patch for correctness and maintainability risks.
