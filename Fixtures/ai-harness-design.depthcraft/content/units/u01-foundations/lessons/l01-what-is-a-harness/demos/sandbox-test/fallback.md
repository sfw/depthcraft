# Sandbox Test Demo

This is a negative test case demo that deliberately attempts to load external resources (CDN scripts, fetch requests, images) to verify sandbox enforcement.

**Expected behavior:**
- All external `http`/`https` requests should be blocked
- Local package file access should work
- Demo should show test results inline

**What's tested:**
- External script tags (`<script src="https://...">``)
- Fetch API to external URLs
- XMLHttpRequest to external APIs
- External image loading
- Local file access (should work)

If the sandbox is working correctly, this demo should render and show that all external requests were blocked while local file access succeeded.
