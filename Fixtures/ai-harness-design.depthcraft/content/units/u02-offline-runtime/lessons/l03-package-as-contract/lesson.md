# The package as a contract

## Online writes, offline reads

Generation happens on the ground with BYOK. The flight experience only reads a versioned `*.depthcraft` folder: manifest, curriculum, progress, markdown lessons, quizzes, meta anchors.

## Schema version matters

`schemaVersion: 0.1.0` is part of the contract. Readers reject unknown majors; writers never silently half-upgrade a package mid-flight.

## Anchors without chat

`meta.json` stubs heading anchors now so v0.2 primers can attach offline explanations without rewriting `lesson.md` or calling a model in airplane mode.
