# Depthcraft Reader (iPad)

SwiftUI course generation and study app for iPad. Generates Depthcraft packages using your LLM keys, then provides a rich offline reading experience with native quizzes and interactive demos.

---

## Requirements

- **macOS** with Xcode 15+ (iOS 17 SDK)
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)**: `brew install xcodegen`
- **iPad simulator or device** (iPad-first; iPhone not optimized)

---

## Build & run

```bash
cd apps/DepthcraftReader
xcodegen generate
open DepthcraftReader.xcodeproj
```

In Xcode:
1. Select the **DepthcraftReader** scheme
2. Choose an **iPad** simulator or device
3. Run (⌘R)

The app launches with the bundled `Fixtures/ai-harness-design.depthcraft` example course. No network required for the study path—airplane mode supported.

---

## Features

### Generation UI
- **Two-speed controls**: Knowledge (New → Expert) × Depth (Brief → Exhaustive) tune content density and prerequisite assumptions
- **Curriculum approval**: Review draft units and lessons, edit titles, selectively approve for cost control
- **Multi-role orchestration**: Separate LLM configs for planner, lesson writer, quiz writer, demo writer (Anthropic, OpenAI, OpenRouter, custom endpoints)
- **Extend & refresh**: Add new units to existing courses while preserving device-local progress; append-only with version tracking
- **Credential management**: API keys stored in Keychain, never bundled in packages

### Study UI
- **Course home**: Typographic cover with title, topic, course progress bar, resume button, and unit list with circular progress indicators and lesson counts
- **Unit view**: Ordered lessons with estimated time and completion checkmarks
- **Lesson player**: Rendered markdown in WKWebView with study typography (proper measure, scale, margins); dynamic height sections for text + embedded demos
- **Native quizzes**: Multiple-choice (tap to select) and cloze (fill-in-the-blank with Unicode casefold + trim grading); immediate feedback with explanation after submit
- **Interactive demos**: Sandboxed Three.js demos render inline at exact `:::demo id="...":::` directive positions in lesson markdown; soft-fail to fallback.md on errors; Reset/Next controls (Next is v0 placeholder)
- **Progress tracking**: Read intent (scroll threshold) + quiz pass = lesson complete; unit complete when all lessons done; progress stored in UserDefaults keyed by `packageId`
- **Package management**: Switch between imported packages, open from Files, extend existing courses

### Demo system
- **Sandboxed WebView**: `loadFileURL` with directory-scoped file access; all http/https blocked via content rules and navigation policies; ES module support for Three.js
- **Kit injection**: Demos import `kit:three-v0/three.module.min.js` from app bundle (no per-package vendoring); custom URL scheme handler with per-demo allowlist
- **Soft-fail**: JavaScript errors, blank content, or missing files trigger fallback to rendered markdown explanation
- **Inline placement**: Demos appear at exact positions in lesson spine (HTML split at placeholders), not appended to end

---

## Project structure

```
apps/DepthcraftReader/
  project.yml              # XcodeGen project definition
  Sources/
    DepthcraftReaderApp.swift
    Models/                # Package models, generation config, navigation
    Views/                 # SwiftUI views (course home, generation, lesson player, quiz, demos)
    Services/              # PackageLoader, generation orchestrator, LLM client, markdown rendering
  Resources/
    demo-kits/three-v0/    # Bundled Three.js v0.170.0 for kit injection
  ../../Fixtures/ai-harness-design.depthcraft/  # Copied into app bundle as folder resource
```

XcodeGen generates `DepthcraftReader.xcodeproj` from `project.yml`. The fixture package is copied as a folder resource (preserves structure for `PackageLoader` discovery).

---

## Settings & BYOK

The app includes a Settings tab with API key management for supported providers (Anthropic, OpenAI, OpenRouter, custom endpoints). Keys are stored in Keychain. No keys = generation unavailable, but you can still study imported packages offline.

To generate courses:
1. Open Settings tab
2. Add API key(s) for your chosen provider(s)
3. Navigate to Course Home → "Generate New Course" or "Extend this Course"
4. Configure topic, locale, Knowledge/Depth, and per-role LLM settings
5. Review and approve curriculum
6. Wait for generation (progress rail shows current phase)
7. Package loads automatically when complete

---

## Architecture notes

### Package loading
`PackageLoader` reads `.depthcraft` folders from app bundle or Documents directory. Validates `manifest.json` and `curriculum.json` schemas, loads units/lessons/quizzes on-demand. Demo manifests and directories resolved lazily.

### Progress ownership
`ProgressStore` (UserDefaults-backed) is the **single source of truth** for user progress. Package `progress.json` files are schema fixtures only. On first open, an empty progress structure is created; on extend/refresh, existing progress merges with new curriculum.

### Generation flow
1. `GenerationOrchestrator` drives `PlannerService` → draft `Curriculum` → approval UI
2. On approval, orchestrator sequences `LessonWriterService`, `QuizWriterService`, `DemoWriterService` in parallel across lessons (retry/resume on role failure)
3. `PackagerService` validates, writes `manifest.json`, copies assets, initializes empty `progress.json` template
4. `CourseStore` loads completed package and navigates to course home

### Demo rendering
`MarkdownHTML.render()` extracts `:::demo id="...":::` directives and returns `LessonRenderResult` (HTML + `[DemoReference]`). `LessonContentView` splits HTML at `<div class="demo-placeholder">` markers and alternates `InlineHTMLSection` (measured WKWebView) with `DemoHostView` (sandboxed demo + Reset/Next controls) in a single ScrollView.

---

## Testing notes

**Offline test:** Enable Airplane Mode on simulator, navigate units/lessons/quizzes/demos → should work fully.

**Sandbox test:** The `sandbox-test` demo (removed from production fixture, available in git history) attempts external CDN fetches, XHR, and script loads—all should be blocked, while local `./demo.json` fetch succeeds.

**Soft-fail test:** Corrupt a demo's `index.html` or remove `demo.json` → fallback.md should render as HTML in-frame after 2-second detection.

**Extend test:** Generate a course, mark lessons complete, tap "Extend this Course" with same topic → new units should merge without clobbering finished lesson progress.

---

## Known limitations

- **iPad-first**: iPhone layout exists but is not polished for production
- **Single kit**: Only Three.js v0.170.0 bundled (`three-v0`); extending to chart.js, d3, etc. requires additional kit bundles
- **No demo state persistence**: Reset clears all state; no step navigation API yet (Next button is placeholder)
- **No background generation**: Generation runs in-app; backgrounding pauses until foregrounded
- **No telemetry**: Soft-fail is silent; no analytics on demo/WebGL failures

---

## Next steps

See root [`README.md`](../../README.md) for repository overview and [`schema/0.1.0/README.md`](../../schema/0.1.0/README.md) for package contract details.

Engineering implementation notes (interactive demos, kit injection, sandbox, dogfood analysis) are in [`docs/engineering/`](../../docs/engineering/).
