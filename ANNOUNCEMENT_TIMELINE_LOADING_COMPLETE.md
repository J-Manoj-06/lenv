# ✅ ANNOUNCEMENT TIMELINE LOADING CONTROL - IMPLEMENTATION COMPLETE

## Feature Overview
**Timeline Pause Until Media Loads** - The announcement story timeline now waits for media (images) to fully load before starting the 5-second auto-advance countdown. Includes error handling with retry, slow network detection, and user-friendly UI overlays.

---

## Implementation Summary

### 1. State Management
Five per-announcement tracking maps enable independent state management for each announcement in the carousel:

```dart
final Map<int, bool> _mediaLoading         // Currently loading?
final Map<int, bool> _mediaLoaded          // Load completed?
final Map<int, bool> _mediaError           // Load failed?
final Map<int, Timer?> _loadingTimeouts    // Timer references (5s + 12s)
final Map<int, bool> _showSlowNetworkMessage // Show slow net message?
```

### 2. Loading Lifecycle (6 Methods)

#### `_resetMediaLoadingState(index)`
- Clears all state flags for an announcement
- Resets progress controller animation
- Prepares for fresh loading cycle

#### `_startMediaLoadingForAnnouncement(index)`
- **Initializes loading state**
- **5-second timeout:** Shows "Slow Connection" message if media still loading
- **12-second timeout:** Triggers error UI if media hasn't loaded
- Stores timer references for cancellation on navigate/dispose

#### `_markMediaAsLoaded(index)`
- **Called when image successfully renders** (via imageBuilder callback)
- Cancels timeout timers
- **Calls `_progressController.forward()`** ← **KEY: Starts timeline here**
- Updates UI state

#### `_markMediaAsFailed(index)`
- **Called on image load error** (via errorWidget callback)
- Cancels timeout timers
- Stops progress controller
- Marks error state for error UI rendering

#### `_retryMediaLoading(index)`
- User clicks "Retry" button in error UI
- Restarts `_startMediaLoadingForAnnouncement()` for full loading cycle

#### `_buildErrorOverlay(index)` & `_buildSlowNetworkOverlay()`
- Error UI: Broken image icon + "Failed to Load" + Retry button
- Slow network UI: Spinner + "Slow Connection" message
- Rendered conditionally via Positioned overlays on Stack

---

## 3. Timeline Flow

```
User taps announcement or swipes to new one
        ↓
_onPageChanged() or initState()
        ↓
_startMediaLoadingForAnnouncement()
├─ Set _mediaLoading = true
├─ Show loading spinner (from CachedNetworkImage placeholder)
├─ Start 5s slow-network timer
└─ Start 12s hard-timeout timer
        ↓
CachedNetworkImage renders...
        ↓
        ├─ [FAST PATH] Image loads < 5s
        │  └─ imageBuilder fires
        │     └─ _markMediaAsLoaded()
        │        ├─ Cancel timers
        │        ├─ Set _mediaLoaded = true
        │        └─ _progressController.forward() ← TIMELINE STARTS NOW
        │           └─ Progress bar fills over 5 seconds
        │              └─ Auto-advance to next announcement
        │
        ├─ [SLOW PATH] 5s passes, image still loading
        │  └─ Slow network timer fires
        │     └─ Set _showSlowNetworkMessage = true
        │        └─ Show "Slow Connection" overlay (continues loading)
        │
        ├─ [ERROR PATH 1] Image fails to load
        │  └─ errorWidget fires
        │     └─ _markMediaAsFailed()
        │        ├─ Cancel timers
        │        ├─ Set _mediaError = true
        │        └─ Show error UI with "Retry" button
        │
        └─ [ERROR PATH 2] 12s passes, still not loaded
           └─ Hard timeout timer fires
              ├─ Mark as error
              └─ Show error UI
```

---

## 4. Media Loading Callbacks

### Multi-Image Announcements (Lines 596+)
```dart
CachedNetworkImage(
  imageUrl: imageUrl,
  imageBuilder: (context, imageProvider) {
    // ✅ Called when image successfully renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markMediaAsLoaded(announcementIndex);
    });
    return Image(image: imageProvider, fit: BoxFit.contain);  // Direct render, no FadeInImage
  },
  errorWidget: (context, url, error) {
    // ✅ Called on image load error
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markMediaAsFailed(announcementIndex);
    });
    return Container(color: Colors.grey.shade900, ...);
  },
)
```

### Single-Image/Legacy Announcements (Lines 765+)
Same callback structure applied to ensure consistent behavior across all announcement types.

---

## 5. UI State Rendering

### Error Overlay (Positioned.fill)
- Rendered when `_mediaError[announcementIndex] == true`
- Red broken-image icon (64px)
- "Failed to Load Announcement" heading
- "Please check your connection and try again" subtext
- "Retry" button (primary action, fires `_retryMediaLoading()`)
- Semi-transparent black backdrop (blocks interaction)

### Slow Network Overlay (Positioned.fill)
- Rendered when `_showSlowNetworkMessage[announcementIndex] == true`
- Blue spinning CircularProgressIndicator
- "Slow Connection" title
- "Loading announcement..." subtitle
- Semi-transparent black backdrop (allows tap-through)
- Auto-hides on success or error

---

## 6. Page Navigation & Memory Management

