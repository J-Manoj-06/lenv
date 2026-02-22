# Auto-Scrolling Announcement Implementation Guide

## Overview
The `AutoScrollAnnouncement` widget provides a smooth auto-scrolling announcement with "Read More" functionality, suitable for all user roles (Teacher, Student, Parent, Institute).

## Features
- ✅ Auto-scrolls vertically when text exceeds height limit
- ✅ "Read More" button appears automatically for long content
- ✅ Pauses auto-scroll when expanded
- ✅ Enables manual scrolling in expanded state
- ✅ Proper AnimationController disposal
- ✅ Dark mode support
- ✅ Customizable colors and timing
- ✅ No overflow issues

## Implementation Examples

### 1. Student Dashboard Implementation

```dart
import 'package:flutter/material.dart';
import '../widgets/auto_scroll_announcement.dart';

// In your student_dashboard_screen.dart, add this to display announcements:

Widget _buildAnnouncementsSection(List<Map<String, dynamic>> announcements) {
  if (announcements.isEmpty) {
    return const SizedBox.shrink();
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'Announcements',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: announcements.length,
        itemBuilder: (context, index) {
          final announcement = announcements[index];
          return AutoScrollAnnouncement(
            title: announcement['title'] ?? 'Announcement',
            content: announcement['content'] ?? '',
            postedBy: announcement['postedBy'],
            timestamp: announcement['timestamp'] != null
                ? (announcement['timestamp'] as Timestamp).toDate()
                : null,
            maxCollapsedHeight: 150.0,
            scrollDuration: const Duration(seconds: 20),
            accentColor: const Color(0xFF7A5CFF),
          );
        },
      ),
    ],
  );
}
```

### 2. Teacher Dashboard Implementation

```dart
import 'package:flutter/material.dart';
import '../widgets/auto_scroll_announcement.dart';

// In your teacher_dashboard.dart:

Widget _buildTeacherAnnouncements(BuildContext context) {
  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('announcements')
        .where('targetRole', whereIn: ['all', 'teacher'])
        .orderBy('createdAt', descending: true)
        .limit(5)
        .snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final announcements = snapshot.data!.docs;
      
      if (announcements.isEmpty) {
        return const SizedBox.shrink();
      }

      return Column(
        children: announcements.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return AutoScrollAnnouncement(
            title: data['title'] ?? 'Announcement',
            content: data['content'] ?? '',
            postedBy: data['postedByName'] ?? 'Admin',
            timestamp: (data['createdAt'] as Timestamp?)?.toDate(),
            maxCollapsedHeight: 120.0,
            scrollDuration: const Duration(seconds: 15),
            accentColor: const Color(0xFF1362EB), // Teacher theme color
          );
        }).toList(),
      );
    },
  );
}
```

### 3. Parent Dashboard Implementation

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/auto_scroll_announcement.dart';
import '../providers/parent_provider.dart';

// In your parent_dashboard_screen.dart:

Widget _buildParentAnnouncements(BuildContext context) {
  return Consumer<ParentProvider>(
    builder: (context, provider, _) {
      if (provider.isLoadingAnnouncements) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ),
        );
      }

      if (provider.announcements.isEmpty) {
        return const SizedBox.shrink();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.notifications_active, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Important Announcements',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ...provider.announcements.map((announcement) {
            return AutoScrollAnnouncement(
              title: announcement['title'] ?? 'Announcement',
              content: announcement['content'] ?? '',
              postedBy: announcement['postedBy'],
              timestamp: announcement['timestamp'] != null
                  ? DateTime.parse(announcement['timestamp'].toString())
                  : null,
              maxCollapsedHeight: 130.0,
              scrollDuration: const Duration(seconds: 18),
              accentColor: Colors.green,
            );
          }).toList(),
        ],
      );
    },
  );
}
```

### 4. Institute Dashboard Implementation

```dart
import 'package:flutter/material.dart';
import '../widgets/auto_scroll_announcement.dart';

// In your institute_dashboard_screen.dart:

Widget _buildInstituteAnnouncements() {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: _fetchInstituteAnnouncements(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SizedBox.shrink();
      }

      if (!snapshot.hasData || snapshot.data!.isEmpty) {
        return const SizedBox.shrink();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Institute Announcements',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...snapshot.data!.map((announcement) {
            return AutoScrollAnnouncement(
              title: announcement['title'] ?? 'Announcement',
              content: announcement['content'] ?? '',
              postedBy: announcement['postedByName'],
              timestamp: announcement['createdAt'] != null
                  ? (announcement['createdAt'] as Timestamp).toDate()
                  : null,
              maxCollapsedHeight: 140.0,
              scrollDuration: const Duration(seconds: 25),
              accentColor: const Color(0xFFE91E63), // Pink accent
            );
          }).toList(),
        ],
      );
    },
  );
}

