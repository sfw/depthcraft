# Prose-First Pedagogy Changes — Testing Guide

**PR**: #87  
**Branch**: `cursor/prose-first-lesson-prompts-5532`  
**Priority**: P1 prompt hardening  
**Scope**: NEW generations only (existing packages unchanged)

## What Changed

### Files Modified
1. `apps/DepthcraftReader/Sources/Services/LessonWriterService.swift`
2. `apps/DepthcraftReader/Sources/Services/DemoWriterService.swift`
3. `apps/DepthcraftReader/Sources/Services/PlannerService.swift`

### Key Additions

#### LessonWriter
- **PROSE-FIRST PEDAGOGY** block in system prompt
- Requires real sections: hook, explanation, examples, pitfalls, summary
- Bans stubs that only launch demos
- Clarifies prose must stand alone; never mention/depend on demos

#### DemoWriter
- **PROSE-FIRST PEDAGOGY** preamble
- Emphasizes prose is PRIMARY, demos are ENHANCEMENTS
- Demos come AFTER prose explanation (via insertAfterHeading)
- Strengthened existing "bias to no demo" with prose-primacy framing
- User prompt now calls prose "complete teaching resource"

#### Planner
- **PROSE-FIRST PEDAGOGY** block
- Bans "demo lesson" as a lesson type
- Lesson objectives must focus on concepts, not activities
- All depth guidance strings now emphasize prose content

## How to Smoke Test

### Setup
Generate 2–3 **new** lessons with these prompts:
- Brief mode: "Introduction to React Hooks"
- Standard mode: "Understanding Async/Await in JavaScript"

### Verification Checklist

#### ✅ Prose Completeness
- [ ] Each lesson.md has 2–3+ main sections with substantive content
- [ ] Real pedagogical structure present (hook/motivation, core explanation, examples, edge cases/pitfalls, summary)
- [ ] No stubs that say "explore this in the demo" without explanation
- [ ] Prose teaches the concept fully on its own

#### ✅ Demo Earn-It
- [ ] NOT every lesson has a demo
- [ ] Demos only appear when concept truly benefits from hands-on manipulation
- [ ] Any demo has `insertAfterHeading` pointing to a prose section that already explained the concept
- [ ] Demo enhances understanding, doesn't replace prose teaching

#### ✅ Density Calibration
- [ ] **Brief**: Lean but complete prose (2–3 sections, essentials only); demos very rare or zero
- [ ] **Standard**: Balanced prose (2–4 sections with examples); demos selective (maybe 1 of 3 lessons)

#### ❌ Regressions to Watch
- [ ] No "demo-only" lessons (lesson.md is just a title + demo directive)
- [ ] No lessons that defer explanation to interactive without teaching in prose
- [ ] Planner didn't create lessons titled "Interactive: ..." or "Try it: ..."

## Expected Behavior

### Before (Problem State)
- Some lessons were demo-first or demo-only
- Prose might be a stub: "Let's explore this concept..." → demo
- Planner might create "Interactive Exploration" lessons
- Bias toward demos after demo-quality improvements

### After (Fixed State)
- Every lesson has substantive explanatory prose
- Prose teaches the concept completely
- Demos are rare and only when truly valuable
- Demos appear AFTER the prose that explains what they demonstrate
- Planner creates concept-focused lesson objectives

## Notes
- Existing packages (e.g., `Fixtures/ai-harness-design.depthcraft`) are **unchanged**
- Only affects **NEW** lesson generation
- ComplexityAnalyzer unchanged (it identifies terms for glosses, not demo routing)
- No reader chrome changes in this PR (demo offset polish is separate)
