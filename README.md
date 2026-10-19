# Meal Planner

iOS app built with [Expo](https://expo.dev) (SDK 58) and Expo Router. Routes live in `src/app/`.

## Develop

```bash
npm ci
npx expo start          # dev server (press w for web)
npm run lint && npm run typecheck && npm test && npx expo-doctor
```

## How work flows

See `CLAUDE.md`: every change starts from a GitHub issue, is built on a `<n>-<slug>` branch (code by Codex in
`tools/codex/`, orchestrated by Claude) and lands through a PR into `main`. Merging to `main` deploys via
`.eas/workflows/deploy-production.yml` — an OTA update when the native fingerprint is unchanged, otherwise a new
build submitted to TestFlight.

Secrets live in an untracked `.env` (`GH_TOKEN`, `EXPO_TOKEN`).
