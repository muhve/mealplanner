---
name: codex-build
description: Use for the build and fix steps of work-issue — hands the code-writing to Codex (developer's ChatGPT subscription), run in an isolated Docker container, to save Claude tokens, while Claude briefs, verifies and reviews. Falls back to Claude when Codex is unavailable.
---

# Build with Codex

Claude is the orchestrator: it plans, writes the brief, runs every gate, reviews, and owns git, PRs, secrets and the
review page. Codex only edits files in a throwaway clone. Never trust Codex's own "done" — the gates in work-issue
decide.

**Isolation.** `tools/codex/run.sh` runs Codex in a Docker container that mounts only a fresh clone of the issue
branch (no `.env` — it's untracked), Codex's own login (`~/.codex`) and a scratch dir. No deploy tokens, no Docker
socket. Codex runs with its internal sandbox off because it can't start here (no user namespaces); the container is
the sandbox. Never run `codex exec` directly on this checkout, and never mount the repo itself or `.env` into the
container. Codex Cloud is not used: its CLI can't see new-style environments (openai/codex#50182).

Paths below: `C=$CLAUDE_JOB_DIR/tmp/codex`, clone `$C/<n>-clone`.

## 0. Is Codex usable?

```bash
codex login status && docker info >/dev/null
```
Fails, or a run fails with a quota/auth error → **fall back**: Claude builds it as before (work-issue step 3) and
notes "Codex unavailable: <reason>" on the review page. Interactive: the developer can log in with
`! codex login --device-auth`.

Write security-critical parts (auth, keys, secrets, sharing) yourself when they are small enough that a brief would
cost as much as writing them. Either way, review such code extra closely.

## 1. Brief

Commit everything on the issue branch first — Codex starts from a clone of the committed branch. Write
`$C/<n>-brief.md`. Codex reads `AGENTS.md` itself; don't repeat it. Include:

- Issue `#<n>` title and the acceptance criteria, verbatim.
- The plan: approach, files to create/change, data shapes, names. Be concrete — vague briefs cost more in fix rounds.
- Anything already decided on the issue or review page (libraries, UX copy, out of scope).
- These rules, verbatim:
  ```
  Rules:
  - Change only what this task needs. Do not run git commit, push, or anything that deploys.
  - Never edit ios/ or android/. Add packages only with `npx expo install <pkg>`.
  - Before you finish, run `npm run lint && npm run typecheck` and fix what fails.
  - End with a short report: files changed, what each change does, any acceptance criterion you could not meet or
    verify, and anything you are unsure about. No code in the report.
  ```

## 2. Run

Runs take minutes: use Bash `run_in_background` and continue when it completes.

```bash
tools/codex/run.sh new "$C/<n>-clone" <n>-<slug> "$C/<n>-brief.md" "$C/<n>-report.md" > "$C/<n>-log.txt" 2>&1
```

Read only the report, not the log — the log is long and spends Claude tokens. Open the log (`tail`) only when the run
failed or the report is missing.

## 3. Collect and verify

1. `git -C "$C/<n>-clone" status --short` — no changes outside the planned files, nothing touching `ios/`,
   `android/`, `.gitignore` or `app.json` unless the brief asked for it.
2. `tools/codex/run.sh collect "$C/<n>-clone" "codex: <what>"` — commits Codex's changes and fast-forwards the issue
   branch in this checkout.
3. `npm ci` if `package-lock.json` changed, then run the gates yourself:
   `npm run lint && npm run typecheck && npx expo-doctor`.
4. Review the diff (work-issue step 5).

## 4. Fix rounds

Commit any fixes of your own first. Write `$C/<n>-fixes-<round>.md`: one numbered list of failing gates and **real**
review findings, each with file, problem and expected behaviour, then the same rules block. Then (background):

```bash
tools/codex/run.sh resume "$C/<n>-clone" "$C/<n>-fixes-<round>.md" "$C/<n>-report.md" > "$C/<n>-log.txt" 2>&1
```
`resume` syncs the clone with the branch first and continues the same Codex session. Then step 3 again. The 5-round
cap of the review–fix loop counts these rounds. A finding Codex fails to fix twice → fix it yourself.

## 5. Review with Codex

Codex also does the review rounds (work-issue step 5). Commit everything first; the review clones the committed
branch. Write `$C/<n>-review-brief.md`: one paragraph on what the branch implements (issue, acceptance criteria,
the risky areas to focus on). `run.sh` appends the review rules and output format. Then (background):

```bash
tools/codex/run.sh review "$C/<n>-review" <n>-<slug> "$C/<n>-review-brief.md" "$C/<n>-review-<round>.md" \
  > "$C/<n>-log.txt" 2>&1
```
Read only the report. It's either `No real findings.` or a numbered list. Triage each item yourself: **real** or
**dismissed** (one-line reason). Check a finding against the code only when it's unclear. A run that exits non-zero
because Codex modified files is void: rerun it. Delete `$C/<n>-review` when done.

## 6. Record

On the review page's Changes section, say which parts Codex wrote and which Claude wrote, and in Review rounds who
fixed each finding. Delete `$C/<n>-clone` once the PR is open.
