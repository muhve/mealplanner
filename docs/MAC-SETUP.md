# Build and release Meal Planner on a Mac

The app is now native SwiftUI for iPhone, iOS 17 or later. `MealPlannerCore` contains Foundation-only logic and tests that run on Linux. The SwiftUI target requires Xcode and the iOS SDK; Linux CI does not compile it.

## 1. Install the tools

1. Install Xcode from the Mac App Store. Launch it, accept the license and install its requested components and an iOS simulator runtime.
2. In Xcode → Settings → Locations, select the installed Xcode under Command Line Tools. If needed, run `xcode-select --install` in Terminal. If Terminal still points to standalone tools, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
3. Install Homebrew from brew.sh if needed, then run `brew install xcodegen`.
4. Clone this repository and open Terminal at its root. Run:
   ```sh
   xcodegen generate
   open MealPlanner.xcodeproj
   ```
   The generated project is ignored by git. Change project settings in `project.yml` and regenerate; settings edited only in Xcode will be lost. The local package is at `MealPlannerCore/`; no external packages are needed.
5. Verify Core separately with `cd MealPlannerCore && swift build && swift test`.

## 2. Configure signing

1. Xcode → Settings → Accounts → add your Apple ID, with access to team `4X292LGV9D` and App Store Connect.
2. Open target MealPlanner → Signing & Capabilities. Use Automatically manage signing, team `4X292LGV9D`, bundle ID `fi.muhve.mealplanner`. Do not change the bundle ID: the existing installation's container and App Store listing depend on it.
3. Select the MealPlanner scheme and an iPhone simulator, then Product → Run (⌘R). Check both light and dark appearances, Dynamic Type and the keyboard in forms. Send simulator screenshots to Claude for review; Claude cannot capture them in Linux.

## 3. Run on your iPhone

1. Connect the iPhone to the Mac, unlock it and trust the computer.
2. On the phone enable Settings → Privacy & Security → Developer Mode, and restart/confirm if requested.
3. Select the iPhone as Xcode's run destination, let Xcode register it and prepare device support, then Run. Trust the development certificate in device settings if requested.
4. Exercise dishes (create/search/edit/delete), ingredient suggestions and validation; repeated meals and aggregation; quantity edit/reset; check and On jo with undo; extras; remove/restore; archive and history. Relaunch to verify persistence. Send screenshots of the resulting screens in light and dark mode.

## 4. Verify the first update preserves Expo data

Do this on a test phone with real or representative saved Expo data before release. **Do not uninstall the Expo build**: deleting it deletes its container. Record its dishes, current list, marks, extras and history. Install the Swift build as an update using the same bundle ID and signing team (prefer the TestFlight upgrade path). Verify every recorded value and relaunch to check that the imported data persists. Do not depend solely on a fresh simulator install.

On first launch without a Swift document, the app reads expo-sqlite kv-store's default database:

- `<app container>/Documents/SQLite/ExpoSQLiteStorage` — **verify on device**. This expected path must be confirmed against the actual shipped Expo build's container, including any SQLite WAL sidecars. Use Xcode → Devices and Simulators → device → app → Download Container where available, or inspect an authorized development build/container on the device.
- SQLite query: `SELECT value FROM storage WHERE key = ?`, binding `ruokalista-v1`. The existing database is opened read/write without CREATE so SQLite can recover WAL sidecars when `-shm` is missing. The reader executes only SELECT statements and never writes application data, creates a database or deletes the file.
- New location: `<app container>/Library/Application Support/MealPlanner/ruokalista-v1.json`. The JSON document shape and millisecond timestamps remain compatible with Expo. Writes are atomic.
- Existing Swift data always wins. Migration reads the legacy value only when the Swift document is absent. A missing database file, missing `storage` table or absent key establishes a fresh Swift document. SQLite corruption (`SQLITE_CORRUPT` / `SQLITE_NOTADB`, including extended codes) also starts empty and saves the Swift document: nothing is imported, and the untouched legacy database remains on the phone as the backup. Other SQLite failures (busy, I/O, permissions, etc.) stop loading without saving a Swift document, show “Tietojen lataaminen epäonnistui.” / “Yritä uudelleen” and retry migration on the next attempt or launch. **Confirm the legacy database path before releasing**: a wrong path still looks like no legacy database. To retry a failed migration during development, back up the container and remove only the new Swift document before relaunching; never delete the Expo database or uninstall the app.
- The load-failed screen also offers “Jatka ilman vanhoja tietoja”. A Finnish confirmation explains that old data stays on the phone but is not imported. Confirming bypasses legacy import, saves an empty Swift document before opening the app, and prevents subsequent migration attempts. Cancelling changes nothing. The legacy database is never deleted; an existing Swift document still takes precedence and retains the normal backup/recovery safeguards. If saving fails, the load-failed screen stays visible.
- An unreadable JSON value is backed up unchanged as `ruokalista-v1-backup-<milliseconds>.json` alongside the Swift document before creating an empty state. Timestamp collisions increment by one. If backup or save fails, loading stays blocked with “Tietojen lataaminen epäonnistui.” / “Yritä uudelleen”. Normal edits also save before becoming visible.

