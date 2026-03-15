# Notification Feature - Complete Current Implementation Analysis

Date: 2026-03-15
Workspace: new_reward

## 1. High-Level Architecture

The notification system is implemented as a hybrid of:

1. Flutter client-side listeners and local notification display.
2. Cloudflare Worker push orchestration.
3. Firebase Cloud Messaging (FCM) for device push.
4. Firestore `notifications` collection for in-app notification center.

Primary flow:

`feature event in app -> CloudflareNotificationService -> Cloudflare Worker (/notify) -> Firestore notification doc + FCM push -> app receives -> tap routing`

There are also client-side save paths that write notification docs from incoming FCM data.

## 2. Core Files and Responsibilities

### Client

- `lib/main.dart`
- `lib/services/notification_service.dart`
- `lib/services/cloudflare_notification_service.dart`
- `lib/screens/notifications/notifications_screen.dart`
- `lib/models/notification_model.dart`
- `lib/routes/app_router.dart`

### Feature Trigger Sources

- `lib/services/parent_teacher_group_service.dart`
- `lib/services/community_service.dart`
- `lib/services/firebase_message_sync_service.dart`
- `lib/services/firestore_service.dart` (test assignment)
- `lib/services/parent_service.dart` (reward status)
- `lib/services/pending_announcement_service.dart` (announcements)
- `lib/services/chat_service.dart` (direct chat currently disabled)

### Backend Push Worker

- `cloudflare-worker/src/notification-worker.ts`
- `cloudflare-worker/wrangler-notification.jsonc`

## 3. Initialization and Runtime Listeners

## 3.1 App startup

In `lib/main.dart`:

1. Firebase initialized.
2. `FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)` registered.
3. Asynchronous services initialized via `_initializeServicesAsync()`, including `NotificationService().initialize()`.
4. Root widget subscribes to `NotificationService().notificationTapStream` and routes using `deepLinkRoute`.

Tap handling in root:

- Reads `payload['deepLinkRoute']`.
- Falls back to `/notifications` if missing.
- `navigator.pushNamed(targetRoute, arguments: payload)`.

## 3.2 NotificationService setup

In `lib/services/notification_service.dart`, `initialize()` does:

1. Requests notification permission.
2. Initializes Flutter local notifications plugin.
3. Creates Android channels:
- `lenv_high_priority`
- `lenv_default`
- `lenv_silent`
4. Initializes FCM token and token refresh listener.
5. Registers message listeners:
- `FirebaseMessaging.onMessage`
- `FirebaseMessaging.onMessageOpenedApp`
- `getInitialMessage()` for terminated-state open.

## 3.3 Token persistence

`saveTokenToFirestore(token)` updates:

1. `users/{uid}`:
- `fcmToken`
- `fcmTokenUpdatedAt`

2. `user_device_tokens/{uid_hash}`:
- `userId`
- `role`
- `schoolId`
- `deviceToken`
- `platform`
- `active`
- `lastUpdated`

Worker can use both user profile token and device token records.

## 4. Notification Push Entry Points (Where Functions Are Called)

## 4.1 Parent-Teacher Group message (primary live path)

Trigger:
- `ParentTeacherGroupService.sendMessage()` in `lib/services/parent_teacher_group_service.dart`

Call chain:

1. Writes message in `parent_teacher_groups/{groupId}/messages`.
2. Updates group last message metadata.
3. Adds sender to `memberIds` using `FieldValue.arrayUnion([senderId])`.
4. Resolves recipients locally via `_resolveNotificationRecipients(...)` (can be empty and still proceed).
5. Calls `CloudflareNotificationService.sendGroupMessageNotification(...)` with:
- `type: group_message`
- `groupType: parent_teacher_group`
- `deepLinkRoute: /parent/section-group-chat`
- metadata includes `className`, `section`, `schoolCode`, `groupName`.

Notes:
- If local recipients are empty, worker-side recipient resolution is expected.

## 4.2 Parent-Teacher Group message (offline sync path)

Trigger:
- `FirebaseMessageSyncService.sendMessage(...)` with `chatType == 'parent_group'`

Call chain:

1. Writes message to Firebase and local DB.
2. Calls `_notifyParentGroupMessage(...)`.
3. Resolves recipients from group members or fallback filters.
4. Calls `CloudflareNotificationService.sendGroupMessageNotification(...)` with:
- `groupType: parent_teacher_group`
- `deepLinkRoute: /parent/section-group-chat`
- metadata includes `className`, `section`, `schoolCode`, `groupName`.

## 4.3 Community message (primary live path)

Trigger:
- `CommunityService.sendMessage(...)` in `lib/services/community_service.dart`

Call chain:

