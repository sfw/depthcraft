# Depthcraft — Claude Code handoff

Mac + Xcode + Claude Code owns the **iPad reader** iteration. Lab Partner / Product Designer own schema, fixtures, and product locks.

## Open the app

```bash
cd apps/DepthcraftReader
brew install xcodegen   # once
xcodegen generate
open DepthcraftReader.xcodeproj
```

Select an **iPad** simulator → Run (⌘R). Study path is offline; fixture is bundled from `../../Fixtures/ai-harness-design.depthcraft`.

## Product bar (do not regress)

Course experience, **not** a markdown file browser:

- Course home → unit → lesson (WKWebView) → **native** in-flow MC + cloze with explain
- Progress: device-local by `packageId` (never clobber on re-import)
- Airplane mode: zero network on the study path
- Out of scope for v0.1 reader: primers, demos, chat, accounts, iCloud, generation pipeline

## Product nits for this pass (from Product Designer)

1. **Read intent ≠ open.** Do not treat ~0.8s open as "studied." Resume may track last opened lesson; **completion** still requires meaningful read intent **and** quiz pass (e.g. scroll-end **or** explicit Continue to quiz before read counts).
2. **Thicken lesson chrome.** Study typography in the WebView HTML (measure, type scale, margins) + **estimated minutes** in the lesson header.
3. **Course session handoff.** After quiz pass, strong **Next lesson** / unit checkmark so it feels like one continuous course session.

When you have simulator screenshots of home / unit / lesson / quiz, Scott can send them to Product Designer for a sharper UX critique.

## Package contract

- Schema: `schema/0.1.0/`
- Dogfood fixture: `Fixtures/ai-harness-design.depthcraft/` (topic: AI harness design for educational systems)
- Cloze grade: Unicode casefold + trim
- MC grade: `correctId` match

## Repo layout

```
schema/0.1.0/
Fixtures/ai-harness-design.depthcraft/
apps/DepthcraftReader/   # SwiftUI + project.yml (XcodeGen)
```
