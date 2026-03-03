# App Maintenance Steps

## Current baseline
- Tags Firestore operations are centralized in `lib/data/tag_repository.dart`.
- Inventory page refresh strategy avoids unnecessary cross-list reads.
- No-op tag updates are skipped in Generate page.
- Firestore auth/role policy is enforced in `firestore.rules`.

## Next implementation steps
1. Move each page into feature folders:
   - `lib/features/inventory/...`
   - `lib/features/tags/...`
   - `lib/features/old/...`
2. Keep UI files focused on rendering:
   - move Firestore and data-mapping logic into repositories/services.
3. Introduce typed models for tag records:
   - remove most raw `Map<String, dynamic>` usage from UI.
4. Add test coverage:
   - unit tests for weight/amount and old-item formulas.
   - widget tests for inventory list mode switching and actions.
5. Add lightweight CI:
   - run `flutter analyze` and tests on push/PR.

## Firebase cost guardrails
- Never write to Firestore during read loops.
- Refresh only visible list screens unless a full sync is required.
- Skip no-op updates.
- Use pagination for large list exports.
- Prefer batch writes for bulk state transitions.

## Security guardrails
- Do not persist passwords in local storage.
- Keep self signup restricted to staff users.
- Never auto-assign admin in client code.
- Grant admin role only through protected Firestore writes.

## Firestore index note
- Pending list pagination now uses:
  - `where('inventoryPending', isEqualTo: true)`
  - `orderBy('createdAt', descending: true)`
- Ensure this composite index exists in Firestore for production.
