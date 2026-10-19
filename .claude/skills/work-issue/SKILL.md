---
name: work-issue
description: Use when picking up a GitHub issue to implement ("work on #N", "let's build …", "do the next issue"), and as the per-issue procedure autopilot runs. Covers branch, build, screenshots, review–fix loop, squash, PR, merge.
---

# Work a GitHub issue

Two modes: **interactive** (developer in the chat — ask when unsure) and **autopilot** (nobody to ask — decide
conservatively and record each decision on the review page). Env vars do not survive between Bash calls (or into background shells): start **every** command that runs `gh`, `eas` or a push with `set -a; . ./.env; set +a;`.

1. **Issue.** `gh issue view <n> --comments`. No issue yet (interactive)? Summarise the chat into one with
   `gh issue create --label enhancement` from `.github/ISSUE_TEMPLATE/feature.md`. Unclear criteria: interactive → ask;
   autopilot → see autopilot skill. No review page yet → create it now (`review-page` skill), Design section filled.
2. **Branch.** `git switch main && git pull --ff-only && git switch -c <n>-<slug> && npm ci`;
   `gh issue edit <n> --add-label in-progress`. Take **before** screenshots.
3. **Build** with the `codex-build` skill: Claude writes the brief, Codex writes the code, Claude verifies and
   commits (it falls back to Claude building it when Codex is unavailable). Follow AGENTS.md (versioned Expo docs,
   `npx expo install`). Commit freely; history is squashed later. After each visible change: screenshot → chat.
4. **Checks.** `npm run lint && npm run typecheck && npx expo-doctor` — all must pass. Fix, don't skip.
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
   git fetch origin && git rebase origin/main && npm ci   # resolve conflicts; re-run step 4 if anything changed
   git reset --soft origin/main
   git commit -F <msgfile>                          # see below
   npm run lint && npm run typecheck && npx expo-doctor
   ```
   Message: imperative subject ≤ 72 chars; body = what changed and why, how it ships (OTA/native), `Closes #<n>`,
   then the attribution trailers.
7. **Ships as.** Fingerprint check:
   ```bash
   H=$(npx @expo/fingerprint fingerprint:generate --platform ios 2>/dev/null | node -pe 'JSON.parse(require("fs").readFileSync(0)).hash')
   npx eas-cli@latest build:list --platform ios --build-profile production --fingerprint-hash "$H" \
     --status finished --json --non-interactive --limit 1
   ```
   Non-empty array → `OTA`. `[]` → `NATIVE` (new TestFlight build on merge).
   **Empty `$H`** (fingerprint generation failed) → `NATIVE`; never call `build:list` with an empty hash — an empty
   filter may match every build and wrongly say `OTA`.
8. **PR.** Push the branch (credential-helper command in CLAUDE.md; `--force-with-lease` after a squash, branch only).
   `gh pr create --title "<subject>" --body-file <tmpfile>` following `.github/pull_request_template.md`:
   `Closes #<n>`, correct "Ships as" box, `Review page: <url>`, short testing notes. Draft PR (`--draft`) if checks
   failed. Update the review page (Changes, Checks, Review rounds, Screenshots, status `PR open`); send the PR link
   and one after-screenshot to the chat.
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
   then the `deploy` skill to confirm the workflow started. Record the outcome on the review page.
   Remove `in-progress` from the issue when the PR is opened (left open) or merged.

Never merge without the developer's go-ahead, except a `yolo` issue whose gates pass (autopilot skill).
