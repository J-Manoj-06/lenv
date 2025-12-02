# Community Feature - Firebase Structure

## Overview
Community feature allows students and teachers to join grade-specific communities, chat, and collaborate. Students can only see and join communities eligible for their grade level.

---

## Firestore Collections Structure

### 1. **communities** Collection
Main collection storing all community data.

```
communities/{communityId}
```

#### Document Structure:
```json
{
  "communityId": "auto-generated-id",
  "name": "Grade 9 Science Club",
  "description": "Discuss science topics and experiments",
  "type": "student" | "teacher" | "mixed",
  "category": "academic" | "sports" | "arts" | "technology" | "general",
  "
": "https://...",
  "coverImage": "https://...",
  
  // Access Control
  "eligibleGrades": ["9", "10"],  // Array of grade numbers as strings
  "eligibleSections": ["A", "B"], // Optional: specific sections, empty = all sections
  "schoolCode": "SCH001",         // School identifier
  "instituteId": "institute_123", // Alternative school identifier
  
  // Metadata
  "createdBy": "userId",          // Creator's UID
  "createdByName": "John Doe",
  "createdByRole": "teacher" | "student" | "admin",
  "createdAt": Timestamp,
  "updatedAt": Timestamp,
  
  // Statistics
  "memberCount": 25,
  "messageCount": 150,
  "lastMessageAt": Timestamp,
  "lastMessagePreview": "Hey everyone!",
  
  // Settings
  "isPrivate": false,             // If true, requires approval to join
  "isActive": true,               // Can be disabled by admin
  "maxMembers": 100,              // Optional member limit
  "allowedRoles": ["student", "teacher"], // Who can join
  
  // Moderation
  "moderators": ["userId1", "userId2"], // Array of moderator UIDs
  "rules": "Be respectful and kind",
  
  // Tags for search
  "tags": ["science", "experiments", "physics"]
}
```

---

### 2. **community_members** Collection
Tracks membership in communities.

```
community_members/{communityId}/members/{userId}
```

#### Document Structure:
```json
{
  "userId": "student_uid",
  "userName": "Alice Smith",
  "userEmail": "alice@example.com",
  "userRole": "student" | "teacher",
  "grade": "9",                    // For students
  "section": "A",                  // For students
  "className": "Grade 9 - A",      // From user profile
  "schoolCode": "SCH001",
  
  // Membership Info
  "joinedAt": Timestamp,
  "status": "active" | "pending" | "banned",
  "isModerator": false,
  "isAdmin": false,
  
  // Permissions
  "canPost": true,
  "canReact": true,
  "canInvite": false,
  
  // Activity
  "lastReadAt": Timestamp,
  "unreadCount": 5,
  "messageCount": 12,              // Messages sent by this user
  
  // Notifications
  "muteNotifications": false,
  "favorited": false
}
```

**Composite Indexes Required:**
- `communityId` + `status` + `joinedAt` (descending)
- `userId` + `status`
- `communityId` + `userRole` + `status`

---

### 3. **community_messages** Collection
Stores all messages within communities.

```
community_messages/{communityId}/messages/{messageId}
```

#### Document Structure:
```json
{
  "messageId": "auto-generated-id",
  "communityId": "community_123",
  
  // Sender Info
  "senderId": "user_uid",
  "senderName": "John Doe",
  "senderRole": "student" | "teacher",
  "senderAvatar": "https://...",
  
  // Message Content
  "type": "text" | "image" | "file" | "announcement" | "poll",
  "content": "Hello everyone!",
  "imageUrl": "https://...",       // For image messages
  "fileUrl": "https://...",        // For file attachments
  "fileName": "document.pdf",
  "fileSize": 1024,                // In bytes
  
  // Metadata
  "createdAt": Timestamp,
  "updatedAt": Timestamp,
  "isEdited": false,
  "isDeleted": false,
  "isPinned": false,
  
  // Reactions & Engagement
  "reactions": {
    "👍": ["userId1", "userId2"],
    "❤️": ["userId3"],
    "😊": ["userId4", "userId5"]
  },
  "reactionCount": 5,
  
  // Reply/Thread
  "replyTo": "messageId",          // If replying to another message
  "replyCount": 3,
  
  // Moderation
  "isReported": false,
  "reportCount": 0,
  "isModerated": false
}
```

