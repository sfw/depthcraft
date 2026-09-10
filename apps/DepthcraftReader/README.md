# Depthcraft Reader (iPad)

Offline SwiftUI course player for Depthcraft packages (`schemaVersion` 0.1.0). Bundles the `Fixtures/ai-harness-design.depthcraft` example and stores progress on-device keyed by `packageId`.

## Requirements
- macOS with Xcode 15+ (iOS 17 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Open & run
```bash
cd apps/DepthcraftReader
xcodegen generate
open DepthcraftReader.xcodeproj
```
In Xcode:
1. Select the **DepthcraftReader** scheme
2. Choose an **iPad** simulator (or device)
3. Run (⌘R)

No network is required for the study path. Airplane mode is supported.

## What you get
- **Course home** — title, topic, unit list with progress, Resume
- **Unit view** — ordered lessons with estimated time + completion
- **Lesson** — WKWebView study typography (not a file browser)
- **Quiz** — native MC + cloze, explain after grade (casefold + trim for cloze)
- **Progress** — UserDefaults keyed by `packageId`; package `progress.json` is never authoritative after first open; re-import does not clobber completions
- **Settings** — BYOK stub only (generation out of scope for v0.1)

## Layout
```
apps/DepthcraftReader/
  project.yml          # XcodeGen → DepthcraftReader.xcodeproj
  Sources/             # SwiftUI app
  README.md
```

The Xcode project copies `../../Fixtures/ai-harness-design.depthcraft` into the app bundle as a folder resource.
