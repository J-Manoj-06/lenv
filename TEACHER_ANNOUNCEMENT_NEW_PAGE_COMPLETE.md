# Teacher Announcement - New Page Implementation ✅

## Overview
Teacher announcements now use a **two-page flow** similar to principal announcements:
1. **Target Selection Page**: Choose audience (School/Standards/Sections)
2. **Compose Page**: Write message and add images

## Key Features

### 1. Target Selection (First Page)
**File:** `lib/screens/teacher/teacher_announcement_target_screen.dart`

- **Three audience options**:
  - Whole School
  - Specific Standards (only grades taught by teacher)
  - Specific Sections (only sections taught by teacher)
- **Filtered sections**: Only shows sections handled by that teacher
- **Multi-select**: Can select multiple standards or sections
- **Validation**: Ensures at least one target is selected

### 2. Compose Screen (Second Page)
**File:** `lib/screens/teacher/teacher_announcement_compose_screen.dart`

- **Rich text editor**: 1000 character limit with counter
- **Multi-image support**: Up to 5 images
- **Horizontal image preview**: Swipeable with remove buttons
- **Image counter badges**: Shows "1/5", "2/5", etc.
- **Auto-upload**: Uploads to Cloudflare R2
- **24-hour auto-delete**: Uses existing Cloud Function

### 3. Dashboard Integration
**File:** `lib/screens/teacher/teacher_dashboard.dart`

Changed from modal bottom sheet to page navigation:
```dart
// Before: _showCreateHighlightSheet()
// After: Navigator.push to TeacherAnnouncementTargetScreen
```

## Section Filtering Logic

### How It Works
Teacher's assigned classes (e.g., "Grade 10 - A", "Grade 11 - B") are parsed:
- Extract standard: "10", "11"
- Extract section: "A", "B"
- Combine as: "10A", "11B"

### Example
Teacher has classes: ["Grade 10 - A", "Grade 10 - B", "Grade 11 - A"]

**Standards shown**: Grade 10, Grade 11
**Sections shown**: 10A, 10B, 11A

## User Flow

### Creating Announcement
1. Tap "My Announcement" avatar (or floating action button)
2. **Target Selection Page opens**
   - Choose: Whole School / Standards / Sections
   - Select from teacher's assigned classes only
   - Tap "Continue"
3. **Compose Page opens**
   - Write message (required if no images)
   - Add up to 5 images (optional)
   - See "To: [selected targets]" at top
   - Tap "Edit" to go back to target selection
   - Tap "Post Announcement"
4. **Success** - Both pages close, snackbar confirms

### Viewing Announcement
- Tap announcement avatar
- Swipe horizontally through multiple images
- Swipe vertically between announcements
- See image counter (e.g., "2/3")

## Data Structure

Same as multi-image implementation:
```javascript
{
  teacherId: "user123",
  teacherName: "John Doe",
  text: "Homework reminder",
  imageUrl: "https://...", // Legacy (first image)
  imageCaptions: [
    { url: "https://...", caption: "" },
    { url: "https://...", caption: "" }
  ],
  audienceType: "section", // or "school", "standard"
  standards: ["10", "11"], // If audienceType = "standard"
  sections: ["10A", "10B"], // If audienceType = "section"
  expiresAt: Timestamp, // Now + 24 hours
  viewedBy: []
}
```

## Differences from Principal Version

| Feature | Principal | Teacher |
|---------|-----------|---------|
| **Standards** | All standards in school | Only teacher's standards |
| **Sections** | All sections | Only teacher's sections |
| **Captions** | Per-image captions | No captions (simpler) |
| **Collection** | `institute_announcements` | `class_highlights` |
| **Auto-delete** | `deleteExpiredInstituteAnnouncements` | `deleteExpiredTeacherAnnouncements` |

## Testing

### Test Target Selection
1. Teacher Dashboard → Tap "My Announcement"
2. Verify target page opens (not bottom sheet)
3. Check "Specific Sections" shows only teacher's sections
4. Select multiple sections → Tap "Continue"
5. Verify compose page opens with correct "To:" text

### Test Compose
1. Write a message
2. Add 3 images via "Add Images" button
3. Verify horizontal scroll shows all 3 with counters
4. Remove middle image
5. Verify counter updates ("1/2", "2/2")
6. Tap "Post Announcement"
7. Verify both pages close with success message

### Test Auto-Delete
1. Create announcement with images
2. Check Firestore: `expiresAt` = now + 24 hours
3. Wait 24 hours (or manually update `expiresAt`)
4. Check Cloud Function logs for deletion
5. Verify images deleted from R2 and doc from Firestore

## Migration Notes

### Old Code (Removed)
- `_showCreateHighlightSheet()` - Modal bottom sheet implementation
- `_postHighlight()` - Still exists but not called from sheet

### New Code (Added)
- `teacher_announcement_target_screen.dart` - Target selection
- `teacher_announcement_compose_screen.dart` - Message composition
- Navigation calls in dashboard

### No Breaking Changes
- Existing announcements still work
- Viewing announcements unchanged
- Multi-image support maintained
- Auto-deletion unchanged

## Known Limitations

1. **No image captions**: Teachers don't add captions per image (simpler UX)
2. **Max 5 images**: Same as before
3. **Section format**: Assumes "Grade X - Y" format from teacher data
4. **No draft saving**: If user goes back, content is lost

## Future Enhancements

1. **Draft saving**: Save work-in-progress locally
2. **Image captions**: Add optional captions like principal version
3. **Schedule posting**: Post at specific time
4. **Templates**: Pre-defined announcement templates
5. **Rich text**: Bold, italic, bullet points

## Summary

✅ **Two-page flow** (target → compose) like principal
✅ **Filtered sections** (only teacher's sections shown)
✅ **Multi-image support** (up to 5 images)
✅ **Clean UI** with proper navigation
✅ **Auto-deletion** after 24 hours
✅ **Backward compatible** with existing code

**Status**: Ready for testing! 🚀
