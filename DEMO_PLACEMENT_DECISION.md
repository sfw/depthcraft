# Demo Placement Decision — Awaiting Product Designer Signoff

## Current Implementation: Below-Content Stacking

Demos are rendered **after** the lesson content in a vertical stack:
```
[Lesson Content WebView]
[Demo 1]
[Demo 2]
...
```

**Rationale:**
- Simple implementation (single WebView for lesson, native views for demos)
- Predictable layout (no dynamic height coordination needed)
- Clear separation between study content and interactive practice

**Tradeoff:**
- Demos appear at end regardless of `:::demo:::` directive position in markdown
- May disrupt narrative flow if demo is meant to illustrate a specific section

## Alternative: True Inline Placement

Would render demos at exact `:::demo id="...":::` directive positions:
```
[Lesson Content Part 1 WebView]
[Demo 1]
[Lesson Content Part 2 WebView]
[Demo 2]
[Lesson Content Part 3 WebView]
```

**Implementation requirements:**
1. Split lesson HTML at `<div class="demo-placeholder" id="DEMO_PLACEHOLDER_xxx">` markers
2. Create multiple `LessonWebView` instances (one per split section)
3. Alternate between WebView sections and DemoHostView instances in VStack
4. Manage dynamic WebView heights (requires JS height probing or estimation heuristics)
5. Coordinate scroll behavior across multiple WebViews

**Tradeoffs:**
- More complex rendering logic (5-8x more code in `LessonContentView`)
- Potential layout jank if WebView heights are mis-estimated
- Multiple WebView instances may increase memory footprint
- Harder to maintain scroll-to-end detection for read intent

**Benefits:**
- Demos appear contextually where author placed them
- Better narrative flow for illustrative demos
- Matches mental model of "inline" directive

## Recommendation for Product Designer

**Question:** Is below-content demo placement acceptable for v0, or is true inline placement required for the intended UX?

**Considerations:**
- Current approach is simpler, more robust, and easier to iterate on
- True inline is achievable but adds implementation risk (layout bugs, scroll issues)
- For brief/standard depth lessons with 1-2 demos, placement may not matter much
- For exhaustive lessons with multiple illustrative demos, inline may be important

**If below-content is acceptable:**
- Ship current implementation
- Can revisit inline placement post-v0 based on user feedback

**If inline is required:**
- Implement HTML splitting + multi-WebView layout (estimate 2-3 days additional work)
- Increases QA surface area (dynamic heights, scroll behavior, memory)

---

**Status:** Awaiting Product Designer decision. Lab Partner is asking PD in parallel.
