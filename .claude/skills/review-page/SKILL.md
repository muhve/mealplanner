---
name: review-page
description: Use when taking app screenshots to show the developer, or when creating/updating the Claude artifact review page linked from a GitHub issue or PR (design, changes, checks, review rounds, screenshots).
---

# Screenshots & review pages

The developer mostly follows along on a phone. Show, don't describe.

## Screenshots

1. **Dev server.** `curl -s -o /dev/null -w '%{http_code}' localhost:8081` — if `200`, reuse it. Otherwise start
   `npx expo start --web --port 8081` with Bash `run_in_background`, then poll the curl until `200`
   (first bundle takes ~30 s). If it never comes up within 2 min, skip screenshots and say so on the review page.
2. **Capture** with the Playwright tools (load them via ToolSearch `+playwright` if deferred):
   - `browser_resize` 393×852
   - `browser_navigate` `http://localhost:8081/<route>`; `browser_wait_for` the screen's text
   - `browser_emulate_media` colorScheme `light` → `browser_take_screenshot` (`scale: "css"`); then `dark` → screenshot
   - Leave `filename` unset: the tool then saves outside the repo, in its output dir (`/home/felix/.claudejail/outputs`).
     A relative filename lands in the repo root; an absolute path elsewhere is refused.
   - Move each file the tool reports to `$CLAUDE_JOB_DIR/tmp/shots/<n>/<screen>-<before|after>-<light|dark>.png`
3. **Before shots**: taken on the branch right after it's created, before any edits, for each screen the issue touches.
4. **Send to chat** with `SendUserFile` (`display: "render"`, one-line caption; `status: "proactive"` in autopilot,
   `"normal"` when replying). Send after each visible change — not every save.
5. Never commit screenshots. Never block a PR on a screenshot failure.

Web screenshots don't show native-only behaviour (haptics, glass effects, iOS controls); say so when it matters.

## Review page

One Claude artifact per issue. Same URL for its whole life; updated in place.

**Find it:** `gh issue view <n> --json comments --jq '.comments[].body' | grep -m1 '^Review page: ' | cut -d' ' -f3`

**Before first publish in a session:** load the `artifact-design` and `artifact-capabilities` skills
(the page declares the `assets` capability for screenshots).

**Source file:** `$CLAUDE_JOB_DIR/tmp/review-pages/<n>.html`. If the page exists but the file doesn't (new session),
`Artifact` `action: "read"` the URL and build on the returned saved file.

**Sections, in order:**
1. Header — `#<n> <issue title>`, status (`designing` / `building` / `PR open` / `merged` / `needs review`), issue + PR links
2. Design — goal, acceptance criteria (✓/✗ once built), key decisions
3. Changes — files touched, what and why, ships as OTA or native build
4. Checks — lint, typecheck, expo-doctor, CI, fingerprint; pass/fail each
5. Review rounds — per round: each finding → fixed (how) or dismissed (why)
6. Screenshots — before/after per screen, light and dark
7. Outcome — merged by whom, deploy status

**Create:** publish with `icon: "checklist"`, a one-sentence `description`, then
`gh issue comment <n> --body "Review page: <url>"`. Put the same link in the PR body.

**Screenshots on the page:** upload with `Artifact` publish `url` + `asset: true` + `file_paths`, reference the
returned URLs exactly.

**Update** at each milestone (design agreed, PR opened, each review round, merge/deploy): edit the source file and
republish with `url`.