Future<List<Map<String, dynamic>>> _fetchInstituteAnnouncements() async {
  // Your Firestore fetch logic here
  final snapshot = await FirebaseFirestore.instance
      .collection('announcements')
      .where('instituteId', isEqualTo: currentInstituteId)
      .orderBy('createdAt', descending: true)
      .limit(10)
      .get();
      
  return snapshot.docs.map((doc) => doc.data()).toList();
}
```

## Customization Options

### Basic Usage
```dart
AutoScrollAnnouncement(
  title: 'Important Update',
  content: 'This is a long announcement that will auto-scroll...',
)
```

### With All Options
```dart
AutoScrollAnnouncement(
  title: 'Holiday Notice',
  content: 'School will be closed on...',
  postedBy: 'Principal Dr. Smith',
  timestamp: DateTime.now(),
  maxCollapsedHeight: 150.0,  // Height before showing "Read More"
  scrollDuration: Duration(seconds: 20),  // Speed of auto-scroll
  backgroundColor: Colors.blue.shade50,  // Custom background
  textColor: Colors.black87,  // Custom text color
  accentColor: Colors.blue,  // Color for icon, buttons
)
```

## State Management

The widget internally manages:
- `_isExpanded`: Controls expanded/collapsed state
- `_needsReadMore`: Determines if "Read More" button should show
- `_scrollController`: AnimationController for auto-scrolling
- `_manualScrollController`: ScrollController for manual scrolling

All controllers are properly disposed in the `dispose()` method.

## Layout Guidelines

### Recommended Placement
1. **Top of Dashboard**: For urgent announcements
2. **Below Stats Section**: For general updates
3. **Dedicated Tab**: For announcement history

### Spacing
```dart
// Good spacing example
Column(
  children: [
    _buildStatsSection(),
    const SizedBox(height: 16),  // Space before announcements
    _buildAnnouncementsSection(),
    const SizedBox(height: 16),  // Space after announcements
    _buildOtherContent(),
  ],
)
```

## Performance Tips

1. **Limit Items**: Show only recent announcements (5-10 items)
2. **Use ListView.builder**: For long lists
3. **Lazy Loading**: Load more on scroll if needed
4. **Cache Data**: Use provider pattern for state management

## Troubleshooting

### Issue: Animation not starting
**Solution**: Ensure content height exceeds `maxCollapsedHeight`

### Issue: Overflow errors
**Solution**: Widget handles this automatically with ClipRect

### Issue: Animation not stopping on dispose
**Solution**: Widget properly disposes AnimationController

### Issue: Manual scroll not working
**Solution**: Ensure you're in expanded mode (_isExpanded = true)

## Testing

Test the widget with:
1. Short text (no "Read More" button)
2. Medium text (borderline case)
3. Very long text (multiple scrolls needed)
4. Dark mode and light mode
5. Different screen sizes

## Integration Checklist

- [ ] Import `auto_scroll_announcement.dart` widget
- [ ] Fetch announcements from Firestore/Provider
- [ ] Add to dashboard layout with proper spacing
- [ ] Test expand/collapse functionality
- [ ] Test auto-scroll animation
- [ ] Verify dark mode appearance
- [ ] Test on different screen sizes
- [ ] Ensure no memory leaks (check dispose)

## Complete Example

Here's a complete working example for any dashboard:

```dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/auto_scroll_announcement.dart';

class DashboardWithAnnouncements extends StatelessWidget {
  const DashboardWithAnnouncements({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Your existing dashboard content
            _buildDashboardStats(),
            
            // Announcements section
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('announcements')
                  .orderBy('createdAt', descending: true)
                  .limit(5)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox.shrink();
                }

                return Column(
                  children: snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return AutoScrollAnnouncement(
                      title: data['title'] ?? '',
                      content: data['content'] ?? '',
                      postedBy: data['postedBy'],
                      timestamp: (data['createdAt'] as Timestamp?)?.toDate(),
                    );
                  }).toList(),
                );
              },
            ),
            
            // More dashboard content
            _buildOtherSections(),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardStats() {
    // Your stats implementation
    return Container();
  }

  Widget _buildOtherSections() {
    // Your other sections
    return Container();
  }
}
```

## Support

For issues or questions:
1. Check the widget documentation in `auto_scroll_announcement.dart`
2. Verify all required parameters are provided
3. Ensure proper state management
4. Check console for any error messages

---

**Created**: February 22, 2026
**Widget Location**: `/lib/widgets/auto_scroll_announcement.dart`
**Status**: Ready for production use