## 5. Version and build numbers

Edit `project.yml` and run `xcodegen generate` again:

- `MARKETING_VERSION` is the public version, initially `1.0.0`. Choose a version accepted by the existing App Store Connect app (increase it if `1.0.0` was already released).
- `CURRENT_PROJECT_VERSION` is the upload build number, initially a placeholder `1`. **Before the first upload, increase it above the last Expo build in TestFlight.** Increase it for each later upload too, including fixes rejected during processing. EAS no longer maintains the counter.

## 6. Archive and upload to TestFlight

1. Ensure Core checks pass, review is clean and the developer has tested the app in Xcode and on a device. Regenerate the project after changing version/build numbers.
2. Select the MealPlanner scheme and a generic iOS device destination (“Any iOS Device (arm64)” or equivalent), not a simulator.
3. Product → Archive. Xcode creates a Release archive and opens Organizer.
4. Select the archive → Distribute App → App Store Connect → Upload. Keep automatic signing, validate, review the bundle ID/team/version/build, then upload.
5. Open App Store Connect → the existing Meal Planner app, app ID **6824632441** → TestFlight. Wait for processing; resolve any compliance or processing messages. Encryption is declared non-exempt encryption = NO, as in the Expo configuration.
6. Add testers/groups as appropriate; external testing may require beta review. Install the processed TestFlight build and verify it, especially an update over the Expo build. Uploading alone does not publicly release the app.

## 7. Release on the App Store

In App Store Connect, open the same existing app (6824632441), create/select the new iOS version, choose the processed build, fill What's New, screenshots and required metadata, then submit for App Review. After approval, release manually or use the release option selected on that version. Keep the archive and record its commit, version and build number. Releases remain a deliberate developer action.

## Troubleshooting

- **No signing profiles / wrong team:** check Xcode Accounts, team membership, automatic signing and the exact bundle ID. Let Xcode refresh profiles; check the Apple Developer agreements.
- **Device unavailable:** unlock/trust it, enable Developer Mode, install the matching iOS platform support in Xcode and check the deployment target is not newer than the phone.
- **Missing package or scheme:** open the generated project from this repository, ensure `MealPlannerCore/` exists beside `project.yml`, regenerate, then resolve packages in Xcode.
- **Build number already used:** increase `CURRENT_PROJECT_VERSION` in `project.yml`, regenerate and archive again.
- **SwiftUI compile failure:** send the exact Xcode error and file/line to Codex/Claude. Linux parses app syntax but cannot typecheck against SwiftUI/UIKit or validate signing and resources.
- **Empty list after upgrading:** stop making edits, back up the container, inspect the expected Expo path and its `storage` table/value, and check recovery backups before attempting a retry as described above. Do not uninstall.
- **Cannot load/save:** check available device storage and backups. Retrying a failed backup must succeed before empty state is published.

## What changed from Expo

No Metro, npm tooling, Expo Go, OTA updates, cloud builds, EAS credentials or deploy-on-merge workflow remain. Every change to the installed app requires a new Xcode build and upload. Xcode manages signing and local archives; TestFlight and App Store Connect handle distribution. GitHub CI builds/tests only Core on Linux. Merging a PR only merges the code; the developer builds, tests and releases from the Mac.

## iCloud sync

