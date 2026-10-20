@AGENTS.md

## Project

Meal Planner — native Swift/SwiftUI iOS 17+ app, generated from `project.yml` with XcodeGen. Bundle ID `fi.muhve.mealplanner`.
GitHub: `muhve/mealplanner`. Pure Foundation logic lives in the local `MealPlannerCore` Swift package.

## Environment

- Secrets are in untracked `.env` (`GH_TOKEN`). Env vars don't survive between Bash calls, so start every command that runs `gh` or a push with `set -a; . ./.env; set +a;`. Never print them.
- `gh` is installed in `~/.local/bin` (on PATH; call it as `gh`). Interactive logins (`gh auth login`) don't work here — the tokens do.
- Every git command that talks to GitHub (`fetch`, `pull`, `push`) needs the token via a credential helper, e.g.
  `git -c credential.helper= -c credential.helper='!f(){ echo username=x-access-token; echo "password=$GH_TOKEN"; }; f' push -u origin HEAD`
  (same `-c` options for `fetch origin` / `pull --ff-only`). The skills' plain `git fetch`/`git pull` mean this form.
- Codex writes the code in an isolated Docker container (`tools/codex/run.sh`); Claude orchestrates and verifies
  (`codex-build` skill). CLI: `codex` in `~/.local/bin`, logged in with the developer's ChatGPT account
  (re-login: `! codex login --device-auth`).
- The developer builds and tests the app in Xcode and sends simulator screenshots (`review-page` skill). Claude cannot take app screenshots here.

## Working modes

| Mode | Started by | Skill | Ends with |
|---|---|---|---|
| 1. Design | "let's design…", a new idea | `design-issue` | Issue + review page. No code. No `ready`/`yolo` unless asked. |
| 2. Build together | "work on #n", "let's build…" | `work-issue` | One squashed PR + review page; ask "merge now or leave it?" |
| 3. Autopilot | `/loop /autopilot` | `autopilot` | A PR per `ready`/`yolo` issue; `yolo` auto-merges if its gates pass |

## Rules for every mode

- Every change starts from a GitHub issue and lands via a PR into `main`. Never push to `main` — in any form
  (`HEAD:main`, `-c credential.helper=… push … main`). The deny rules in `.claude/settings.json` only catch common
  spellings; this rule is what counts.
- Branch names: `<issue-number>-<short-slug>` (e.g. `12-weekly-plan`).
- Every issue and PR links its review page — a Claude artifact with design, changes, checks, review rounds and
  screenshots — via an issue comment starting `Review page: <url>`. Keep it current.
- After each visible change, record that simulator screenshots are needed from the developer.
- Before opening a PR: `swift build && swift test` in `MealPlannerCore` (Claude runs this via Docker; command below) pass, the review–fix loop (Codex review rounds + one final Claude check) finds no
  real issues (max 5 rounds), and the branch is squashed into one clean commit (`work-issue` skill).
- PR body: `Closes #<n>`, device/simulator testing status, the review page link.
- Merging to `main` only merges code. Merge only when the developer says so, or for a `yolo` issue whose gates pass (`autopilot` skill).

## Labels

| Label | Meaning |
|---|---|
| `ready` | Autopilot may build it; PR left for the developer |
| `yolo` | Autopilot may build and auto-merge: CI green + clean review. Otherwise → `needs-review` |
| `in-progress` | Claimed by Claude |
| `needs-info` | Claude asked questions on the issue. After answering, remove `needs-info` and re-add `ready`/`yolo` |
| `needs-review` | Autopilot stopped; the developer must look. To let autopilot retry, remove `needs-review` and close any open PR for it |

Autopilot skips issues that already have an open PR, and issues whose body has a line `Depends on #<m>` while #<m> is
still open. Use that line whenever an issue builds on another one.

## Verification

Codex writes Swift. Claude verifies the Foundation-only core and reviews the diff:

```bash
docker run --rm -v "$PWD":/w -w /w/MealPlannerCore swift:6.2-bookworm sh -c 'swift build && swift test'
```

Linux has no SwiftUI, UIKit or iOS SDK. The developer builds and tests the app in Xcode and sends simulator screenshots.

## Releases

Releases are manual from Xcode; see [docs/MAC-SETUP.md](docs/MAC-SETUP.md). Every app change requires a new build.
There are no OTA updates or automatic releases on merge. Xcode manages signing with team `4X292LGV9D`.