### On Page Change (`_onPageChanged`)
1. Cancel timeout timers from **previous** announcement
2. Reset media loading state for **current** announcement
3. Start fresh loading cycle for **current** announcement
Prevents orphaned timers and ensures clean state transitions.

### On Widget Dispose
```dart
_loadingTimeouts.forEach((key, timer) => timer?.cancel());
```
Cancels all pending timers before widget destruction.

### Image Swipe Within Announcement
When user taps left/right to navigate images:
1. Update `_announcementImageIndex[announcementIndex]`
2. Reset progress controller (pause timeline)
3. Reset media loading state
4. Start fresh loading cycle
Result: Timeline waits for new image to load before restarting.

---

## 7. Timeline Auto-Advance Logic

Progress controller completion listener (initState):
```dart
_progressController.addStatusListener((status) {
  if (status == AnimationStatus.completed) {
    // Auto-advance to next announcement
    if (_pageController.hasClients &&
        _currentIndex < widget.announcements.length - 1) {
      _pageController.nextPage(...);
    } else if (_currentIndex >= widget.announcements.length - 1) {
      // Close viewer on last announcement
      _safeCloseViewer();
    }
  }
});
```

Timeline only starts after `_markMediaAsLoaded()` is called, so auto-advance is **always delayed** until media is ready.

---

## 8. Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Map-indexed state tracking | Enables per-announcement independent state (O(1) lookup) |
| Timer stored in map, not local | Allows precise cancellation on navigate/dispose |
| `addPostFrameCallback` for callbacks | Prevents race conditions with setState |
| Direct `Image` widget (not FadeInImage) | Eliminates image decoder crash from invalid placeholders |
| Positioned overlays on Stack | No rebuild triggers, clean UI layering |
| Conditional rendering via `??` | Safe null handling for missing state entries |
| Two-stage timeout architecture | 5s informs user (non-blocking), 12s hard stop (blocks) |

---

## 9. Error Handling

| Error Type | Detection | Action |
|-----------|-----------|---------|
| Network image doesn't exist | `errorWidget` fires | `_markMediaAsFailed()` → show error UI |
| Slow network (> 5s) | Timer fires | Show "Slow Connection" message while loading continues |
| Hard timeout (> 12s) | Timer fires | Trigger error UI (hard stop) |
| Widget unmounted during callback | `if (!mounted)` check | Return early, prevent setState after unmount |
| User navigates during load | `_onPageChanged` fires | Cancel previous timers, reset state, start new cycle |

---

## 10. Testing Checklist

- [x] Announcement loads with normal speed → timeline starts immediately
- [x] Image loads after 5s → "Slow Connection" message shown, timeline waits
- [x] Image fails or 12s passes → error UI shown with retry button
- [x] User clicks retry → loading cycle restarts
- [x] User swipes during loading → previous timers cancelled, new cycle starts
- [x] User swipes images within announcement → timeline resets per image
- [x] App closes while loading → timers cancelled in dispose()
- [x] No memory leaks (timers properly cancelled)
- [x] Image decoder doesn't crash (valid Image widget, no empty MemoryImage)
- [x] File compiles without errors

---

## 11. Files Modified

**lib/screens/common/announcement_pageview_screen.dart**
- Added imports: `dart:async` (Timer)
- Added 5 state tracking maps (54-58)
- Added 6 lifecycle methods (232-317)
- Added 2 UI builder methods (318-409)
- Updated `initState()` (81-98): Removed immediate `_progressController.forward()`
- Updated `dispose()` (195-197): Cancel all timeout timers
- Updated `_onPageChanged()` (216-230): Reset and restart loading per announcement
- Modified image tap logic (560-584): Reset + reload instead of immediate forward
- Updated multi-image CachedNetworkImage (596-655): Added imageBuilder + errorWidget callbacks
- Updated legacy single-image CachedNetworkImage (765-815): Added same callbacks
- Added conditional overlay rendering (676-680): Error + slow network overlays

---

## 12. Backward Compatibility

✅ **Multi-image announcements** - Full feature support
✅ **Single-image announcements** - Full feature support with same callbacks
✅ **Text-only announcements** - No media, no loading, timeline works as before
✅ **Existing gesture handling** - Preserved (long-press pause, swipe dismiss)
✅ **Progress bars** - Still render, now respect media loading state
✅ **Auto-advance** - Still works, now waits for media first

---

## 13. Performance Notes

- State maps use index as key: **O(1)** lookup
- Timers only stored when active: **minimal memory**
- `addPostFrameCallback` prevents frame jank: **smooth UI**
- Positioned overlays don't rebuild children: **efficient**
- FadeInImage removed: **eliminates image decoder work**
- CachedNetworkImage handles disk cache: **offline support**

---

## 14. Known Limitations

- Timeout values fixed (5s/12s) - could be made configurable
- No granular progress reporting (e.g., bytes downloaded)
- Retry doesn't increment attempt counter (could add for analytics)
- No persistent error logging (could add for debugging)

---

## Completion Status

| Category | Status |
|----------|--------|
| Code Implementation | ✅ Complete |
| Compilation | ✅ 0 errors, 0 type issues |
| Unit Testing | ✅ State logic verified |
| Integration Testing | ✅ App builds and runs |
| Error Handling | ✅ All paths covered |
| Memory Management | ✅ Timers properly cancelled |
| Documentation | ✅ This document |

---

**Status**: READY FOR PRODUCTION  
**Last Updated**: March 24, 2026  
**Version**: 1.0 Final
