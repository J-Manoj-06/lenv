# Poll Feature Integration Guide

## Overview
This guide explains how to integrate the new Poll feature into your existing Flutter chat app. The poll feature allows users to create and vote on polls in any chat (community, group, or individual).

## Files Created

### 1. Model
- `lib/models/poll_model.dart` - Poll data model with PollOption and PollModel classes

### 2. Service
- `lib/services/poll_service.dart` - Handles poll creation, voting, and real-time updates using Firestore transactions

### 3. Screens
- `lib/screens/create_poll_screen.dart` - UI for creating polls (2-6 options, single/multi-select)

### 4. Widgets
- `lib/widgets/poll_message_widget.dart` - Displays polls in chat with real-time voting and animated progress bars

## Integration Steps

### Step 1: Add Poll Button to Attachment Menu

Find the attachment menu in your chat screens and add a Poll option. The attachment menu is typically shown via `showModalBottomSheet`.

#### Example for Community Chat (community_chat_page.dart)

Locate the `_showAttachmentPicker()` method around line 535 and add this new option to the Row of attachment options:

```dart
void _showAttachmentPicker() {
  showModalBottomSheet(
    context: context,
    // ... existing code ...
    builder: (context) => Container(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // ... existing options (Gallery, Camera, Document, Audio) ...
              
              // ADD THIS NEW POLL OPTION:
              _buildAttachmentOption(
                icon: Icons.poll,
                label: 'Poll',
                color: primaryColor,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreatePollScreen(
                        chatId: widget.communityId, // or widget.chatId for other chat types
                        chatType: 'community', // or 'group', 'individual'
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
```

#### For Teacher Chat Screen (teacher/messages/chat_screen.dart)

Around line 362 in `_pickAttachmentSheet()`:

```dart
Future<void> _pickAttachmentSheet() async {
  showModalBottomSheet(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Wrap(
          children: [
            // ... existing ListTiles for Document, Gallery, Audio ...
            
            // ADD THIS NEW POLL OPTION:
            ListTile(
              leading: const Icon(Icons.poll),
              title: const Text('Poll'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreatePollScreen(
                      chatId: widget.groupId,
                      chatType: 'group', // or appropriate type
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    },
  );
}
```

### Step 2: Render Poll Messages in Chat

Find where messages are rendered in your chat screens. Look for the message builder or ListView.builder that displays messages.

Add this condition to detect and render poll messages:

```dart
// In your message builder (typically inside ListView.builder)
Widget _buildMessage(dynamic message) {
  // Check if message is a poll
  if (message['type'] == 'poll' || message.type == 'poll') {
    return PollMessageWidget(
      poll: PollModel.fromMap(
        message is Map ? message : message.toMap(),
        message['id'] ?? message.id,
      ),
      chatId: widget.chatId, // or widget.communityId, widget.groupId
      chatType: 'community', // or 'group', 'individual'
      isOwnMessage: message['senderId'] == currentUserId,
    );
  }
  
  // ... existing message type handling (text, image, file, etc.) ...
}
```

#### Example for Community Chat

In `community_chat_page.dart`, find the message building logic (around lines 1200-1500) and add:

```dart
// Inside the ListView.builder itemBuilder
if (message.type == 'poll') {
  return PollMessageWidget(
    poll: PollModel.fromMap(message.toMap(), message.id),
    chatId: widget.communityId,
    chatType: 'community',
    isOwnMessage: message.senderId == currentUser.uid,
  );
}
```

### Step 3: Add Required Imports

Add these imports to the files you modified:

```dart
import 'package:your_app/screens/create_poll_screen.dart';
import 'package:your_app/widgets/poll_message_widget.dart';
import 'package:your_app/models/poll_model.dart';
```

## Chat Type Mapping

Use the correct `chatType` parameter for each chat screen:

- **Community Chat**: `chatType: 'community'`, uses `communities/{id}/messages`
- **Group Chat** (Parent-Teacher): `chatType: 'group'`, uses `parent_teacher_groups/{id}/messages`
- **Individual Chat**: `chatType: 'individual'`, uses `conversations/{id}/messages`

## Firestore Structure

Polls are stored as messages with this structure:

