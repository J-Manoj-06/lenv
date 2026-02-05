/// POLL INTEGRATION - CODE EXAMPLES FOR ALL CHAT TYPES
/// Copy the appropriate section to your chat screen
library;

// ============================================================================
// SECTION 1: COMMUNITY CHAT (Principal/Institute - community_chat_page.dart)
// ============================================================================

// Add import at top of file:
import 'package:new_reward/screens/create_poll_screen.dart';
import 'package:new_reward/widgets/poll_message_widget.dart';
import 'package:new_reward/models/poll_model.dart';

// STEP 1A: Add Poll option to _showAttachmentPicker() around line 535
// Find the Row with attachment options and add this as the 5th option:

void _buildAttachmentOption(
  label = 'Poll',
),

// STEP 1B: Render poll messages in message list
// Find where messages are built (search for message.type checks)
// Add this before other type checks:

PollMessageWidget if (message.type == 'poll') {
  return PollMessageWidget(
    poll: PollModel.fromMap(message.toMap(), message.id),
    chatId: widget.communityId,
    chatType: 'community',
    isOwnMessage: message.senderId == currentUser.uid,
  );
}

// ============================================================================
// SECTION 2: STUDENT COMMUNITY CHAT (community_chat_screen.dart)
// ============================================================================

// Add same imports as Section 1

// STEP 2A: Add Poll to attachment menu (around line 3256 in showModalBottomSheet)
// Inside the GridView.count children list, add:

void _AttachmentButton(
  label = 'Poll',
),

// STEP 2B: Render polls in message list
// Find message rendering logic and add:

PollMessageWidget if (message['type'] == 'poll') {
  return PollMessageWidget(
    poll: PollModel.fromMap(message as Map<String, dynamic>, message['id']),
    chatId: widget.community.id,
    chatType: 'community',
    isOwnMessage: message['senderId'] == currentUser?.uid,
  );
}

// ============================================================================
// SECTION 3: TEACHER COMMUNITY CHAT (teacher_community_chat_screen.dart)
// ============================================================================

// Add same imports

// STEP 3A: Add Poll to attachment menu
// Find showModalBottomSheet with attachment options and add:

void _AttachmentOption(
  label = 'Poll',
),

// STEP 3B: Render polls
PollMessageWidget if (message['type'] == 'poll') {
  return PollMessageWidget(
    poll: PollModel.fromMap(message as Map<String, dynamic>, message['id']),
    chatId: widget.community.id,
    chatType: 'community',
    isOwnMessage: message['senderId'] == currentUser?.uid,
  );
}

// ============================================================================
// SECTION 4: GROUP CHAT (Parent-Teacher - parent_section_group_chat_screen.dart)
// ============================================================================

// Add same imports

// STEP 4A: Add Poll to attachment menu (around line 2440)
// Find GridView with attachment buttons and add:

void _buildAttachmentOption(
  context,
  Icons.poll,
  'Poll',
),

// STEP 4B: Render polls in message builder
PollMessageWidget if (message.type == 'poll') {
  return PollMessageWidget(
    poll: PollModel.fromMap(message.toMap(), message.id),
    chatId: widget.groupId,
    chatType: 'group',
    isOwnMessage: message.senderId == currentUserId,
  );
}

// ============================================================================
// SECTION 5: TEACHER GROUP CHAT (teacher/messages/chat_screen.dart)
// ============================================================================

// Add same imports

// STEP 5A: Add Poll to _pickAttachmentSheet() around line 362
// Add this ListTile to the Wrap children:

void ListTile(
  leading = const Icon(Icons.poll),
  title = const Text('Poll'),
  onTap = () {
    Navigator.pop(ctx);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePollScreen(
          chatId: widget.groupId,
          chatType: 'group',
        ),
      ),
    );
  },
),

// STEP 5B: Render polls in message list
// Find where messages are rendered and add:

PollMessageWidget if (msg['type'] == 'poll') {
  return PollMessageWidget(
    poll: PollModel.fromMap(msg as Map<String, dynamic>, msg['id']),
    chatId: widget.groupId,
    chatType: 'group',
    isOwnMessage: msg['senderId'] == currentUserId,
  );
}

// ============================================================================
// SECTION 6: INDIVIDUAL CHAT - Teacher-Parent (teacher_chat_screen.dart)
// ============================================================================

// Add same imports

// STEP 6A: Add Poll to attachment menu
// Find showModalBottomSheet around line 352 and add:

void ListTile(
  leading = const Icon(Icons.poll),
  title = const Text('Poll'),
  onTap = () {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePollScreen(
          chatId: widget.conversationId,
          chatType: 'individual',
        ),
      ),
    );
  },
),

// STEP 6B: Render polls
PollMessageWidget if (message['type'] == 'poll') {
  return PollMessageWidget(
    poll: PollModel.fromMap(message as Map<String, dynamic>, message['id']),
    chatId: widget.conversationId,
    chatType: 'individual',
    isOwnMessage: message['senderRole'] == currentUserRole,
  );
}

// ============================================================================
// SECTION 7: PARENT INDIVIDUAL CHAT (parent_chat_screen.dart)
// ============================================================================

// Add same imports

// STEP 7A: Add Poll to attachment menu
// Find showModalBottomSheet and add:

void ListTile(
  leading = const Icon(Icons.poll),
  title = const Text('Poll'),
  onTap = () {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePollScreen(
          chatId: widget.conversationId,
          chatType: 'individual',
        ),
      ),
    );
  },
),

// STEP 7B: Render polls
PollMessageWidget if (message['type'] == 'poll') {
  return PollMessageWidget(
    poll: PollModel.fromMap(message as Map<String, dynamic>, message['id']),
    chatId: widget.conversationId,
    chatType: 'individual',
    isOwnMessage: message['senderRole'] == 'parent',
  );
}

// ============================================================================
// QUICK REFERENCE TABLE
// ============================================================================

/**
 * Chat Type Mapping:
 * 
 * Screen                                  | chatType      | chatId variable
 * ----------------------------------------|---------------|------------------
 * community_chat_page.dart (Institute)    | 'community'   | widget.communityId
 * community_chat_screen.dart (Student)    | 'community'   | widget.community.id
 * teacher_community_chat_screen.dart      | 'community'   | widget.community.id
 * parent_section_group_chat_screen.dart   | 'group'       | widget.groupId
 * teacher/messages/chat_screen.dart       | 'group'       | widget.groupId
 * teacher_chat_screen.dart                | 'individual'  | widget.conversationId
 * parent_chat_screen.dart                 | 'individual'  | widget.conversationId
 * 
 * Firestore Paths:
 * - Community: communities/{communityId}/messages/{messageId}
 * - Group: parent_teacher_groups/{groupId}/messages/{messageId}
 * - Individual: conversations/{conversationId}/messages/{messageId}
 */

// ============================================================================
// TESTING CHECKLIST
// ============================================================================

/**
 * □ Institute can create polls in community chats
 * □ Students can create and vote on polls in community chats
 * □ Teachers can create and vote on polls in all chat types
 * □ Parents can create and vote on polls in group and individual chats
 * □ Single-select polls work correctly (radio buttons)
 * □ Multi-select polls work correctly (checkboxes)
 * □ Vote counts update in real-time
 * □ Multiple users voting concurrently works
 * □ Users can change their votes
 * □ Progress bars animate smoothly
 * □ Theme colors are used (no hardcoded colors)
 * □ Polls display correctly on all screen sizes
 * □ Offline behavior works (votes queued)
 * □ Error messages are user-friendly
 * □ Existing message types still work
 */
