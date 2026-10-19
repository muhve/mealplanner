@AGENTS.md

## Project

Meal Planner — iOS app (Expo SDK 58, Expo Router). Bundle ID `fi.muhve.mealplanner`.
GitHub: `muhve/mealplanner`. Expo project: `mealplanner` (owner `felixlin`).

## Environment

- Secrets are in untracked `.env` (`GH_TOKEN`, `EXPO_TOKEN`). Env vars don't survive between Bash calls, so start every command that runs `gh`, `eas` or a push with `set -a; . ./.env; set +a;`. Never print them.
- `gh` is installed in `~/.local/bin` (on PATH; call it as `gh`). Interactive logins (`eas login`, `gh auth login`) don't work here — the tokens do.
- Every git command that talks to GitHub (`fetch`, `pull`, `push`) needs the token via a credential helper, e.g.
  `git -c credential.helper= -c credential.helper='!f(){ echo username=x-access-token; echo "password=$GH_TOKEN"; }; f' push -u origin HEAD`
  (same `-c` options for `fetch origin` / `pull --ff-only`). The skills' plain `git fetch`/`git pull` mean this form.
- Codex writes the code in an isolated Docker container (`tools/codex/run.sh`); Claude orchestrates and verifies
  (`codex-build` skill). CLI: `codex` in `~/.local/bin`, logged in with the developer's ChatGPT account
  (re-login: `! codex login --device-auth`).
- The developer mostly follows along on a phone: send screenshots, not descriptions (`review-page` skill).

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
- Send a screenshot to the chat after each visible change.
- Before opening a PR: `npm run lint && npm run typecheck && npx expo-doctor` pass, the review–fix loop (Codex review rounds + one final Claude check) finds no
  real issues (max 5 rounds), and the branch is squashed into one clean commit (`work-issue` skill).
- PR body: `Closes #<n>`, the "Ships as" box ticked (OTA vs native build), the review page link.
- Merging to `main` deploys automatically (`deploy` skill) — it is a production release. Merge only when the
  developer says so, or for a `yolo` issue whose gates pass (`autopilot` skill).

## Labels

| Label | Meaning |
|---|---|
| `ready` | Autopilot may build it; PR left for the developer |
| `yolo` | Autopilot may build and auto-merge: CI green + ships OTA + clean review. Otherwise → `needs-review` |
| `in-progress` | Claimed by Claude |
| `needs-info` | Claude asked questions on the issue. After answering, remove `needs-info` and re-add `ready`/`yolo` |
| `needs-review` | Autopilot stopped; the developer must look. To let autopilot retry, remove `needs-review` and close any open PR for it |

Autopilot skips issues that already have an open PR.

## Deployment model

`.eas/workflows/deploy-production.yml` runs on every push to `main`:
- native fingerprint unchanged → EAS Update (OTA) to the `production` channel — users get it on next app launch.
- native fingerprint changed → `eas build --profile production` + submit to TestFlight.
App Store release from TestFlight is manual (`app-store-release` skill).

Things that change the fingerprint (= require a new native build): adding/upgrading packages with native code,
changing `app.json` native fields or plugins, Expo SDK upgrades, changes to icons/splash, and edits to `.gitignore`.
