# Depthcraft — builder handoff

## Org chart

| Role | Who | Job |
|------|-----|-----|
| Eng lead | **Lab Partner** (Scott’s Grok Bot) | Dispatches builder agents, answers questions, reviews PRs, gives direction, updates Scott |
| Product | **Product Designer** (via Lab Partner) | UX/scope/completion rules — builders do **not** ping Product Designer directly |
| Builder | **Cursor cloud agents** (and any other agents Lab Partner launches) | Implement on a branch, open PRs, escalate to Lab Partner when stuck |
| Human | Scott | Dogfood, screenshots, high-level calls — **does not** run Claude Code or babysit builders |

Scott is not the relay. Questions → Lab Partner (PR comment or issue labeled `needs-lab-partner`). Product forks → Lab Partner asks Product Designer, then posts the lock.

## How to work

1. Branch off `main` — never dump big UI straight onto `main`.
2. Open a **PR** early; keep it updated.
3. Blockers → issue with label `needs-lab-partner` (create label if missing).
4. Do not guess past a product fork.

## Open the app (Scott / Mac dogfood)

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

## Product nits (active)

1. **Read intent ≠ open.** Resume may track last opened lesson; **completion** requires meaningful read intent **and** quiz pass (scroll-end and/or Continue-to-quiz before read counts).
2. **Thicken lesson chrome.** Study typography (measure, type scale, margins) + **estimated minutes** in the lesson header.
3. **Course session handoff.** After quiz pass, strong **Next lesson** / unit checkmark.

## Package contract

- Schema: `schema/0.1.0/`
- Dogfood fixture: `Fixtures/ai-harness-design.depthcraft/`
- Cloze: Unicode casefold + trim; MC: `correctId` match
