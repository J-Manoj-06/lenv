# Post-Rule Update Checklist (Manual Copy/Paste Path)

Do these steps now (post-rules update, after fresh `flutter run`).

## 1) Verify rules are live
- Confirm Rules tab shows latest publish timestamp.
- If unsure, run: `firebase deploy --only firestore:rules`.

## 2) Refresh auth token
- Sign out/in once so custom claims (role/admin) refresh.

## 3) Quick rule spot-checks (live data)
- Student: create reward request → expect success.
- Parent (linked): approve same request → status changes.
- Unrelated parent: attempt update → should be denied.
- Client write to `rewards_catalog` → should be denied.

## 4) App refresh already done
- You already reran `flutter run`; if perms look stale, kill and restart once more.

## 5) Cloud Functions
- If not deployed, run: `firebase deploy --only functions:rewards`.
- Check logs for PERMISSION_DENIED when functions write.

## 6) On-device happy path
- Student: catalog → create request → success.
- Parent: approve request → status updates.
- Delivery: confirm delivery → points release reflected on request doc.

## 7) Fast negative checks
- Student tries to update existing request → denied.
- Unrelated parent updates request → denied.
- Client writes to `rewards_catalog` → denied.
- Client updates `notifications` doc → denied.

## 8) Watch for denies
- Monitor Firestore usage; lots of denies = fix client flows.

## 9) Mirror to repo
- Keep `firebase/firestore.rules` in sync with what you pasted.

## 10) Ready-to-ship signal
- Rules live, claims good, spot-checks pass, functions clean → proceed to build/release.
