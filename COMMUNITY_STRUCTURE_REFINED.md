# Community Feature - Refined Firebase Structure
**Based on Current Implementation**

---

## ✅ Current Firebase Structure Analysis

Your current structure is **GOOD** but needs a few refinements for the student exploration feature to work properly.

### Current Structure:
```json
{
  "name": "neet",
  "purpose": "neet aspirants",
  "slug": "neet",
  "standards": ["Grade 9", "Grade 10"],
  "audienceRoles": ["student"],
  "schoolCode": "",
  "schoolScope": "global",
  "visibility": "public",
  "joinMode": "open",
  "isActive": true,
  "memberCount": 0,
  "createdAt": Timestamp,
  "createdBy": "URW6w7CuGiMKopQlCqqMOTiKvji1"
}
```

---

## 🔧 Required Adjustments

### 1. **Add Missing Fields for Better Functionality**

```json
{
  // ✅ Already Present - Keep These
  "name": "neet",
  "purpose": "neet aspirants",
  "slug": "neet",
  "standards": ["Grade 9", "Grade 10"],
  "audienceRoles": ["student"],
  "schoolCode": "",
  "schoolScope": "global",
  "visibility": "public",
  "joinMode": "open",
  "isActive": true,
  "memberCount": 0,
  "createdAt": Timestamp,
  "createdBy": "URW6w7CuGiMKopQlCqqMOTiKvji1",
  
  // ➕ ADD THESE for Better Features
  "createdByName": "Teacher Name",        // For displaying creator
  "createdByRole": "student" | "teacher", // For filtering by creator type
  "avatarUrl": "",                        // Community icon/logo
  "coverImage": "",                       // Banner image
  "description": "neet aspirants",        // Detailed description (can be same as purpose)
  "category": "academic",                 // academic, sports, arts, technology, general
  "tags": ["neet", "medical", "exam"],    // For search functionality
  
  // Message tracking (optional but recommended)
  "messageCount": 0,                      // Total messages
  "lastMessageAt": null,                  // Last message timestamp
  "lastMessagePreview": "",               // Preview text
  "lastMessageBy": "",                    // Last message sender name
  
  // Moderation (optional)
  "moderators": [],                       // Array of moderator UIDs
  "rules": "Be respectful and helpful",   // Community rules
  "maxMembers": 500,                      // Optional member limit
  
  "updatedAt": Timestamp                  // Track updates
}
```

---

## 📊 Complete Collections Structure

### 1. **communities** Collection ✅
```
communities/{communityId}
```
**Document fields:** (as shown above)

---

### 2. **communities/{communityId}/members** Subcollection
```
communities/{communityId}/members/{userId}
```

**Purpose:** Track who joined each community

```json
{
  "userId": "student_uid",
  "userName": "Alice Smith",
  "userEmail": "alice@school.com",
  "userRole": "student",
  "userGrade": "Grade 9",
  "userSection": "A",
  "schoolCode": "SCH001",
  "avatarUrl": "",
  
  // Join Info
  "joinedAt": Timestamp,
  "status": "active",              // active, pending (for approval mode), banned
  "isModerator": false,
  
  // Activity
  "lastReadAt": Timestamp,
  "unreadCount": 0,
  "messageCount": 0,               // Messages sent by this user
  
  // Settings
  "muteNotifications": false,
  "favorited": false
}
```

**Why Subcollection?** 
- Easier to query members of a specific community
- Cleaner than a separate `community_members` collection
- Better performance for listing members

---

### 3. **communities/{communityId}/messages** Subcollection
```
communities/{communityId}/messages/{messageId}
```

**Purpose:** Store all messages in the community

```json
{
  "messageId": "auto-generated",
  
  // Sender
  "senderId": "user_uid",
  "senderName": "John Doe",
  "senderRole": "student",
  "senderAvatar": "https://...",
  
  // Content
  "type": "text",                  // text, image, file, poll, announcement
  "content": "Hello everyone!",
  "imageUrl": "",                  // For image messages
  "fileUrl": "",                   // For file attachments
  "fileName": "",
  
  // Metadata
  "createdAt": Timestamp,
  "updatedAt": Timestamp,
  "isEdited": false,
  "isDeleted": false,
  "isPinned": false,
  
  // Engagement
  "reactions": {                   // Map of reactions
    "👍": ["userId1", "userId2"],
    "❤️": ["userId3"]
  },
  "replyTo": "",                   // messageId if replying
  "replyCount": 0,
  
  // Moderation
  "isReported": false,
  "reportCount": 0
}
```

