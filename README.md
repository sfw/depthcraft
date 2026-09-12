# Depthcraft

**Free, open-source, BYOK course generation and offline study for iPad.**

Depthcraft generates structured courses from any topic using your own LLM keys, then delivers them through a refined study experience that works completely offline. No accounts, no backend, no lock-in—just your keys, your device, and focused learning.

Not mid-flight chat. Full courses—lessons, quizzes, interactive demos—that you generate on the ground and study airplane-mode.

---

## Who it's for

**Perpetual learners** who already use LLMs to generate markdown notes, dump them into Obsidian, and read on flights—but want structure, progress tracking, quizzes with grading, and interactive demos without stitching it all together yourself.

**Students and professionals** who need offline study materials for planes, trains, commutes, or anywhere connectivity is unreliable or distracting.

**Educators and course creators** who want to prototype curriculum, generate quiz banks, or produce structured packages with full content control.

**BYOK practitioners** who want both generation and runtime without vendor lock-in, usage tracking, or required cloud services.

---

## How you use it

1. **Add your API keys** — Open Settings, add credentials for Anthropic, OpenAI, OpenRouter, or a custom OpenAI-compatible endpoint. Keys stay in your device Keychain.

2. **Generate a course** — Tap Generate, enter a topic ("Rust async programming", "Renaissance art history", "category theory"). Tune Knowledge (your background: New → Expert) and Depth (thoroughness: Brief → Exhaustive). Depthcraft orchestrates LLM roles (planner, lesson writer, quiz writer, demo writer) to produce a structured curriculum. Review the draft—edit titles, exclude expensive units—then approve to run generation.

3. **Study offline** — Navigate a typographic course home with progress tracking. Read rendered lessons with clean study typography. Complete native multiple-choice and cloze quizzes with immediate grading and explanations. Interact with sandboxed Three.js demos that render inline at exact lesson positions. Everything works airplane-mode once the package is imported.

4. **Extend when ready** — Tap "Extend this Course" to add new units. Your completed lessons stay marked; new content merges in without clobbering progress. Packages are versioned with collision detection.

Courses live as versioned `.depthcraft` package folders. Progress is device-local. Export, share, or archive packages however you want.

---

## Features

### Course generation
- **Two-speed controls**: Knowledge (New → Expert) and Depth (Brief → Exhaustive) sliders tune content for your background and goals
- **Curriculum approval**: Review and edit the draft outline before spending tokens; exclude expensive units for cost control
- **Multi-provider support**: Configure different LLMs per role (planner, lesson writer, quiz writer, demo writer)
- **Extend & refresh**: Append new units while preserving completed progress; version tracking prevents collisions

### Study experience
- **Course home**: Typographic cover with progress bar, resume button, unit list with circular indicators
- **Lesson player**: Clean study typography with proper measure and scale; smooth scroll behavior
- **Native quizzes**: Multiple-choice and cloze (fill-in-the-blank) with immediate grading and explanation feedback
- **Interactive demos**: Sandboxed Three.js demos render inline at exact lesson positions; soft-fail to markdown fallback on errors
- **Offline-first**: Zero network after import; packages bundle all content and assets
- **Progress tracking**: Device-local completion keyed by package ID; read intent + quiz pass = lesson complete

---

## Package model

Courses are folders with the `.depthcraft` extension (zip for transfer):

```
ai-harness-design.depthcraft/
  manifest.json          # Package metadata, version, IDs
  curriculum.json        # Units, lessons, approval status
  progress.json          # Template only (runtime progress is device-local)
  content/units/<unitId>/unit.md
  content/units/<unitId>/lessons/<lessonId>/lesson.md
  content/units/<unitId>/lessons/<lessonId>/quiz.json
  content/units/<unitId>/lessons/<lessonId>/meta.json
  content/units/<unitId>/lessons/<lessonId>/demos/<demoId>/
    demo.json
    index.html
    fallback.md
  assets/
```

**Progress ownership:** Runtime progress is stored on-device (UserDefaults, keyed by `packageId`). Re-importing a package never overwrites your completions. The `progress.json` file in distributed packages is a schema fixture only.

**Versioning:** Packages support append-only extension with `contentVersion` (integer) and `extendedFrom` tracking. New units merge with preserved progress.

See [`schema/0.1.0/README.md`](schema/0.1.0/README.md) for full contract details.

---

## Getting Depthcraft

**Current distribution:** Open-source build (field trial). Clone the repo and build with Xcode, or request a TestFlight invite (if available—check Issues for current trial status).

**App Store:** Not yet listed. Public release timeline TBD.

iPad-first (iOS 17+). iPhone works but isn't optimized.

---

## Repository layout

| Path | Contents |
|------|----------|
| `apps/DepthcraftReader/` | SwiftUI iPad app source |
| `schema/0.1.0/` | Package format schemas and contract |
| `Fixtures/ai-harness-design.depthcraft/` | Example course (AI harness design) |
| `docs/engineering/` | Implementation notes, dogfood analysis |
| `CLAUDE.md` | Builder agent handoff |

---

## Scope boundaries

**Shipped now:**
- iPad reader and generation UI
- BYOK with Anthropic, OpenAI, OpenRouter, custom endpoints
- Curriculum approval workflow
- Offline study with MC/cloze quizzes and sandboxed demos
- Extend/refresh with version tracking
- Device-local progress

**Later / roadmap:**
- Primers (pre-lesson concept checks)
- Tap-to-explain on lesson terms
- iCloud progress sync
- Standalone Mac app
- App Store distribution

---

## Contributing

Depthcraft is early-stage open source. Issues, feature requests, and PRs welcome. For significant changes, open an issue first to discuss scope.

**Engineering notes:**
- Implementation details: [`docs/engineering/`](docs/engineering/)
- Package schema: [`schema/0.1.0/README.md`](schema/0.1.0/README.md)
- Reader architecture: [`apps/DepthcraftReader/README.md`](apps/DepthcraftReader/README.md)

### Build from source

See [`apps/DepthcraftReader/README.md`](apps/DepthcraftReader/README.md) for build instructions (requires macOS, Xcode 15+, XcodeGen).

---

## License

Licensing is under review. This codebase is open for inspection and experimentation; formal license terms will be published soon. Open an issue if you have licensing questions.
