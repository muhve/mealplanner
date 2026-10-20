---
name: autopilot
description: Use when running autopilot — started with "/loop /autopilot" or "start autopilot". Keeps building GitHub issues labelled ready or yolo, one at a time, until the developer says stop.
---

# Autopilot

Runs in this container inside a self-paced `/loop`. Env vars do not survive between Bash calls: start **every** command that runs `gh` or a push with `set -a; . ./.env; set +a;`.
Stop: developer says stop → `ScheduleWakeup` with `stop: true`.

## Start-up (first iteration only)
List `gh issue list --label in-progress --state open`. Report any to the developer as possibly stale from an
earlier run; never pick them up yourself.

## Each iteration
1. **Pick** the oldest eligible issue that has no open PR yet. Use label filters, **not** `--search`: GitHub's
   search index lags (new issues and fresh labels like `in-progress` show up late), the label filter doesn't.
   ```bash
   set -a; . ./.env; set +a
   for l in ready yolo; do
     gh issue list --state open --limit 100 --label $l --json number,labels,createdAt \
       --jq '.[] | select([.labels[].name] | index("in-progress") or index("needs-info") or index("needs-review") | not)
             | "\(.createdAt) \(.number) \([.labels[].name] | join(","))"'
   done | sort -u                                                         # oldest first
   gh pr list --state open --limit 100 --json headRefName --jq '.[].headRefName'   # branches with an open PR
   ```
   Take the first issue `<n>` with no open PR from a branch named `<n>-…` and no unmet dependency: for each
   `Depends on #<m>` in its body, #<m> must be closed:
   ```bash
   for m in $(gh issue view <n> --json body --jq .body | grep -oiE 'depends on #[0-9]+' | grep -oE '[0-9]+'); do
     gh issue view $m --json state --jq .state                            # all CLOSED → eligible
   done
   ```
   Take the first issue `<n>` that passes both checks. That keeps an open `ready` PR from
   being picked up again, while an issue whose PR was closed can be retried.
   None → `ScheduleWakeup` ~900 s with the same `/loop` prompt (`noop: true`), end the iteration.
2. **Mode:** `yolo` only if the issue has `yolo` and **not** `ready`; otherwise `ready` (both labels → `ready`).
3. **Claim:** `gh issue edit <n> --add-label in-progress`; `gh issue comment <n> --body "Autopilot picked this up."`
4. **Unclear** acceptance criteria (missing, contradictory, or needing a product decision): comment the questions,
   `gh issue edit <n> --remove-label ready,yolo,in-progress --add-label needs-info`, go to step 1.
5. **Build:** `work-issue` steps 1–8 in autopilot mode.
6. **Decide:**
   - `ready` → leave the PR open.
   - `yolo` → merge (work-issue step 9) only if **all** pass:
     - CI green — the Actions run for the branch head, watched in the background (work-issue step 9)
     - review–fix loop ended with no real findings
     Any gate fails → no merge; `gh issue edit <n> --add-label needs-review`; PR comment naming the failed gate.
     Merge only merges code. The developer builds and releases manually from Xcode.
   - Real findings left after 5 review rounds, unresolvable rebase conflict, or any unexpected error → `needs-review`
     with a comment explaining; never merge.
7. **Finish:** remove `in-progress`; update the review page; send a one-line chat message: issue, PR link, merged or waiting. Include a screenshot from the developer if available (status `proactive`). Go straight to step 1.

Never push to `main`, never force-push anything but the issue branch, never close or delete issues.
