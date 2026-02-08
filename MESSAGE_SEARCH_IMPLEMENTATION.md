# Message Search Implementation Guide

## Overview
This guide shows how to integrate the message search feature into your chat screens.

## Files Created
1. **`lib/screens/messages/message_search_page.dart`** - Search UI and logic
2. **`lib/utils/message_scroll_highlight_mixin.dart`** - Scroll and highlight functionality

---

## Implementation Steps

### Step 1: Add Search Icon to AppBar

```dart
// In your chat screen (e.g., community_chat_page.dart)
actions: [
  IconButton(
    icon: Icon(Icons.search, color: textColor),
    onPressed: () => _openSearchPage(context),
  ),
],
```

### Step 2: Add Mixin to Your Chat State

```dart
import 'package:your_app/utils/message_scroll_highlight_mixin.dart';

class _CommunityChatPageState extends State<CommunityChatPage> 
    with MessageScrollAndHighlightMixin {
  
  @override
  void initState() {
    super.initState();
    initializeScrollController(); // Initialize scroll controller from mixin
  }
  
  @override
  void dispose() {
    disposeScrollController(); // Clean up from mixin
    super.dispose();
  }
}
```

### Step 3: Update ListView to Use Mixin Keys

```dart
ListView.builder(
  controller: scrollController, // Use controller from mixin
  reverse: true,
  itemCount: messages.length,
  itemBuilder: (context, index) {
    final message = messages[index];
    final messageId = message['id'] as String;
    final isHighlighted = highlightedMessageId == messageId;
    
    return HighlightedMessageWrapper(
      key: getMessageKey(messageId), // Assign key from mixin
      isHighlighted: isHighlighted,
      highlightColor: primaryColor.withOpacity(0.3),
      child: _MessageBubble(
        message: message,
        isMe: isMe,
        // ... other properties
      ),
    );
  },
);
```

### Step 4: Implement Search Navigation

```dart
void _openSearchPage(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MessageSearchPage(
        collectionPath: 'staff_rooms/${widget.instituteId}/messages',
        primaryColor: primaryColor,
        searchHint: 'Search in ${widget.communityName}...',
        onMessageSelected: (messageId, messageData) {
          _handleMessageSelected(messageId, messageData);
        },
      ),
    ),
  );
}

Future<void> _handleMessageSelected(
  String messageId,
  Map<String, dynamic> messageData,
) async {
  // Wait for page to dismiss
  await Future.delayed(const Duration(milliseconds: 100));
  
  // Get current messages from StreamBuilder
  final messages = _currentMessages; // Your messages list
  
  // Scroll to message with highlight
  await scrollToMessage(
    messageId,
    messages,
    highlightDuration: const Duration(seconds: 2),
  );
}
```

---

## Complete Example: Community Chat Integration

```dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/message_scroll_highlight_mixin.dart';
import 'message_search_page.dart';

class CommunityChatPage extends StatefulWidget {
  final String communityId;
  final String communityName;

  const CommunityChatPage({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  @override
  State<CommunityChatPage> createState() => _CommunityChatPageState();
}

class _CommunityChatPageState extends State<CommunityChatPage> 
    with MessageScrollAndHighlightMixin {
  
  List<DocumentSnapshot> _currentMessages = [];

  @override
  void initState() {
    super.initState();
    initializeScrollController(); // From mixin
  }

  @override
  void dispose() {
    disposeScrollController(); // From mixin
    super.dispose();
  }

  void _openSearchPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageSearchPage(
          collectionPath: 'chats/${widget.communityId}/messages',
          primaryColor: const Color(0xFF00A884),
          searchHint: 'Search in ${widget.communityName}...',
          onMessageSelected: (messageId, messageData) async {
            await Future.delayed(const Duration(milliseconds: 100));
            
            final messages = _currentMessages.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              data['id'] = doc.id;
              return data;
            }).toList();
            
            await scrollToMessage(messageId, messages);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.communityName),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _openSearchPage,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats/${widget.communityId}/messages')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          _currentMessages = snapshot.data!.docs;

          return ListView.builder(
            controller: scrollController, // From mixin
            reverse: true,
            itemCount: _currentMessages.length,
            itemBuilder: (context, index) {
              final doc = _currentMessages[index];
              final message = doc.data() as Map<String, dynamic>;
              final messageId = doc.id;
              final isHighlighted = highlightedMessageId == messageId;

              return HighlightedMessageWrapper(
                key: getMessageKey(messageId), // From mixin
                isHighlighted: isHighlighted,
                child: MessageBubble(
                  message: message,
                  messageId: messageId,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final String messageId;

  const MessageBubble({
    super.key,
    required this.message,
    required this.messageId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFF8800),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message['text'] ?? '',
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}
```

---

## Features

### ✅ Live Search
- Type and see results instantly
- Case-insensitive matching
- Partial text matching
- Searches both message text and attachment names

### ✅ Precise Scrolling
- Scrolls to exact message position
- Centers message on screen
- Smooth animation (500ms)
- Fallback index-based scrolling if key not found

### ✅ Highlight Animation
- Yellow glow effect (customizable)
- Fades in and out smoothly
- Auto-clears after 2 seconds
- Visual feedback for located message

### ✅ Performance Optimized
- Loads last 500 messages
- Client-side filtering for speed
- Efficient GlobalKey management
- Automatic key cleanup

---

## Customization

### Change Highlight Color
```dart
HighlightedMessageWrapper(
  isHighlighted: isHighlighted,
  highlightColor: Colors.blue.withOpacity(0.4), // Custom color
  animationDuration: const Duration(milliseconds: 500), // Custom duration
  child: yourWidget,
)
```

### Change Search Result Limit
```dart
// In message_search_page.dart, line 67
.limit(500) // Change to desired number
```

### Adjust Scroll Animation
```dart
// In message_scroll_highlight_mixin.dart, line 161
duration: const Duration(milliseconds: 500), // Adjust speed
curve: Curves.easeInOut, // Change curve
```

---

## Troubleshooting

### Issue: Message not scrolling
**Solution:** Ensure GlobalKey is assigned to the message container, not a child widget.

### Issue: Highlight not showing
**Solution:** Check that `isHighlighted` boolean is being updated in ListView.builder.

### Issue: Search showing no results
**Solution:** Verify Firestore collection path is correct and messages have 'text' field.

### Issue: Scroll jumps instead of animating
**Solution:** Ensure ScrollController has clients before animating.

---

## Notes

- Works with reverse and normal ListViews
- Compatible with StreamBuilder and FutureBuilder
- Handles deleted messages gracefully
- Thread-safe with proper state management
