# Depthcraft

Free/OSS/BYOK offline course runtime — **iPad reader first**. Packages are versioned `*.depthcraft` folders (zip for transfer). Generation happens on the ground with the user's keys; airplane-mode study only reads the local package.

## Repo layout
| Path | Purpose |
|------|---------|
| `schema/0.1.0/` | JSON Schemas + package contract notes |
| `Fixtures/ai-harness-design.depthcraft/` | Built example course (AI harness design) |
| `apps/DepthcraftReader/` | SwiftUI iPad reader (iOS 17+) |

## Package contract (`0.1.0`)
```
course.depthcraft/
  manifest.json
  curriculum.json
  progress.json          # template only in fixtures
  content/units/<unitId>/unit.md
  content/units/<unitId>/lessons/<lessonId>/lesson.md
  content/units/<unitId>/lessons/<lessonId>/quiz.json
  content/units/<unitId>/lessons/<lessonId>/meta.json
  assets/                # optional
```

Runtime progress is **device-local**, keyed by `packageId`. Regenerating or re-importing a course must not overwrite existing learner completions.

## iPad reader
```bash
cd apps/DepthcraftReader
brew install xcodegen   # once
xcodegen generate
open DepthcraftReader.xcodeproj
```
Run on an iPad simulator. See [`apps/DepthcraftReader/README.md`](apps/DepthcraftReader/README.md).

## Out of scope (v0.1 reader)
Primers UI, interactive demos, chat, accounts, iCloud sync, and the generation pipeline UI (BYOK settings are a stub).