Regenerate with `xcodegen generate`. The target's XcodeGen `entitlements` properties generate `MealPlanner/MealPlanner.entitlements` and set `CODE_SIGN_ENTITLEMENTS`. Signing & Capabilities should show iCloud (CloudKit), container **iCloud.fi.muhve.mealplanner**, and Push Notifications. Automatic signing provisions the App ID capabilities and container when the team's permissions allow it. If either capability is absent, verify the entitlements/signing profile and enable it for App ID `fi.muhve.mealplanner` in the Apple Developer portal. Check the container exists and is associated with that App ID in the portal and CloudKit Console. Do not create a different container to work around signing errors.

Background delivery uses XcodeGen's supported `info.properties.UIBackgroundModes: [remote-notification]`. XcodeGen writes `MealPlanner/Info.plist` and sets `INFOPLIST_FILE`; Xcode merges this input with generated properties while `GENERATE_INFOPLIST_FILE: YES` remains enabled. This ensures the background modes value is a plist array. Verify the built app's Info.plist contains that array. The source entitlement is `aps-environment: development`; Xcode distribution signing uses the production push environment for App Store/TestFlight builds. Inspect the signed archive's entitlements before uploading. No notification permission prompt is needed for silent pushes.

1. Run a debug build signed into iCloud, create/edit sample dishes with photos, list items, extras and an archive. This creates the `dish`, `meal`, `item`, `extra`, `archivedTrip` and `trip` record types and their fields (`payload`, `modified`, `deletedAt`, and dish `photo` CKAsset) in the private database's custom `MealPlanner` zone. Include a deletion so `deletedAt` is created, and a photo so the asset field exists. CKSyncEngine manages subscriptions, change tokens and push handling; the app registers for remote notifications at launch.
2. **Before the first TestFlight build, deploy the CloudKit schema from Development to Production in CloudKit Console.** Debug builds use Development; TestFlight uses Production. Check every record type and field above appears in the deployment review, including `deletedAt` and `photo`. Deployment changes schema, not private user data. This is a manual developer action, never performed by this repository's scripts.
3. Install the same TestFlight build on two real devices signed into the same Apple ID with iCloud enabled for the app. Start with existing local data on one device and a fresh installation on the other. Confirm the existing library, instructions, photos and active trip appear on both, survive termination/relaunch, and do not duplicate. Also test bootstrapping distinct local dishes on both phones.
4. Keep both apps open. Edit different fields of one dish, then the same field; check the same and different shopping items; uncheck/reset; edit extras; replace/remove photos; delete a dish while editing it on the other phone. Archive while the other phone edits/adds meals. The archived trip's known records are tombstoned; concurrent additions tied to the old trip stay out of the new trip. Tombstones win over later edits. Check the next trip can check the same ingredients again.
5. Enable Airplane Mode on one phone, edit locally and terminate/relaunch. Reconnect and confirm queued changes upload. Sign out of iCloud and confirm local editing still works with “iCloud ei käytössä”; sign back in and confirm convergence. Local data is deliberately retained on sign-out; switching Apple IDs uploads the retained local library to the newly selected account. Test account changes separately with disposable accounts/data.
6. Check foreground refresh, silent-push delivery while open, Finnish status labels/error details, Dynamic Type, VoiceOver, and light/dark mode. Send simulator screenshots of the toolbar/status/error presentation for review. Push delivery and scheduling are controlled by iOS/CloudKit and cannot be guaranteed within a fixed number of seconds; measure real-device latency, including foreground after force-quit and Low Power Mode. No real-device or native SDK verification has been done in Linux.

To reset **Development only**, first back up any needed local app containers and stop test builds on all devices. In CloudKit Console select this exact container and Development environment, then use Reset Environment. This deletes development records/schema/subscriptions; never reset Production. Relaunch a debug build to recreate the zone and re-upload its retained local ledger (including tombstones). To start entirely clean, use disposable test installations/containers too: a server reset alone deliberately does not erase offline local data. Recreate representative records and redeploy schema before testing TestFlight again if schema changed.

Local UI data remains `ruokalista-v1.json`. `ruokalista-sync-v1.json` holds field timestamps, tombstones, pending names, CKRecord system fields, account identity and base64 CKSyncEngine state. A write-ahead transaction document repairs interrupted state/ledger writes on launch. Unreadable sync documents are backed up before replacement; an unreadable transaction blocks recovery rather than guessing. No tombstone garbage collection or physical server deletion is implemented.