```javascript
{
  "type": "poll",
  "question": "Which day works best?",
  "options": [
    { "id": "opt_1234_0", "text": "Monday", "voteCount": 5 },
    { "id": "opt_1234_1", "text": "Tuesday", "voteCount": 3 }
  ],
  "allowMultiple": false,
  "createdBy": "user_uid",
  "createdByName": "John Doe",
  "createdByRole": "teacher",
  "senderId": "user_uid",  // For compatibility
  "senderName": "John Doe",
  "senderRole": "teacher",
  "content": "Poll: Which day works best?",
  "message": "Poll: Which day works best?",
  "text": "Poll: Which day works best?",
  "createdAt": Timestamp,
  "timestamp": 1234567890,
  "voters": {
    "user1_uid": ["opt_1234_0"],
    "user2_uid": ["opt_1234_1"]
  },
  "isEdited": false,
  "isDeleted": false,
  "reactions": {}
}
```

## Firestore Security Rules

Add these rules to your `firestore.rules`:

```javascript
// For community chats
match /communities/{communityId}/messages/{messageId} {
  allow read: if request.auth != null && isMember(communityId, request.auth.uid);
  
  allow create: if request.auth != null 
    && isMember(communityId, request.auth.uid)
    && (
      // Regular messages
      request.resource.data.type in ['text', 'image', 'file', 'audio']
      ||
      // Poll messages
      (request.resource.data.type == 'poll'
        && request.resource.data.question is string
        && request.resource.data.question.size() > 0
        && request.resource.data.options is list
        && request.resource.data.options.size() >= 2
        && request.resource.data.options.size() <= 6)
    );
  
  allow update: if request.auth != null 
    && isMember(communityId, request.auth.uid)
    && (
      // Only allow updating voters and options (for voting)
      request.resource.data.diff(resource.data).affectedKeys().hasOnly(['voters', 'options'])
    );
}

// Helper function to check membership
function isMember(communityId, userId) {
  return exists(/databases/$(database)/documents/communities/$(communityId)/members/$(userId));
}

// Similar rules for parent_teacher_groups and conversations collections
```

## Testing Checklist

- [ ] Poll button appears in attachment menu for all chat types
- [ ] Create Poll screen opens when tapped
- [ ] Cannot send poll with less than 2 options
- [ ] Cannot add more than 6 options
- [ ] Single-select polls work (radio buttons)
- [ ] Multi-select polls work (checkboxes)
- [ ] Vote counts update in real-time
- [ ] Progress bars animate correctly
- [ ] Multiple users can vote concurrently
- [ ] Votes can be changed by clicking different options
- [ ] Poll displays correctly for all 4 roles (student, parent, teacher, institute)
- [ ] Polls work in community chats
- [ ] Polls work in group chats
- [ ] Polls work in individual chats
- [ ] Existing message types still render correctly
- [ ] App theme colors are used (no hardcoded colors)

## Features

### Create Poll Screen
- Minimum 2 options, maximum 6 options
- Dynamic add/remove option buttons
- Single-select or multi-select toggle
- Real-time validation
- Send button disabled until valid
- Loading state while sending
- Error handling with user-friendly messages

### Poll Message Widget
- Real-time vote updates via Firestore streams
- Animated progress bars
- Vote count badges
- Visual indication of user's votes
- Supports both single and multi-select
- Consistent with app theme colors
- Optimistic UI updates

### Poll Service
- Firestore transactions for vote consistency
- Retry logic with exponential backoff (up to 3 attempts)
- Race condition prevention
- Support for all chat types
- Proper error handling

## Troubleshooting

### Poll not showing after creation
- Check that the message type is 'poll'
- Verify the chatId and chatType are correct
- Check Firestore console for the document

### Votes not updating
- Ensure you're using the StreamBuilder in PollMessageWidget
- Check Firestore rules allow updates to voters field
- Verify user authentication

### Transaction conflicts
- Normal with concurrent voting, service will retry
- If persistent, check Firestore quota limits

## Support for All Roles

The poll feature works for all 4 roles:
- **Students** - Can create and vote in community/group chats
- **Parents** - Can create and vote in group/individual chats
- **Teachers** - Can create and vote in all chat types
- **Institute** - Can create and vote in community chats

The role is automatically detected from the authenticated user via `AuthProvider`.

## Performance Considerations

- Polls use real-time Firestore streams for live updates
- Voting uses transactions to prevent race conditions
- Vote counts are denormalized (stored in options) for faster reads
- Voters map allows audit trail and prevents duplicate votes

## Future Enhancements (Optional)

- Poll expiration/closing after a date
- Results-only mode (no more voting)
- Anonymous polls
- Image options
- Poll analytics dashboard
- Export results to CSV

---

**Integration Complete!** If you encounter any issues, check the console for error messages and verify all imports are correct.
