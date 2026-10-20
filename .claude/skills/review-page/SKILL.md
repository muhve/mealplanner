---
name: review-page
description: Use when recording simulator screenshots from the developer, or when creating/updating the Claude artifact review page linked from a GitHub issue or PR (design, changes, checks, review rounds, screenshots).
---

# Screenshots & review pages

The developer mostly follows along on a phone. Show, don't describe.

## Screenshots

Screenshots are **from the developer**. The developer builds and tests the SwiftUI app in Xcode, captures light/dark simulator screenshots and sends them to Claude. Claude cannot run the iOS app or take simulator screenshots in Linux. Record pending screenshots honestly; use supplied images in the review page. Never commit screenshots. Never block a PR on missing screenshots.

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
3. Changes — files touched, what and why
4. Checks — Core swift build, swift test (Docker swift:6.2-bookworm), CI, developer Xcode/device checks; pass/fail each
5. Review rounds — per round: each finding → fixed (how) or dismissed (why)
6. Screenshots — from the developer; before/after per screen, light and dark when available
7. Outcome — merged by whom; manual release status, if known

**Create:** publish with `icon: "checklist"`, a one-sentence `description`, then
`gh issue comment <n> --body "Review page: <url>"`. Put the same link in the PR body.

**Screenshots on the page:** upload with `Artifact` publish `url` + `asset: true` + `file_paths`, reference the
returned URLs exactly.

**Update** at each milestone (design agreed, PR opened, each review round, merge/release): edit the source file and
republish with `url`.
