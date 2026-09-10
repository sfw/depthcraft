# Fail-closed BYOK and role boundaries

## Keys stay on device

BYOK means Anthropic, OpenAI, or OpenRouter keys never leave the user’s device to a Depthcraft backend — there isn’t one. Missing or rejected keys stop the role.

## Fail closed

If quiz writer fails mid-unit, do not ship a package with empty `quiz.json` marked built. Leave the lesson `draft`, surface the error, let the user retry that role.

## Boundaries

Planner must not write lesson bodies. Packager must not invent curriculum. Thin wrappers are fine in v0.1; muddy ownership is not.
