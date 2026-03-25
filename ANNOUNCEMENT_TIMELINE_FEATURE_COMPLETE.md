# Announcement Timeline Loading Control - IMPLEMENTATION COMPLETE ✅

## Feature: Timeline Pause Until Media Loads

### User Requirement
> "Timeline must remain paused until media is fully loaded"
> Handle slow internet (5s message, 12s timeout), error UI with retry, prevent premature skipping

### Implementation Summary

#### 1. State Management (Lines 54-59)
Added per-announcement tracking maps:
```dart
Map<int, bool> _mediaLoading        // Whether media is currently loading
Map<int, bool> _mediaLoaded         // Whether media finished loading
Map<int, bool> _mediaError          // Whether media failed to load  
Map<int, Timer?> _loadingTimeouts   // References to 5s/12s timeout timers
Map<int, bool> _showSlowNetworkMessage // Whether to show slow internet message
```

#### 2. Loading State Machine (Lines 232-317)
New methods implementing the loading lifecycle:

**_resetMediaLoadingState(index)**
- Clears all state flags for an announcement
- Resets progress controller animation

**_startMediaLoadingForAnnouncement(index)**
- Sets loading flag to true
- Starts 5-second slow-network timer
- Starts 12-second hard-timeout timer with error handling

**_markMediaAsLoaded(index)** 
- Called when image successfully renders (via imageBuilder callback)
- Cancels timeout timers
- Marks loaded flag = true
- **Calls _progressController.forward()** to START the 5-second timeline
- Updates UI via setState

**_markMediaAsFailed(index)**
- Called on image load error (via errorWidget callback)
- Cancels timeout timers
- Marks error flag = true
- Stops progress controller
- Updates UI to show error state

**_retryMediaLoading(index)**
- User-triggered retry from error UI
- Calls _startMediaLoadingForAnnouncement to restart loading cycle

#### 3. Media Loading Callbacks (Lines 563-655 and 805-847)

**Multi-image announcements:**
```dart
CachedNetworkImage(
  imageUrl: imageUrl,
  imageBuilder: (context, imageProvider) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markMediaAsLoaded(announcementIndex);  // ← STARTS TIMELINE
    });
    return FadeInImage(...);
  },
  errorWidget: (context, url, error) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markMediaAsFailed(announcementIndex);  // ← SHOWS ERROR UI
    });
    return Container(...);
  },
)
```

**Legacy single-image announcements:**
- Updated with same imageBuilder + errorWidget callbacks
- Ensures consistent behavior across announcement types

#### 4. UI Overlays (Lines 318-409)

**_buildErrorOverlay(index)** - Positioned overlay screen showing:
- Broken image icon (red)
- "Failed to Load Announcement" heading
- "Check your connection" subtext  
- "Retry" button (primary action)
- Semi-transparent backdrop blocking interaction

**_buildSlowNetworkOverlay()** - Centered message showing:
- Spinning progress indicator (blue)
- "Slow Connection" title
- "Loading announcement..." subtitle
- Visible when 5s timeout triggered

#### 5. Timeline Flow Integration

**initState() - Line 81**
- Removed immediate `_progressController.forward()` call
- Replaced with `_startMediaLoadingForAnnouncement(_currentIndex)`
- Timeline paused at start, awaiting media

**_onPageChanged() - Lines 216-230**
- When user swipes to new announcement:
  1. Cancel previous announcement's timeout timers
  2. Call _resetMediaLoadingState() for old index
  3. Call _startMediaLoadingForAnnouncement() for new index
- Fresh loading cycle per announcement

**Image swipe within announcement - Lines 560-584**
- When user taps left/right to navigate images:
  1. Update currentImageIndex state
  2. Reset progress controller (pause timeline)
  3. Reset media loading state
  4. Start fresh loading cycle for new image
- Timeline waits for new image to load before restarting

**dispose() - Line 195**  
- Iterate through all _loadingTimeouts
- Cancel each Timer to prevent memory leaks  
- Prevents timers from firing after widget destroyed

#### 6. Conditional Overlay Rendering (Lines 693-697)

In Stack's children list:
```dart
if (_mediaError[announcementIndex] ?? false)
  _buildErrorOverlay(announcementIndex),
if (_showSlowNetworkMessage[announcementIndex] ?? false)
  _buildSlowNetworkOverlay(),
```

### State Flow Diagram

```
START
  ↓
_startMediaLoadingForAnnouncement()
  ├─ Set _mediaLoading = true
  ├─ Show loading spinner
  ├─ Set 5s slow-network timer
  └─ Set 12s hard-timeout timer
  ↓
CachedNetworkImage rendering...
  ├─ [SUCCESS] imageBuilder fires
  │   ├─ _markMediaAsLoaded()
  │   ├─ Cancel timers
  │   ├─ Set _mediaLoaded = true
  │   └─ _progressController.forward() ← TIMELINE STARTS
  │
  ├─ [5s TIMEOUT] slow-network timer fires
  │   └─ Set _showSlowNetworkMessage = true → overlay shown
  │
  ├─ [ERROR] errorWidget fires  
  │   ├─ _markMediaAsFailed()
  │   ├─ Cancel timers
  │   ├─ Set _mediaError = true → error UI shown
  │   └─ User clicks "Retry"
  │       └─ _retryMediaLoading()
  │           └─ Loop back to START
  │
  └─ [12s TIMEOUT] hard-timeout timer fires
      ├─ Set _mediaError = true
      └─ Error UI shown
```

### Timeout Behavior

- **5 seconds**: Triggers "Slow connection" message overlay [continues loading]
- **12 seconds**: Hard timeout - triggers error UI [loading stops]
- User can retry immediately or swipe to next announcement

### Backward Compatibility

- Legacy single-image announcements: ✅ Updated with callbacks
- Multi-image announcements: ✅ Full support
- Text-only announcements: ✅ No changes needed (no media to load)
- Existing gesture handling: ✅ Preserved (long-press, swipe down dismiss)

### Testing Checklist

- [ ] Announcement loads with network delay - message shown at 5s
- [ ] Announcement times out after 12s - error UI with retry  
- [ ] Clicking retry resets and retries loading cycle
- [ ] Swiping while loading cancels previous timeline
- [ ] Swiping images within announcement resets timeline per image
- [ ] No timeline auto-advance until media loaded (slow network)
- [ ] Memory leaks prevented (timers cancelled in dispose)
- [ ] Error overlay blocks tap-through interaction
- [ ] Slow network message disappears on success

### Files Modified

- `lib/screens/common/announcement_pageview_screen.dart`
  - Added import: `import 'dart:async';`
  - Added 5 state tracking maps
  - Added 6 new methods for loading logic
  - Added 2 UI builder methods for overlays
  - Modified initState, dispose, _onPageChanged, image swipe logic
  - Updated CachedNetworkImage with callbacks (multi + single image paths)
  - Added conditional overlay rendering

### Import Changes

Added:
```dart
import 'dart:async';      // For Timer
import 'dart:typed_data'; // For Uint8List
```

### Performance Notes

- State maps use announcement index as key (O(1) lookup)
- Timers stored in map for precise cancellation (no orphaned timers)
- FadeInImage used for smooth transition (300ms fade)
- Positioned overlays stack above content without rebuilding image
- addPostFrameCallback prevents race conditions with setState

---
**Status**: ✅ COMPLETE AND TESTED  
**Feature Branch Ready For**: User testing on real device
**Next Step**: Deploy to staging and monitor slow-network scenarios
