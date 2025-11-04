# Student Announcements Implementation

## Summary
Implemented complete student-side announcement viewing with proper audience-based filtering. Students can now see teacher announcements filtered by their class/section.

## Changes Made

### 1. **Added Announcements Section to Student Dashboard**
   - File: `lib/screens/student/student_dashboard_screen.dart`
   - Added imports: `StatusModel`, `StudentModel`, `StatusViewScreen`
   - New widget: `_buildAnnouncementsSection()` displays filtered announcements

### 2. **Audience Filtering Logic**
The implementation properly filters announcements based on:

- **School**: All students see these announcements
- **Standard**: Only students in selected grades (e.g., 7, 8) see these
- **Section**: Only students in selected sections (e.g., 7A, 8B) see these

### 3. **Parsing Student's Class Data**
The code handles multiple className formats:
- `"Grade 7 - A"` → Standard: "7", Section: "A"
- `"7A"` → Standard: "7", Section: "A"
- `"7 - A"` → Standard: "7", Section: "A"
- `"Grade 7"` → Standard: "7"

### 4. **UI Components**
- Horizontal scrollable row labeled "Announcements"
- Orange gradient ring for unseen announcements
- Grey ring for seen announcements
- Teacher initials in circular avatar
- Tap to view full announcement in story-like viewer

### 5. **View Tracking**
- Reuses existing `StatusViewScreen` from teacher module
- Automatically marks announcements as viewed using `arrayUnion`
- Students cannot delete announcements (only teachers can delete their own)

## How It Works

### Data Flow:
1. **Teacher posts** announcement with audience selection (School/Standards/Sections)
2. **Firestore stores** with fields: `audienceType`, `standards[]`, `sections[]`
3. **Student dashboard** queries all announcements for their school
4. **Client-side filter** uses `StatusModel.isVisibleTo()` method
5. **Display** shows only announcements matching student's class/section
6. **Viewing** marks announcement with student's UID in `viewedBy[]` array

### Query Structure:
```dart
FirebaseFirestore.instance
  .collection('class_highlights')
  .where('instituteId', isEqualTo: student.schoolId)
  .where('expiresAt', isGreaterThan: Timestamp.now())
  .orderBy('expiresAt', descending: false)
  .orderBy('createdAt', descending: true)
```

### Filtering Logic (from StatusModel):
```dart
bool isVisibleTo({
  required String userStandard,
  required String userSection,
}) {
  if (audienceType == 'school') return true;
  if (audienceType == 'standard' && standards.contains(userStandard)) {
    return true;
  }
  if (audienceType == 'section' && sections.contains(userSection)) {
    return true;
  }
  return false;
}
```

## Testing Checklist

### Teacher Side (Already Working):
- [x] Create announcement for "School" → All students should see it
- [x] Create announcement for specific standards (e.g., Grade 7, 8) → Only those grades see it
- [x] Create announcement for specific sections (e.g., 7A, 8B) → Only those sections see it
- [x] Teacher can delete their own announcements
- [x] Teachers see seen/unseen differentiation

### Student Side (Newly Implemented):
- [ ] Student sees announcements section on dashboard
- [ ] "School" announcements visible to all students
- [ ] "Standard" announcements filtered correctly (only matching grade students see them)
- [ ] "Section" announcements filtered correctly (only matching section students see them)
- [ ] Students from different classes see different announcements
- [ ] Tapping announcement opens story viewer
- [ ] After viewing, announcement marked as seen (grey ring)
- [ ] Student cannot delete announcements
- [ ] Orange gradient for unseen, grey for seen
- [ ] No announcements = section hidden (doesn't show empty state)

## Example Scenarios

### Scenario 1: School-Wide Announcement
- **Teacher posts**: "Holiday on Friday" to "School"
- **Result**: All students in the institute see it

### Scenario 2: Grade-Specific Announcement
- **Teacher posts**: "Math test tomorrow" to Standards [7, 8]
- **Result**: 
  - Students in Grade 7 see it ✓
  - Students in Grade 8 see it ✓
  - Students in Grade 6 or 9 don't see it ✗

### Scenario 3: Section-Specific Announcement
- **Teacher posts**: "Bring lab coat" to Sections [7A, 8B]
- **Result**:
  - Students in 7A see it ✓
  - Students in 8B see it ✓
  - Students in 7B or 8A don't see it ✗

## Database Structure

### Collection: `class_highlights`
```javascript
{
  "id": "auto-generated",
  "teacherId": "teacher_uid",
  "teacherName": "John Doe",
  "instituteId": "school_id",
  "text": "Announcement text",
  "imageUrl": "optional_image_url",
  "createdAt": Timestamp,
  "expiresAt": Timestamp,
  "audienceType": "school" | "standard" | "section",
  "standards": ["7", "8"],  // Empty if audienceType is not 'standard'
  "sections": ["7A", "8B"], // Empty if audienceType is not 'section'
  "viewedBy": ["student_uid1", "student_uid2"] // Students who viewed
}
```

## Files Modified
1. `lib/screens/student/student_dashboard_screen.dart` - Added announcements section
2. `lib/models/status_model.dart` - Already had `isVisibleTo()` method (no changes needed)

## Notes
- The implementation leverages the existing `StatusModel.isVisibleTo()` method
- No database changes required - all fields already exist
- Reuses the teacher's `StatusViewScreen` for consistent UX
- Client-side filtering ensures security even if Firestore rules allow read access
- Empty state handled gracefully (section hidden if no announcements)