1. Writes community message.
2. Updates community last-message fields.
3. Reads community doc to capture `name` and `icon`.
4. Resolves active member recipients (excluding sender).
5. Calls `CloudflareNotificationService.sendGroupMessageNotification(...)` with:
- `groupType: community`
- `deepLinkRoute: /community-group-chat`
- metadata includes `communityId`, `replyToId`, `groupName`, `communityIcon`.

## 4.4 Community message (offline sync path)

Trigger:
- `FirebaseMessageSyncService.sendMessage(...)` with `chatType == 'community'`

Call chain:

1. Writes message.
2. `_notifyCommunityMessage(...)` fetches community info and members.
3. Calls `CloudflareNotificationService.sendGroupMessageNotification(...)` with:
- `groupType: community`
- `deepLinkRoute: /community-group-chat`
- metadata includes `communityId`, `groupName`, `communityIcon`.

## 4.5 Test assignment notification

Trigger:
- `FirestoreService.assignTestToClass(...)` in `lib/services/firestore_service.dart`

Call chain:

1. Creates assignment docs and updates user counters.
2. Calls `CloudflareNotificationService.sendTestAssignmentNotification(...)` with:
- `type: test_assignment`
- `deepLinkRoute: /student-tests`
- metadata includes start time and date.

## 4.6 Reward status notification

Trigger:
- `ParentService.updateRewardRequestStatus(...)` in `lib/services/parent_service.dart`

Call chain:

1. Updates reward request document.
2. Calls `CloudflareNotificationService.sendRewardStatusNotification(...)`.
3. Worker default deep link for reward type is `/student-rewards` unless overridden.

## 4.7 Announcement notification

Trigger:
- `PendingAnnouncementService` queue flush in `lib/services/pending_announcement_service.dart`

Call chain:

1. Saves announcement document in selected collection.
2. Calls `CloudflareNotificationService.sendAudienceAnnouncementNotification(...)`.
3. Worker resolves recipients by school and audience filtering.
4. Worker default deep link is `/notifications` unless request provides one.

## 4.8 Direct chat notification status

- `CloudflareNotificationService.sendDirectChatNotification(...)` exists.
- Worker supports `type: direct_chat`.
- Current app call path is disabled in `lib/services/chat_service.dart` (comment: direct teacher-parent notifications are disabled).
- So direct push is currently implemented in backend/client service surface but not actively triggered by chat service.

## 5. Cloudflare Worker Implementation (Push + Firestore Write)

Worker endpoint:
- `POST /notify`
- File: `cloudflare-worker/src/notification-worker.ts`

Supported payload `type` values:

1. `chat` / `direct_chat` -> `handleDirectChat`
2. `group_message` -> `handleGroupMessage`
3. `reward_status` -> `handleRewardStatus`
4. `assignment` / `test_assignment` -> `handleTestAssignment`
5. `announcement` -> `handleAnnouncement`

## 5.1 Common worker behavior

For all major handlers, worker sends through `sendNotificationToUser(...)` (or fast variant) which:

1. Builds deterministic notification ID (`buildNotificationId`).
2. Writes Firestore `notifications/{notificationId}`.
3. Finds active device tokens (profile token + `user_device_tokens`).
4. Sends FCM HTTP v1 message to each token.

If token is invalid/unregistered, worker deactivates token.

## 5.2 Parent-teacher group fast path

For `groupType == parent_teacher_group` in `handleGroupMessage`:

1. Uses `resolveParentTeacherRecipients(...)` returning recipient profile data (with `fcmToken`).
2. Uses `sendFastGroupNotification(...)` (2 subrequests per recipient: Firestore write + FCM send).

Resolution strategy:

1. Try explicit group members (`memberIds`, `members`, `participants`, `userIds`).
2. Fallback query by school code variants from parsed scope.
3. Filter roles to parent/teacher.
4. Keep recipients with valid `fcmToken`.
5. Cap to safety limit (`MAX_FAST_RECIPIENTS = 20`) to avoid Cloudflare subrequest limits.

## 5.3 Community and other groups standard path

For non parent-teacher `group_message`:

1. Uses provided `recipientIds`.
2. Calls `sendNotificationToUser` per recipient.
3. Deep link defaults to `/notifications` if request omits deep link.

## 6. In-App Notification Storage Model

Primary collection:
- `notifications`

Typical fields written by worker:

- `notificationId`
- `userId`
- `role`
- `schoolId`
- `category`
- `title`
- `body`
- `iconType`
- `priority`
- `soundEnabled`
- `vibrationEnabled`
- `isRead`
- `createdAt`
- `timestamp`
- `targetType`
- `targetId`
- `referenceId`
- `deepLinkRoute`
- `metadata`
- `data`
- `dedupeKey`

