# Performance Optimization - Group Message Page Loading

**Issue 1: 2-3 Second Loading Delay**
- Root Cause: `convertToMessageGroup()` does 3 sequential Firestore queries per group:
  1. `getStudentCount()` - Query students collection
  2. `getLastMessage()` - Query messages collection
  3. `getUnreadCount()` - Query messages collection again
- When loading 5-10 groups, this becomes: 15-30 Firestore queries!

**Issue 2: Unread Badge Persistence**
- Root Cause: Unread count is stored in MessageGroup data structure
- When teacher exits chat, `_loadGroups()` is called but the old data might show briefly
- Badge shows stale count because it's not being cleared/reset

**Solution:**
1. Cache group data in memory (5-minute TTL)
2. Make unread count queries optional (lazy load)
3. Reset unread counts when entering chat
4. Show instant UI with placeholder data
5. Update in background without blocking UI

