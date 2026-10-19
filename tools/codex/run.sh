#!/usr/bin/env bash
# Run Codex in an isolated Docker container that sees only a clean clone of one branch — never .env, deploy
# tokens or the Docker socket. Codex's own sandbox can't start in this environment; the container is the sandbox.
# See .claude/skills/codex-build/SKILL.md.
#
#   tools/codex/run.sh new     <clone-dir> <branch> <prompt-file> <report-file>   fresh clone, new Codex session
#   tools/codex/run.sh resume  <clone-dir> <prompt-file> <report-file>            same session, clone synced first
#   tools/codex/run.sh collect <clone-dir> <message>                              commit Codex's changes, ff into repo
#   tools/codex/run.sh review  <clone-dir> <branch> <brief-file> <report-file>   Codex reviews main...branch (read-only)
set -euo pipefail
mode=$1; wt=$2
repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)

run_codex() { # <prompt-file> <report-file> <container command>
  # Each clone is mounted at its own path, so `resume --last` (which filters by working dir) finds this issue's
  # session, not whichever ran most recently.
  local prompt=$1 report=$2 cmd=$3 out work status=0
  out=$(mktemp -d); work="/w/$(basename "$wt")"
  trap 'rm -rf "$out"' RETURN
  cp "$prompt" "$out/prompt.md"
  docker build -q -t mealplanner-codex "$repo/tools/codex" >/dev/null
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -w "$work" \
    -v "$wt":"$work" -v "$HOME/.codex":/codex-home -v "$out":/out \
    mealplanner-codex sh -c "$cmd" || status=$?
  mkdir -p "$(dirname "$report")"
  if [ -s "$out/report.md" ]; then mv "$out/report.md" "$report"
  else echo "Codex run failed (exit $status) and wrote no report; see the log." > "$report"; fi
  return "$status"
}

case $mode in
  new)
    branch=$3
    rm -rf "$wt"
    git clone -q --no-hardlinks "$repo" "$wt" -b "$branch"
    [ ! -e "$wt/.env" ] || { echo ".env found in clone, aborting" >&2; exit 1; }
    run_codex "$4" "$5" 'npm ci --no-audit --no-fund > /tmp/npm.log 2>&1 || { tail -20 /tmp/npm.log; echo "npm ci failed" >&2; exit 90; };
      codex exec --dangerously-bypass-approvals-and-sandbox -o /out/report.md - < /out/prompt.md'
    ;;
  resume)
    # Bring in anything committed in the repo since (e.g. fixes Claude made itself).
    git -C "$wt" pull -q --ff-only origin "$(git -C "$wt" branch --show-current)"
    run_codex "$3" "$4" 'npm ci --no-audit --no-fund > /tmp/npm.log 2>&1 || { tail -20 /tmp/npm.log; echo "npm ci failed" >&2; exit 90; };
      codex exec resume --last --dangerously-bypass-approvals-and-sandbox -o /out/report.md - < /out/prompt.md'
    ;;
  review)
    branch=$3
    rm -rf "$wt"
    git clone -q --no-hardlinks "$repo" "$wt" -b "$branch"
    git -C "$wt" branch -q -f main origin/main
    [ ! -e "$wt/.env" ] || { echo ".env found in clone, aborting" >&2; exit 1; }
    refs=$(git -C "$wt" show-ref --head)
    review_prompt=$(mktemp)
    trap 'rm -f "$review_prompt"' EXIT
    cat "$4" - > "$review_prompt" <<'EOF'

How to work: run `git diff main...HEAD` and read changed files as needed. REVIEW ONLY: do not modify, create or
delete files and do not commit. You may run the project's checks (`npm test`, `npm run typecheck`) to confirm a
suspicion. Report only real bugs: correctness, security/privacy, unmet acceptance criteria, crashes, data loss.
No style nits. Final message format: a numbered list, most severe first, each item
"N. [high|medium|low] path:line — summary. Scenario: …", at most 12 items, no preamble.
If there is nothing real, the final message is exactly: No real findings.
EOF
    # Called plainly (not in an || list) so set -e stays active inside run_codex.
    run_codex "$review_prompt" "$5" 'npm ci --no-audit --no-fund > /tmp/npm.log 2>&1 || { tail -20 /tmp/npm.log; echo "npm ci failed" >&2; exit 90; };
      codex exec --dangerously-bypass-approvals-and-sandbox -o /out/report.md - < /out/prompt.md'
    # A review must not change anything: same HEAD and refs (incl. the `main` baseline), and no tracked,
    # untracked or ignored changes except the node_modules from npm ci.
    changes=$(git -C "$wt" status --porcelain --untracked-files=all --ignored=matching | grep -v '^!! node_modules/$' || true)
    if [ "$(git -C "$wt" show-ref --head)" != "$refs" ] || [ -n "$changes" ]; then
      echo "Codex modified the clone during a review; discard its findings and rerun." >&2; exit 1
    fi
    ;;
  collect)
    b=$(git -C "$wt" branch --show-current)
    [ "$(git -C "$repo" branch --show-current)" = "$b" ] || { echo "checkout is not on $b; switch to it first" >&2; exit 1; }
    git -C "$wt" add -A
    git -C "$wt" diff --cached --quiet && { echo "no changes from Codex"; exit 0; }
    git -C "$wt" -c user.name="$(git -C "$repo" config user.name)" -c user.email="$(git -C "$repo" config user.email)" \
      commit -q -m "$3"
    git -C "$repo" fetch -q "$wt" HEAD
    git -C "$repo" merge -q --ff-only FETCH_HEAD
    git -C "$repo" log --oneline -1
    ;;
  *) echo "usage: see header" >&2; exit 2 ;;
esac
