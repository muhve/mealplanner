---
name: deploy
description: Use for anything about shipping the app - checking whether a merge deployed, OTA updates, TestFlight builds, forcing a native build, deploy failures, or rolling back a bad release.
---

# Deploy & rollback

Pipeline: merge to `main` → EAS Workflow `.eas/workflows/deploy-production.yml` (triggered by the Expo GitHub app).
Fingerprint match → OTA update on `production` channel. No match → production build + TestFlight submit.

Use `npx eas-cli@latest` (or `eas` if installed). Requires `eas login` or `EXPO_TOKEN`.

## Check status
- `eas workflow:runs` — recent runs; `eas workflow:view <id>`; `eas workflow:logs <id>` for failures.
- `eas update:list --branch production` — published OTA updates.
- `eas build:list --platform ios --limit 5` — native builds.

## Manually trigger
- Re-run the production pipeline from current checkout: `eas workflow:run .eas/workflows/deploy-production.yml`
- Hotfix OTA only (prefer the PR route): `eas update --branch production --platform ios --message "<msg>"`
- Force native build + TestFlight: `eas build -p ios --profile production --auto-submit`

## Roll back a bad OTA update
1. `eas update:list --branch production` to find the last good group.
2. `eas update:republish --group <good-group-id>` (or `eas update:rollback` interactively to go back to the
   build's embedded bundle).
3. Then fix forward with a revert PR so `main` matches what's live: `git revert <sha>` on a branch → PR.

A bad *native* build can't be rolled back on devices — expire it in TestFlight / don't release it, and ship a fix.

## Gotchas
- An OTA update only reaches installs whose runtime (fingerprint) matches. Users on an older native build won't
  get JS-only changes until they install the newer build.
- The first-ever merge will always do a native build (no build exists for the fingerprint yet).
- Validate workflow edits with `eas workflow:validate .eas/workflows/<file>.yml` before merging.
