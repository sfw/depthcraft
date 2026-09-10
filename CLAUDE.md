# Depthcraft — Claude Code handoff

## Org chart (do not skip)

| Role | Who | Job |
|------|-----|-----|
| Eng lead | **Lab Partner** (Scott’s Grok Bot) | Oversees builders, answers eng questions, reviews PRs, gives direction |
| Product | **Product Designer** (via Lab Partner) | UX/scope/completion rules — builders do **not** ping Product Designer directly |
| Builder | **You (Claude Code on Mac)** | Implement on a branch, open PRs, ask Lab Partner when stuck |
| Human | Scott | Dogfood, screenshots, merge when Lab Partner says merge-ready |

Scott should not be the relay. If you need a decision, escalate to Lab Partner (issue/`needs-lab-partner` or PR comment `@` / clear ask). Lab Partner asks Product Designer for product forks.

## How to work

1. Branch off `main` — never dump big UI straight onto `main`.
2. Open a **PR** early; keep it updated.
3. Questions / blockers → GitHub **issue** with label `needs-lab-partner` (create the label if missing), body = question + options you considered. Do not guess past a product fork.
4. After meaningful UI: ask Scott to drop iPad simulator screenshots of home / unit / lesson / quiz into the Lab Partner chat for UX critique.
5. Wait for Lab Partner review comments before treating work as done.

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
CLAUDE.md
```
