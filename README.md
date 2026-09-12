# Depthcraft

**Free, open-source, BYOK course generation and study runtime.**

Depthcraft generates structured courses from topics using your LLM keys, then delivers them through a rich iPad study experience that works completely offline. No accounts, no custom cloud—just your keys, your device, and deep learning.

---

## What it does

**Generate** → Input a topic and knowledge/depth level. Depthcraft orchestrates your chosen LLM through planning, lesson writing, quiz creation, and interactive demo generation. Review and approve the curriculum before generation. Extend existing courses with new units while preserving your progress.

**Study** → Navigate a typographically refined course home with progress tracking and unit/lesson structure. Read rendered lessons, complete multiple-choice and cloze quizzes with immediate explanations, and interact with sandboxed Three.js demos that run inline. Everything works airplane-mode after import.

**Own** → Courses live as versioned `.depthcraft` package folders. Progress is device-local and survives re-imports. No lock-in, no telemetry, no required backend.

---

## Shipped features

### Generation
- **Two-speed controls**: Knowledge (New → Expert) and Depth (Brief → Exhaustive) sliders tune content for your background and learning goals
- **Curriculum approval**: Review, edit, and selectively approve units before generation; exclude expensive lessons for cost control
- **Multi-provider support**: Anthropic, OpenAI, OpenRouter, or custom OpenAI-compatible endpoints; configure per-role (planner, lesson writer, quiz writer, demo writer)
- **Extend & refresh**: Append new units to existing courses while preserving completed progress (opt-in with version tracking and collision detection)

### Reader (iPad)
- **Course home**: Typographic cover with progress overview, resume button, and unit list with circular progress indicators
- **Lesson player**: Clean study typography in WKWebView with dynamic height sections and smooth scroll behavior
- **Native quizzes**: Multiple-choice and cloze (fill-in-the-blank) questions with immediate grading and explanation feedback
- **Interactive demos**: Sandboxed Three.js demos that render inline at exact lesson positions; soft-fail to markdown fallback on errors; kit-injected from app bundle (demos don't vendor libraries)
- **Offline-first**: Zero network required for study path; packages bundle all content and assets
- **Progress tracking**: Device-local completion state keyed by `packageId`; read intent + quiz pass = lesson complete

---

## Repository layout

| Path | Contents |
|------|----------|
| `apps/DepthcraftReader/` | SwiftUI iPad app (iOS 17+) with generation UI and offline reader |
| `schema/0.1.0/` | JSON schemas and package contract documentation |
| `Fixtures/ai-harness-design.depthcraft/` | Example course (AI harness design, bundled with app) |
| `docs/engineering/` | Implementation notes and dogfood analysis |
| `CLAUDE.md` | Builder agent handoff (for AI pair programming workflows) |

---

## Build & run

**Requirements:**
- macOS with Xcode 15+ (iOS 17 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

**Steps:**
```bash
cd apps/DepthcraftReader
xcodegen generate
open DepthcraftReader.xcodeproj
```

In Xcode, select the **DepthcraftReader** scheme, choose an **iPad simulator** (or iPad device), and Run (⌘R).

The app bundles `Fixtures/ai-harness-design.depthcraft` as an offline demo. To generate your own courses, add LLM API keys in Settings.

---

## Package format (`0.1.0`)

Depthcraft courses are folders with the `.depthcraft` extension (zip for transfer):

```
course.depthcraft/
  manifest.json          # Package metadata, title, topic, version, IDs
  curriculum.json        # Units, lessons, approval status
  progress.json          # Template only in distributed packages
  content/units/<unitId>/unit.md
  content/units/<unitId>/lessons/<lessonId>/lesson.md
  content/units/<unitId>/lessons/<lessonId>/quiz.json
  content/units/<unitId>/lessons/<lessonId>/meta.json
  content/units/<unitId>/lessons/<lessonId>/demos/<demoId>/
    demo.json            # Demo manifest with kit dependency
    index.html           # Entry point
    fallback.md          # Soft-fail content
  assets/                # Optional media
```

**Progress ownership:** Runtime progress is **device-local** (UserDefaults, keyed by `packageId`). Re-importing a package never clobbers existing completions; the `progress.json` file in distributed packages is a schema fixture only.

**Versioning:** Packages support append-only extension with `contentVersion` (integer) and `extendedFrom` tracking. New units/lessons merge with preserved progress for finished lessons.

See [`schema/0.1.0/README.md`](schema/0.1.0/README.md) for full contract details.

---

## Scope boundaries

**In scope now:**
- iPad-first reader (iPhone support possible but not optimized)
- BYOK generation with approval workflow
- Offline study with MC/cloze quizzes and sandboxed demos
- Extend/refresh for versioned packages
- Device-local progress

**Later / not required for current release:**
- Primers (pre-lesson concept checks)
- Tap-to-explain on lesson terms
- iCloud progress sync
- Standalone Mac app
- App Store distribution (TestFlight/sideload available; public release TBD)

---

## Contributing

Depthcraft is early-stage open source. We welcome issues, feature requests, and PRs. For significant changes, please open an issue first to discuss scope and approach.

**Development notes:**
- Engineering scratch notes: [`docs/engineering/`](docs/engineering/)
- Package schema: [`schema/0.1.0/README.md`](schema/0.1.0/README.md)
- Agent handoff: [`CLAUDE.md`](CLAUDE.md)

---

## License

Licensing is under review. This codebase is open for inspection and experimentation; formal license terms will be published soon. Check back or open an issue if you have licensing questions.
