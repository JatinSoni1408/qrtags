# Secret management

## Firebase config files
- Required files (now gitignored): `ios/Runner/GoogleService-Info.plist` and `android/app/google-services.json`.
- Use the `.example` files in the same folders as templates; copy and fill the placeholders with the values from Firebase Console → Project Settings → Your apps.
  - iOS bundle id: `com.example.shubhamJewellers`
  - Android package: `com.example.shubham_jewellers` (add SHA-1/SHA-256 when restricting the key).

## Local development
```bash
cp ios/Runner/GoogleService-Info.plist.example ios/Runner/GoogleService-Info.plist
cp android/app/google-services.json.example android/app/google-services.json
# fill placeholders with real values (keep files untracked)
```

## CI/CD idea (GitHub Actions)
Store the real files as base64 secrets:
- `IOS_GOOGLE_SERVICE_INFO_PLIST_B64`
- `ANDROID_GOOGLE_SERVICES_JSON_B64`

Then in the workflow:
```bash
echo "$IOS_GOOGLE_SERVICE_INFO_PLIST_B64" | base64 -d > ios/Runner/GoogleService-Info.plist
echo "$ANDROID_GOOGLE_SERVICES_JSON_B64" | base64 -d > android/app/google-services.json
```

## API key restrictions (must do after rotation)
- Android key: restrict to package `com.example.shubham_jewellers` and your release/debug SHA-1/SHA-256 fingerprints.
- iOS key: restrict to the Runner bundle ID from Xcode and (optionally) an App Store ID once published.
- Scope-limit the key to only the Google APIs actually used.

## History rewrite summary
- Repository history was scrubbed to replace the exposed keys with `[REDACTED_GOOGLE_API_KEY]`.
- Backup before rewrite: `backup/pre-secret-purge-2026-03-15`.
- After verifying locally, force-push the rewritten `main` (e.g., `git push --force-with-lease origin main`) and ask collaborators to re-clone or hard reset to the new history.
