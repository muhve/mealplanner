---
name: app-store-release
description: Use when promoting a TestFlight build to the public App Store, preparing App Store metadata/screenshots, or bumping the marketing version.
---

# Release to the App Store

Merges only reach TestFlight. Public release is a deliberate manual step.

1. Confirm the build: `eas build:list --platform ios --profile production --limit 3` and that it's processed in
   TestFlight (App Store Connect → TestFlight). Test it on a device.
2. Marketing version: `expo.version` in app.json (e.g. 1.0.0 → 1.1.0). Build numbers auto-increment remotely
   (`appVersionSource: remote`), don't touch them. Changing `version` changes the fingerprint ⇒ new native build,
   so bump it via a PR *before* the build you intend to release.
3. In App Store Connect → the app → "+ Version", select the build, fill "What's New", submit for review.
   (Optionally manage store metadata in-repo with `eas metadata:pull` / `eas metadata:push`.)
4. After approval, release (manual or automatic, as set on the version).
5. Tag it: `git tag v<version> <sha> && git push origin v<version>`, and create a GitHub release with notes
   from merged PRs: `gh release create v<version> --generate-notes`.
