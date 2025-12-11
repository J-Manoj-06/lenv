# 📱 Media Upload Type Decision Tree

```
                    User Uploads Media
                           |
                           v
              What type of content is this?
                           |
        ┌──────────────────┼──────────────────┐
        v                  v                  v
   📢 Announcement    💬 Message         👥 Community
   (Time-sensitive)   (Personal)        (Group)
        |                  |                  |
        v                  v                  v
  mediaType=          mediaType=         mediaType=
  'announcement'      'message'          'community'
        |                  |                  |
        v                  v                  v
   ⏰ 24-hour         ♾️ Permanent       ♾️ Permanent
   auto-delete        storage            storage
        |                  |                  |
        v                  v                  v
   After 24h:         Never deleted     Never deleted
   1. Delete R2       Stored in:        Stored in:
   2. Delete          - R2 (file)       - R2 (file)
      thumbnail       - Firestore       - Firestore
   3. Set deletedAt     (metadata)        (metadata)
      in Firestore
```

---

## 🔄 Lifecycle Comparison

### Announcement Media (Ephemeral)
```
Hour 0  ──► Upload to R2 ──► Save to Firestore (mediaType='announcement')
             ✅ Active       ✅ Visible in app

Hour 12 ──► Still in R2 ──► Still in Firestore
             ✅ Active       ✅ Visible in app

Hour 24 ──► Still in R2 ──► Still in Firestore
             ✅ Active       ✅ Visible in app

Hour 25 ──► Cloud Function Runs:
             ❌ Delete R2    ✅ Firestore (deletedAt set)
             ❌ Deleted      ⚠️ Soft-deleted (hidden in app)

Day 30  ──► Hard Delete:
             ❌ R2 gone      ❌ Firestore document removed
```

### Message/Community Media (Permanent)
```
Hour 0  ──► Upload to R2 ──► Save to Firestore (mediaType='message')
             ✅ Active       ✅ Visible in app

Hour 24 ──► Still in R2 ──► Still in Firestore
             ✅ Active       ✅ Visible in app

Day 30  ──► Still in R2 ──► Still in Firestore
             ✅ Active       ✅ Visible in app

Year 1  ──► Still in R2 ──► Still in Firestore
             ✅ Active       ✅ Visible in app
                            ♾️ Never auto-deleted
```

---

## 🎯 Use Case Examples

### ✅ CORRECT Usage

| Scenario | mediaType | Reasoning |
|----------|-----------|-----------|
| Principal posts school event poster | `'announcement'` | Event is time-sensitive, no need to keep after 24h |
| Teacher shares homework assignment PDF | `'message'` | Students need to reference it multiple times |
| Student sends photo to friend | `'message'` | Personal chat, should remain permanent |
| Teacher posts study material in group | `'community'` | Educational resource, needed long-term |
| Admin posts exam schedule | `'announcement'` | Time-sensitive notification |
| Parent shares child's achievement photo | `'message'` | Personal memory, should be permanent |

---

### ❌ INCORRECT Usage

| Scenario | Wrong Type | Why It's Wrong | Correct Type |
|----------|------------|----------------|--------------|
| Teacher shares lesson notes | `'announcement'` | Will be deleted! Students can't review later | `'message'` or `'community'` |
| Student uploads project submission | `'announcement'` | Important document will disappear! | `'message'` |
| Sharing study group resources | `'announcement'` | Students need ongoing access | `'community'` |
| Time-sensitive alert | `'message'` | Will clutter storage unnecessarily | `'announcement'` |

---

## 🔧 Implementation Checklist

### Code Changes ✅
- [x] MediaMessage model updated with `mediaType` field
- [x] MediaUploadService accepts `mediaType` parameter
- [x] MediaChatProvider uses correct mediaType
- [x] Cloud Functions created for auto-deletion

### Deployment 📋
- [ ] npm install in functions directory
- [ ] Configure R2 credentials in functions/.env
- [ ] Deploy Cloud Functions to Firebase
- [ ] Verify functions appear in Firebase Console
- [ ] Test announcement upload with 24h deletion
- [ ] Monitor function logs for first cycle

### Testing 🧪
- [ ] Upload announcement media
- [ ] Upload message media  
- [ ] Upload community media
- [ ] Wait 25 hours
- [ ] Verify announcement deleted, others remain
- [ ] Check function logs for success
- [ ] Query Firestore for deletedAt timestamp

---

## 📊 Storage Cost Comparison

### Before Implementation
```
All media stored permanently:
├─ Announcements: 1000 files × 2MB = 2 GB
├─ Messages: 800 files × 1.5MB = 1.2 GB
└─ Community: 600 files × 1.8MB = 1.08 GB
Total: 4.28 GB × $0.015/GB/month = $0.064/month
```

### After Implementation (After 30 Days)
```
Only permanent media stored:
├─ Announcements: 0 files (auto-deleted) = 0 GB
├─ Messages: 800 files × 1.5MB = 1.2 GB
└─ Community: 600 files × 1.8MB = 1.08 GB
Total: 2.28 GB × $0.015/GB/month = $0.034/month
Savings: $0.030/month (47% reduction)
```

**Note**: Savings scale with usage. Higher volume = greater savings.

---

## 🚨 Critical Reminders

### For Developers
1. **Always specify mediaType** when calling `uploadMedia()`
2. **Default is 'message'** (permanent) - safe default
3. **Use 'announcement' only** for truly ephemeral content
4. **Test thoroughly** - deleted media cannot be recovered from R2

### For Admins
1. **Backup important announcements** before 24h if needed
2. **Inform users** about 24h deletion policy for announcements
3. **Monitor function logs** regularly
4. **Keep R2 credentials secure** in Firebase environment config

---

## 📞 Support Resources

| Resource | Location |
|----------|----------|
| Full Setup Guide | `ANNOUNCEMENT_MEDIA_AUTO_DELETE_SETUP.md` |
| Quick Reference | `MEDIA_TYPE_QUICK_REFERENCE.md` |
| Code Examples | `lib/services/MEDIA_TYPE_DOCUMENTATION.dart` |
| Implementation Summary | `IMPLEMENTATION_SUMMARY_24HR_DELETION.md` |
| Cloud Function Code | `functions/deleteExpiredMediaAnnouncements.js` |

---

## ✨ Key Takeaways

✅ Announcements → 24-hour auto-delete → `mediaType: 'announcement'`  
✅ Messages → Permanent → `mediaType: 'message'`  
✅ Communities → Permanent → `mediaType: 'community'`  
✅ Default → Safe (permanent) → Defaults to `'message'`  
✅ Cost Optimized → ~50% R2 storage reduction  
✅ Fully Automated → Cloud Functions run on schedule  
✅ WhatsApp-Style → Familiar UX pattern  

**Implementation Status**: ✅ **Complete and ready for deployment**