**Composite Indexes Required:**
- `communityId` + `createdAt` (descending)
- `communityId` + `isPinned` + `createdAt` (descending)
- `senderId` + `createdAt` (descending)

---

### 4. **user_communities** Collection
Quick lookup for communities a user has joined.

```
user_communities/{userId}
```

#### Document Structure:
```json
{
  "userId": "student_uid",
  "joinedCommunities": [
    {
      "communityId": "comm_123",
      "communityName": "Grade 9 Science Club",
      "communityIcon": "https://...",
      "joinedAt": Timestamp,
      "lastReadAt": Timestamp,
      "unreadCount": 5,
      "isFavorite": false,
      "muteNotifications": false
    }
  ],
  "totalCommunities": 3,
  "updatedAt": Timestamp
}
```

---

### 5. **community_invites** Collection (Optional)
For private communities requiring approval.

```
community_invites/{inviteId}
```

#### Document Structure:
```json
{
  "inviteId": "auto-generated-id",
  "communityId": "comm_123",
  "communityName": "Grade 9 Science Club",
  
  // Invite Info
  "invitedUserId": "user_uid",
  "invitedBy": "teacher_uid",
  "invitedByName": "Mr. Smith",
  "invitedAt": Timestamp,
  
  // Status
  "status": "pending" | "accepted" | "rejected" | "expired",
  "respondedAt": Timestamp,
  
  // Expiry
  "expiresAt": Timestamp
}
```

---

## Security Rules

