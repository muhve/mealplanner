---
name: work-issue
description: Use when picking up a GitHub issue to implement ("work on #N", "let's build …", "do the next issue"), and as the per-issue procedure autopilot runs. Covers branch, build, screenshots, review–fix loop, squash, PR, merge.
---

# Work a GitHub issue

Two modes: **interactive** (developer in the chat — ask when unsure) and **autopilot** (nobody to ask — decide
conservatively and record each decision on the review page). Env vars do not survive between Bash calls (or into background shells): start **every** command that runs `gh` or a push with `set -a; . ./.env; set +a;`.

1. **Issue.** `gh issue view <n> --comments`. No issue yet (interactive)? Summarise the chat into one with
   `gh issue create --label enhancement` from `.github/ISSUE_TEMPLATE/feature.md`. Unclear criteria: interactive → ask;
   autopilot → see autopilot skill. No review page yet → create it now (`review-page` skill), Design section filled.
2. **Branch.** `git switch main && git pull --ff-only && git switch -c <n>-<slug>`;
   `gh issue edit <n> --add-label in-progress`. Record **before** simulator screenshots from the developer when available.
3. **Build** with the `codex-build` skill: Claude writes the brief, Codex writes the code, Claude verifies and
   commits (it falls back to Claude building it when Codex is unavailable). Follow AGENTS.md (SwiftUI iOS 17 and Foundation-only Core). Commit freely; history is squashed later. The developer builds in Xcode and sends simulator screenshots after visible changes.
4. **Checks.** `docker run --rm -v "$PWD":/w -w /w/MealPlannerCore swift:6.2-bookworm sh -c 'swift build && swift test'` — all must pass. Fix, don't skip.
5. **Review–fix loop**. Codex reviews, Claude triages (`codex-build` step 5):
   1. **Codex rounds** (max 5): Codex reviews `main...HEAD`; classify each finding **real** (bug, unmet acceptance
      criterion, failing check, security, clear quality problem) or **dismissed** (style nitpick, false positive,
      with a one-line reason); send the real ones to Codex as a fix round (`codex-build` step 4), re-run step 4,
      record the round on the review page, review again. Stop when Codex reports `No real findings.` or
      when you rated none of a round's findings real (all dismissed). That counts as "no real findings" for gates.
   2. **Final check**: one Claude review of `git diff origin/main...HEAD` with the `code-review` skill at `medium`.
      Real findings go through one more Codex fix round and a Codex review, then this final check is not repeated.
   3. Still real findings after Codex round 5, or after the final check's fix round: interactive → ask the
      developer; autopilot → continue, PR gets `needs-review`.
   4. **Codex unavailable** (`codex-build` step 0 fails, or a review run fails with an auth/quota error): run the
      rounds with the `code-review` skill (`high`) instead, fixing real findings yourself, max 5 rounds; skip the
      separate final check. Note "Codex unavailable: <reason>" on the review page.
6. **Squash** into one commit:
   ```bash
   git fetch origin && git rebase origin/main   # resolve conflicts; re-run step 4 if anything changed
   git reset --soft origin/main
   git commit -F <msgfile>                          # see below
   docker run --rm -v "$PWD":/w -w /w/MealPlannerCore swift:6.2-bookworm sh -c 'swift build && swift test'
   ```
   Message: imperative subject ≤ 72 chars; body = what changed and why, validation performed, `Closes #<n>`,
   then the attribution trailers.
7. **Device check.** Record whether the developer has tested in Xcode on a simulator/device. Claude cannot run the app or capture simulator screenshots here.
8. **PR.** Push the branch (credential-helper command in CLAUDE.md; `--force-with-lease` after a squash, branch only).
   `gh pr create --title "<subject>" --body-file <tmpfile>` following `.github/pull_request_template.md`:
   `Closes #<n>`, device/simulator testing status, `Review page: <url>`, short testing notes. Draft PR (`--draft`) if checks
   failed. Update the review page (Changes, Checks, Review rounds, Screenshots, status `PR open`); send the PR link
   to the chat; include an after-screenshot from the developer if available.
9. **Merge?** Interactive → ask "merge now, or leave it for you?". Autopilot → autopilot skill decides.
   To merge: CI must pass. `gh pr checks` does **not** work with our fine-grained token ("Resource not accessible
   by personal access token"), so wait on the GitHub Actions run for the branch head instead. The run may take a
   few seconds to appear and minutes to finish — longer than a foreground command may run — so run this with Bash
   `run_in_background` and continue when its completion notice arrives (exit 0 = green, anything else = not green):
   ```bash
   set -a; . ./.env; set +a; SHA=$(git rev-parse HEAD); ID=
   for i in $(seq 30); do
     ID=$(gh run list --branch <branch> --workflow CI --limit 20 --json databaseId,headSha \
       --jq ".[] | select(.headSha==\"$SHA\") | .databaseId" | head -1)
     [ -n "$ID" ] && break; sleep 10
   done
   [ -n "$ID" ] || { echo "no CI run for $SHA"; exit 1; }
   gh run watch "$ID" --exit-status
   ```
   Then `gh pr merge <pr> --squash --delete-branch`,
   record the outcome on the review page. Merging only merges; releases are manual from Xcode (docs/MAC-SETUP.md).
   Remove `in-progress` from the issue when the PR is opened (left open) or merged.

Never merge without the developer's go-ahead, except a `yolo` issue whose gates pass (autopilot skill).