---

### 4. **user_communities/{userId}** Document (Optional but Recommended)
```
user_communities/{userId}
```

**Purpose:** Quick lookup of communities a user joined (for performance)

```json
{
  "userId": "student_uid",
  "communities": {
    "communityId1": {
      "name": "neet",
      "avatarUrl": "",
      "joinedAt": Timestamp,
      "unreadCount": 5,
      "lastReadAt": Timestamp,
      "isFavorite": false,
      "muteNotifications": false
    }
  },
  "totalCommunities": 1,
  "updatedAt": Timestamp
}
```

---

## 🔍 Query Examples for Student Exploration

### **Filter 1: Explore Communities (Eligible Only)**

```dart
Future<List<CommunityModel>> getExploreCommunities(StudentModel student) async {
  // Extract student's grade
  final studentGrade = student.className; // e.g., "Grade 9 - A"
  
  Query query = FirebaseFirestore.instance
      .collection('communities')
      .where('isActive', isEqualTo: true)
      .where('visibility', isEqualTo: 'public')
      .where('audienceRoles', arrayContains: 'student');
  
  // Filter by school if community is school-specific
  if (student.schoolCode?.isNotEmpty ?? false) {
    query = query.where('schoolScope', whereIn: ['global', 'school']);
  }
  
  final snapshot = await query.get();
  
  // Client-side filtering for grade eligibility
  final communities = snapshot.docs
      .map((doc) => CommunityModel.fromFirestore(doc))
      .where((community) {
        // Check if student's grade is in standards array
        return community.standards.contains(studentGrade) ||
               community.standards.any((standard) => 
                 studentGrade.contains(standard));
      })
      .where((community) {
        // Exclude if student already joined
        return !_isAlreadyJoined(community.id, student.uid);
      })
      .toList();
  
  return communities;
}
```

**Note:** Firestore doesn't support complex array queries, so we filter grades client-side.

### **Filter 2: My Communities (Already Joined)**

```dart
Future<List<CommunityModel>> getMyCommunit(String userId) async {
  // Get all communities where user is a member
  final memberSnapshot = await FirebaseFirestore.instance
      .collectionGroup('members')
      .where('userId', isEqualTo: userId)
      .where('status', isEqualTo: 'active')
      .get();
  
  // Extract community IDs
  final communityIds = memberSnapshot.docs
      .map((doc) => doc.reference.parent.parent!.id)
      .toList();
  
  if (communityIds.isEmpty) return [];
  
  // Fetch community details
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
  
  // Sort by last message time
  communities.sort((a, b) => 
    (b.lastMessageAt ?? b.createdAt).compareTo(a.lastMessageAt ?? a.createdAt));
  
  return communities;
}
```

---