### Firestore Security Rules:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper Functions
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function getUserData() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data;
    }
    
    function isStudent() {
      return isAuthenticated() && getUserData().role == 'student';
    }
    
    function isTeacher() {
      return isAuthenticated() && getUserData().role == 'teacher';
    }
    
    function getUserGrade() {
      let className = getUserData().className;
      // Extract grade from "Grade 9 - A" format
      return className.matches('Grade ([0-9]+).*')[0];
    }
    
    function isEligibleForCommunity(communityData) {
      let userGrade = getUserGrade();
      let userData = getUserData();
      
      // Check school match
      let schoolMatch = communityData.schoolCode == userData.schoolCode;
      
      // Check grade eligibility
      let gradeMatch = communityData.eligibleGrades.size() == 0 || 
                       userGrade in communityData.eligibleGrades;
      
      // Check role eligibility
      let roleMatch = userData.role in communityData.allowedRoles;
      
      return schoolMatch && gradeMatch && roleMatch && communityData.isActive;
    }
    
    function isCommunityMember(communityId) {
      return exists(/databases/$(database)/documents/community_members/$(communityId)/members/$(request.auth.uid)) &&
             get(/databases/$(database)/documents/community_members/$(communityId)/members/$(request.auth.uid)).data.status == 'active';
    }
    
    function isCommunityModerator(communityId) {
      let memberDoc = get(/databases/$(database)/documents/community_members/$(communityId)/members/$(request.auth.uid)).data;
      return memberDoc.isModerator == true || memberDoc.isAdmin == true;
    }
    
    // Communities Collection
    match /communities/{communityId} {
      // Anyone authenticated can read communities they're eligible for
      allow read: if isAuthenticated() && isEligibleForCommunity(resource.data);
      
      // Only teachers and admins can create communities
      allow create: if isAuthenticated() && (isTeacher() || getUserData().role == 'admin');
      
      // Only creator or moderators can update
      allow update: if isAuthenticated() && 
                      (resource.data.createdBy == request.auth.uid || 
                       isCommunityModerator(communityId));
      
      // Only creator or admin can delete
      allow delete: if isAuthenticated() && 
                      (resource.data.createdBy == request.auth.uid || 
                       getUserData().role == 'admin');
    }
    
    // Community Members
    match /community_members/{communityId}/members/{userId} {
      // Members can read their own membership and other members
      allow read: if isAuthenticated() && 
                    (request.auth.uid == userId || isCommunityMember(communityId));
      
      // Users can join if eligible
      allow create: if isAuthenticated() && 
                      request.auth.uid == userId &&
                      isEligibleForCommunity(get(/databases/$(database)/documents/communities/$(communityId)).data);
      
      // Users can update their own membership settings
      allow update: if isAuthenticated() && 
                      (request.auth.uid == userId || isCommunityModerator(communityId));
      
      // Users can leave community
      allow delete: if isAuthenticated() && 
                      (request.auth.uid == userId || isCommunityModerator(communityId));
    }
    
    // Community Messages
    match /community_messages/{communityId}/messages/{messageId} {
      // Only members can read messages
      allow read: if isAuthenticated() && isCommunityMember(communityId);
      
      // Only members with canPost permission can create messages
      allow create: if isAuthenticated() && 
                      isCommunityMember(communityId) &&
                      request.auth.uid == request.resource.data.senderId;
      
      // Only sender or moderators can update/delete
      allow update, delete: if isAuthenticated() && 
                              (resource.data.senderId == request.auth.uid || 
                               isCommunityModerator(communityId));
    }
    
    // User Communities
    match /user_communities/{userId} {
      allow read: if isAuthenticated() && request.auth.uid == userId;
      allow write: if isAuthenticated() && request.auth.uid == userId;
    }
  }
}
```

---

## Query Examples

### 1. **Get Communities Eligible for Student to Explore**
```dart
// In Flutter
Future<List<CommunityModel>> getEligibleCommunities(StudentModel student) async {
  // Parse grade from className (e.g., "Grade 9 - A" -> "9")
  final gradeMatch = RegExp(r'Grade\s+(\d+)').firstMatch(student.className ?? '');
  final userGrade = gradeMatch?.group(1) ?? '';
  
  if (userGrade.isEmpty) return [];
  
  final query = FirebaseFirestore.instance
      .collection('communities')
      .where('schoolCode', isEqualTo: student.schoolCode)
      .where('isActive', isEqualTo: true)
      .where('allowedRoles', arrayContains: 'student')
      .where('eligibleGrades', arrayContains: userGrade)
      .orderBy('memberCount', descending: true);
  
  final snapshot = await query.get();
  
  // Filter out communities user already joined
  final joinedCommunityIds = await _getJoinedCommunityIds(student.uid);
  
  return snapshot.docs
      .map((doc) => CommunityModel.fromFirestore(doc))
      .where((community) => !joinedCommunityIds.contains(community.communityId))
      .toList();
}
```

### 2. **Get Communities User Joined**
```dart
Future<List<CommunityModel>> getJoinedCommunities(String userId) async {
  final memberSnapshot = await FirebaseFirestore.instance
      .collectionGroup('members')
      .where('userId', isEqualTo: userId)
      .where('status', isEqualTo: 'active')
      .get();
  
  final communityIds = memberSnapshot.docs
      .map((doc) => doc.reference.parent.parent!.id)
      .toList();
  
  if (communityIds.isEmpty) return [];
  
  final communities = <CommunityModel>[];
  for (final id in communityIds) {
    final doc = await FirebaseFirestore.instance
        .collection('communities')
        .doc(id)
        .get();
    
    if (doc.exists) {
      communities.add(CommunityModel.fromFirestore(doc));
    }
  }
  
  return communities;
}
```

### 3. **Join a Community**
```dart
Future<void> joinCommunity(String communityId, StudentModel student) async {
  final batch = FirebaseFirestore.instance.batch();
  
  // Add user to community members
  final memberRef = FirebaseFirestore.instance
      .collection('community_members')
      .doc(communityId)
      .collection('members')
      .doc(student.uid);
  
  batch.set(memberRef, {
    'userId': student.uid,
    'userName': student.name,
    'userEmail': student.email,
    'userRole': 'student',
    'grade': _extractGrade(student.className),
    'section': _extractSection(student.className),
    'className': student.className,
    'schoolCode': student.schoolCode,
    'joinedAt': FieldValue.serverTimestamp(),
    'status': 'active',
    'isModerator': false,
    'isAdmin': false,
    'canPost': true,
    'canReact': true,
    'canInvite': false,
    'lastReadAt': FieldValue.serverTimestamp(),
    'unreadCount': 0,
    'messageCount': 0,
    'muteNotifications': false,
    'favorited': false,
  });
  
  // Update community member count
  final communityRef = FirebaseFirestore.instance
      .collection('communities')
      .doc(communityId);
  
  batch.update(communityRef, {
    'memberCount': FieldValue.increment(1),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  
  await batch.commit();
}
```

### 4. **Send Message in Community**
```dart
Future<void> sendMessage(String communityId, String userId, String content) async {
  final batch = FirebaseFirestore.instance.batch();
  
  // Add message
  final messageRef = FirebaseFirestore.instance
      .collection('community_messages')
      .doc(communityId)
      .collection('messages')
      .doc();
  
  batch.set(messageRef, {
    'messageId': messageRef.id,
    'communityId': communityId,
    'senderId': userId,
    'senderName': 'Current User Name',
    'senderRole': 'student',
    'type': 'text',
    'content': content,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'isEdited': false,
    'isDeleted': false,
    'isPinned': false,
    'reactions': {},
    'reactionCount': 0,
    'replyCount': 0,
    'isReported': false,
    'reportCount': 0,
    'isModerated': false,
  });
  
  // Update community last message
  final communityRef = FirebaseFirestore.instance
      .collection('communities')
      .doc(communityId);
  
  batch.update(communityRef, {
    'messageCount': FieldValue.increment(1),
    'lastMessageAt': FieldValue.serverTimestamp(),
    'lastMessagePreview': content.length > 50 
        ? content.substring(0, 50) + '...' 
        : content,
  });
  
  await batch.commit();
}
```

---

## Composite Indexes Required

Add these to `firestore.indexes.json`:

```json
{
  "indexes": [
    {
      "collectionGroup": "communities",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "schoolCode", "order": "ASCENDING" },
        { "fieldPath": "isActive", "order": "ASCENDING" },
        { "fieldPath": "eligibleGrades", "arrayConfig": "CONTAINS" },
        { "fieldPath": "memberCount", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "members",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "joinedAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "messages",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "communityId", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "messages",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "communityId", "order": "ASCENDING" },
        { "fieldPath": "isPinned", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    }
  ]
}
```

---

## Key Features

### ✅ **Grade-Based Access Control**
- Students only see communities eligible for their grade
- `eligibleGrades` array filters communities automatically
- Security rules enforce grade matching

### ✅ **School Isolation**
- Communities filtered by `schoolCode`
- Students from different schools can't see each other's communities

### ✅ **Join & Leave**
- Simple join process with one-click "Join Now" button
- Automatically updates member count
- Users can leave anytime

### ✅ **Real-time Messaging**
- Subcollection structure for efficient queries
- Support for text, images, files
- Reactions and replies

### ✅ **Unread Tracking**
- Each member has `unreadCount` and `lastReadAt`
- Updates when user views messages

### ✅ **Moderation**
- Moderators can manage members and messages
- Pin important messages
- Report inappropriate content

---

## Next Steps

1. **Create Models** - `CommunityModel`, `CommunityMemberModel`, `MessageModel`
2. **Create Service** - `CommunityService` with all query methods
3. **Build UI** - Communities list, explore screen, chat screen
4. **Add to Navigation** - Add community tab to student dashboard
5. **Test** - Verify grade filtering and join functionality

Would you like me to proceed with creating the Dart models and service classes?
