---
name: design-issue
description: Use when the developer wants to brainstorm or design a feature or change together and turn it into a GitHub issue ("let's design…", "I have an idea…", "make an issue for…"). Produces an issue and review page, no code.
---

# Design → GitHub issue

1. Brainstorm with the `superpowers:brainstorming` skill's conversation style: one question at a time, prefer
   multiple choice. When it helps, send screenshots of the current screens (`review-page` skill) — the developer
   is on a phone.
2. Agree on: goal, acceptance criteria (testable, checkbox list), key decisions, anything out of scope.
3. Read the understanding back in a short note and wait for an OK.
4. `gh issue create --label enhancement --title "<title>" --body-file <tmpfile>` using
   `.github/ISSUE_TEMPLATE/feature.md` (Goal, Acceptance criteria) plus a "Decisions" section.
   Add `ready` or `yolo` **only if the developer says so** — those labels start autopilot work.
5. Create the review page (`review-page` skill), status `designing`, Design section filled; comment its link.
6. Reply with the issue URL and review-page URL. No branch, no code.