## 🔐 Security Rules (Critical!)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper functions
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function getUserData() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data;
    }
    
    function extractGrade(className) {
      // Extract "Grade 9" from "Grade 9 - A"
      return className.split(' - ')[0];
    }
    
    function isEligibleForCommunity(communityData) {
      let userData = getUserData();
      let userGrade = extractGrade(userData.className);
      
      // Check if user's role is allowed
      let roleAllowed = userData.role in communityData.audienceRoles;
      
      // Check if user's grade is in standards array
      let gradeAllowed = userGrade in communityData.standards ||
                         userData.className in communityData.standards;
      
      // Check school scope
      let schoolAllowed = communityData.schoolScope == 'global' ||
                         (communityData.schoolScope == 'school' && 
                          userData.schoolCode == communityData.schoolCode);
      
      return roleAllowed && gradeAllowed && schoolAllowed && 
             communityData.isActive;
    }
    
    function isMember(communityId) {
      return exists(/databases/$(database)/documents/communities/$(communityId)/members/$(request.auth.uid)) &&
             get(/databases/$(database)/documents/communities/$(communityId)/members/$(request.auth.uid)).data.status == 'active';
    }
    
    function isModerator(communityId) {
      let memberData = get(/databases/$(database)/documents/communities/$(communityId)/members/$(request.auth.uid)).data;
      return memberData.isModerator == true;
    }
    
    // Communities
    match /communities/{communityId} {
      // Read: Only if eligible or already a member
      allow read: if isAuthenticated() && 
                    (isEligibleForCommunity(resource.data) || isMember(communityId));
      
      // Create: Anyone authenticated (students can create communities)
      allow create: if isAuthenticated();
      
      // Update: Only creator, moderators, or admins
      allow update: if isAuthenticated() && 
                      (resource.data.createdBy == request.auth.uid || 
                       isModerator(communityId) ||
                       getUserData().role == 'admin');
      
      // Delete: Only creator or admin
      allow delete: if isAuthenticated() && 
                      (resource.data.createdBy == request.auth.uid || 
                       getUserData().role == 'admin');
      
      // Members subcollection
      match /members/{userId} {
        // Read: If you're a member or it's your own membership
        allow read: if isAuthenticated() && 
                      (isMember(communityId) || request.auth.uid == userId);
        
        // Create: User joining (if eligible)
        allow create: if isAuthenticated() && 
                        request.auth.uid == userId &&
                        isEligibleForCommunity(get(/databases/$(database)/documents/communities/$(communityId)).data);
        
        // Update: Own settings or moderator
        allow update: if isAuthenticated() && 
                        (request.auth.uid == userId || isModerator(communityId));
        
        // Delete: Leave community
        allow delete: if isAuthenticated() && 
                        (request.auth.uid == userId || isModerator(communityId));
      }
      
      // Messages subcollection
      match /messages/{messageId} {
        // Read: Only members
        allow read: if isAuthenticated() && isMember(communityId);
        
        // Create: Only members
        allow create: if isAuthenticated() && 
                        isMember(communityId) &&
                        request.auth.uid == request.resource.data.senderId;
        
        // Update/Delete: Own messages or moderators
        allow update, delete: if isAuthenticated() && 
                                (resource.data.senderId == request.auth.uid || 
                                 isModerator(communityId));
      }
    }
    
    // User communities lookup
    match /user_communities/{userId} {
      allow read, write: if isAuthenticated() && request.auth.uid == userId;
    }
  }
}
```

---

## ✅ Summary: Is Your Structure Enough?

### **What You Have:** ✅
- ✅ `name`, `purpose`, `slug`
- ✅ `standards` (for grade filtering)
- ✅ `audienceRoles` (for role filtering)
- ✅ `schoolCode`, `schoolScope` (for school filtering)
- ✅ `visibility`, `joinMode`
- ✅ `isActive`, `memberCount`
- ✅ `createdAt`, `createdBy`

### **What's Missing:** ⚠️
- ⚠️ `createdByName` & `createdByRole` - for display
- ⚠️ `avatarUrl` & `coverImage` - for UI
- ⚠️ `description` - longer text
- ⚠️ `category` & `tags` - for search/filtering
- ⚠️ `lastMessageAt`, `lastMessagePreview`, `lastMessageBy` - for activity feed
- ⚠️ `moderators` array - for moderation
- ⚠️ `updatedAt` - track changes
- ⚠️ **Subcollections:** `members` and `messages`

### **Recommendation:**
Your current structure is **80% complete**. You can start with it, but add:
1. **Required NOW:** `members` and `messages` subcollections
2. **Add Soon:** `createdByName`, `avatarUrl`, `description`, `lastMessageAt`
3. **Add Later:** `category`, `tags`, `moderators`, `rules`

---

## 🚀 Next Steps

1. **Update existing communities** to add missing fields
2. **Create Models** - `CommunityModel`, `MemberModel`, `MessageModel`
3. **Create Service** - `CommunityService` with queries
4. **Build UI** - Community list, Explore screen, Chat screen
5. **Deploy Security Rules** - Protect data access

Ready to proceed with implementation?