Client model parser:
- `NotificationModel.fromFirestore(...)` in `lib/models/notification_model.dart`.

Compatibility behavior:
- `targetId` may fallback from `referenceId`.
- `deepLinkRoute` may fallback from `metadata.deepLinkRoute`.

## 7. Client Receive and Tap Navigation

## 7.1 FCM receive paths

In `NotificationService`:

1. Foreground: `onMessage` -> save Firestore notification -> show local notification.
2. Background open: `onMessageOpenedApp` -> emit tap stream with `message.data`.
3. Terminated open: `getInitialMessage()` -> emit tap stream.
4. Local-notification tap: decode payload JSON -> emit tap stream.

## 7.2 App-level tap routing

`main.dart` listens to `notificationTapStream`:

1. Reads `deepLinkRoute` from payload.
2. If absent, route `/notifications`.
3. Pushes named route with full payload as arguments.

## 7.3 Notification center tap routing

In `NotificationsScreen._handleNotificationTap(...)`:

1. Marks notification as read.
2. If notification has `deepLinkRoute`, pushes named route with `notification.metadata`.
3. If no deep link, category fallback routing:
- messaging -> `/messages`
- tests/academic -> `/student-tests`
- rewards -> `/student-rewards`
- announcements/alerts/general -> stays in notifications screen.

## 8. Deep Link Mapping (Current)

Configured in current trigger calls:

1. Parent-teacher group messages -> `/parent/section-group-chat`
2. Community messages -> `/community-group-chat`
3. Test assignment -> `/student-tests`

Worker defaults (if caller did not pass deepLinkRoute):

1. direct chat -> `/messages`
2. group message -> `/notifications`
3. reward status -> `/student-rewards`
4. test assignment -> `/student-tests`
5. announcement -> `/notifications`

## 9. Router Support (Current)

In `lib/routes/app_router.dart`:

1. `/parent/section-group-chat` exists and constructs `ParentGroupChatPage`.
2. `/community-group-chat` exists and constructs `CommunityChatPage` with:
- `communityId` from `communityId` or `targetId`
- `communityName` from `groupName` or `communityName`
- `communityIcon` from `communityIcon` default `🌐`
3. `/notifications` exists.

This supports direct open from notification taps when payload includes required fields.

## 10. Function-Level Call Graphs (Condensed)

## 10.1 Parent-group push

`ParentTeacherGroupService.sendMessage`
-> `_resolveNotificationRecipients`
-> `CloudflareNotificationService.sendGroupMessageNotification`
-> Worker `handleGroupMessage`
-> `resolveParentTeacherRecipients` (if needed)
-> `sendFastGroupNotification`
-> Firestore `notifications` + FCM

## 10.2 Community push

`CommunityService.sendMessage`
-> `CloudflareNotificationService.sendGroupMessageNotification`
-> Worker `handleGroupMessage`
-> `sendNotificationToUser`
-> Firestore `notifications` + FCM

## 10.3 Test assignment push

`FirestoreService.assignTestToClass`
-> `CloudflareNotificationService.sendTestAssignmentNotification`
-> Worker `handleTestAssignment`
-> `sendNotificationToUser`

## 10.4 Reward status push

`ParentService.updateRewardRequestStatus`
-> `CloudflareNotificationService.sendRewardStatusNotification`
-> Worker `handleRewardStatus`
-> `sendNotificationToUser`

## 10.5 Announcement push

`PendingAnnouncementService.flush...`
-> `CloudflareNotificationService.sendAudienceAnnouncementNotification`
-> Worker `handleAnnouncement`
-> `getAnnouncementRecipients`
-> `sendNotificationToUser`

## 11. Current Behavior Notes

1. Direct teacher-parent chat push is intentionally disabled in `chat_service.dart`.
2. Parent-teacher group recipient resolution has dual strategy (group member list first, school fallback).
3. Worker writes notification docs even for push delivery path; client also writes from incoming FCM data in some receive modes, using merge semantics.
4. Notification bell/unread count uses stream from `NotificationService.unreadCountStream()` querying Firestore `notifications` by `userId` and `isRead`.

## 12. End-to-End Example: Parent-Teacher Message Tap

1. Parent sends message in parent-teacher group.
2. Service posts to worker with `deepLinkRoute: /parent/section-group-chat` and group metadata.
3. Worker resolves recipients, writes `notifications/{id}`, sends FCM.
4. Recipient taps push.
5. App receives payload and `main.dart` pushes `/parent/section-group-chat` with payload args.
6. Router opens `ParentGroupChatPage` for the target group.

---

This document reflects the current implementation in the repository as of 2026-03-15.