# qrtags

Flutter application for QR-based tag generation, scanning, inventory flow, and order workflows.

## Security Rules

Firestore rules are defined in [`firestore.rules`](firestore.rules) and wired in [`firebase.json`](firebase.json).

- Self-signup is staff-only.
- Admin role is never auto-assigned in app logic.
- Admin privileges must be granted explicitly in Firestore.
- `app_config`, `tags`, and `orders` writes are admin-only.

Deploy rules and indexes:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

## Free iOS Build from Windows (GitHub Actions)

This repo includes `.github/workflows/ios-build.yml` to build iOS on GitHub's free macOS runner.

What it does:
- Installs Flutter on a GitHub-hosted macOS runner.
- Runs `flutter pub get`.
- Builds an unsigned iOS app with `flutter build ios --debug --no-codesign`.
- Uploads `Runner.app` as a workflow artifact (`ios-runner-app`).

How to run:
1. Push this project to GitHub.
2. Open `Actions` tab in your repo.
3. Select `iOS Build (No Codesign)`.
4. Click `Run workflow`.
