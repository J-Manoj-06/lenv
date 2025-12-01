# Setup Class Subjects - Quick Guide

## Option 1: Firebase Console (Manual)

Go to Firebase Console → Firestore Database → Add Collection

### For Grade 10-A Students:

1. **Create Collection**: `classes`
2. **Create Document**: `10-A` (use the exact format your students have in their profile)
3. **Add Subcollection**: `subjects`
4. **Add Documents** (one for each subject):

#### English
```
Document ID: english
Fields:
  name: "English"
  teacherName: "Mr. Rajesh Kumar"
  icon: "📖"
```

#### Hindi
```
Document ID: hindi
Fields:
  name: "Hindi"
  teacherName: "Mr. Rajesh Kumar"
  icon: "📚"
```

#### Mathematics
```
Document ID: mathematics
Fields:
  name: "Mathematics"
  teacherName: "Ms. Priya Singh"
  icon: "🔢"
```

#### Science
```
Document ID: science
Fields:
  name: "Science"
  teacherName: "Dr. Amit Patel"
  icon: "🔬"
```

#### Social Studies
```
Document ID: social_studies
Fields:
  name: "Social Studies"
  teacherName: "Mrs. Anita Sharma"
  icon: "🌍"
```

---

## Option 2: Quick Firestore Rules Script

Copy this to Firebase Console → Firestore → Rules (temporary):

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;  // ⚠️ TEMPORARY - Remove after setup
    }
  }
}
```

Then run this in your browser console while on Firebase Console:

```javascript
// PASTE THIS IN BROWSER CONSOLE ON FIREBASE CONSOLE PAGE
const db = firebase.firestore();

const subjects10A = [
  { id: 'english', name: 'English', teacherName: 'Mr. Rajesh Kumar', icon: '📖' },
  { id: 'hindi', name: 'Hindi', teacherName: 'Mr. Rajesh Kumar', icon: '📚' },
  { id: 'mathematics', name: 'Mathematics', teacherName: 'Ms. Priya Singh', icon: '🔢' },
  { id: 'science', name: 'Science', teacherName: 'Dr. Amit Patel', icon: '🔬' },
  { id: 'social_studies', name: 'Social Studies', teacherName: 'Mrs. Anita Sharma', icon: '🌍' },
];

async function setupSubjects() {
  const batch = db.batch();
  
  subjects10A.forEach(subject => {
    const ref = db.collection('classes').doc('10-A').collection('subjects').doc(subject.id);
    batch.set(ref, {
      name: subject.name,
      teacherName: subject.teacherName,
      icon: subject.icon
    });
  });
  
  await batch.commit();
  console.log('✅ Subjects created successfully!');
}

setupSubjects();
```

---

## Option 3: Node.js Script (If you have Firebase Admin SDK)

Run the `setup_class_subjects.js` file:

```bash
cd functions
node setup_class_subjects.js
```

---

## Important: Check Student's Class Format

Your students have `className: "Grade 10"` and `section: "A"` in their profile.

The `getStudentClassId()` function converts this to `"10-A"`.

**Make sure your Firestore collection matches this format:**
- ✅ Correct: `classes/10-A/subjects/...`
- ❌ Wrong: `classes/Grade 10-A/subjects/...`

---

## Verify Setup

After adding subjects, check in Firestore:

```
classes/
  └─ 10-A/
      └─ subjects/
          ├─ english/
          │   ├─ name: "English"
          │   ├─ teacherName: "Mr. Rajesh Kumar"
          │   └─ icon: "📖"
          ├─ hindi/
          │   ├─ name: "Hindi"
          │   ├─ teacherName: "Mr. Rajesh Kumar"
          │   └─ icon: "📚"
          └─ ... (other subjects)
```

---

## Test in App

1. Hot reload/restart your app
2. Navigate to Messages tab
3. Click GROUPS
4. You should see all subjects for the student's class (Grade 10-A)
5. Click any subject to open the group chat

---

## Add More Classes

Repeat the same structure for other classes:
- `classes/10-B/subjects/...`
- `classes/11-A/subjects/...`
- `classes/12-A/subjects/...`
- etc.
