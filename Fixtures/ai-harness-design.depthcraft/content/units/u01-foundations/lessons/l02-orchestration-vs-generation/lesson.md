# Orchestration vs generation

## Split the work

**Generation** fills lesson markdown and quiz items. **Orchestration** sequences roles (planner → lesson → quiz → packager), passes only approved inputs, and stops on schema failure.

## Why discrete roles

One mega-prompt hides failure modes. Discrete roles make it obvious whether the map, the prose, or the quiz broke — and let you swap providers per role (BYOK).

## Approve before generate

Humans edit the curriculum tree, then approve once. Optional `generateUnitIds` limits cost; it is not a second approve bureaucracy.
