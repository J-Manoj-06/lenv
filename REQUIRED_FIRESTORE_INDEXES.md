# Required Firestore Indexes

To support efficient queries and avoid FAILED_PRECONDITION errors, create the following composite indexes in your Firebase Firestore project.

## tests collection
- Fields:
  - teacherId (Ascending)
  - createdAt (Descending)

You can create it quickly using this generated link (for project `lenv-cb08e`):

- https://console.firebase.google.com/v1/r/project/lenv-cb08e/firestore/indexes?create_composite=Ckhwcm9qZWN0cy9sZW52LWNiMDhlL2RhdGFiYXNlcy8oZGVmYXVsdCkvY29sbGVjdGlvbkdyb3Vwcy90ZXN0cy9pbmRleGVzL18QARoNCgl0ZWFjaGVySWQQARoNCgljcmVhdGVkQXQQAhoMCghfX25hbWVfXxAC

## Optional: rewards collection
- Fields:
  - studentId (Ascending)
  - createdAt (Descending)

This index is only needed if you see an index error when viewing rewards ordered by `createdAt`.

## Notes
- After creating an index, it may take 1–2 minutes to build. While building, queries will still fail with the index error.
- We temporarily sort client-side to avoid blocking the UI (see `FirestoreService.getTestsByTeacher` and `getRewardsByStudent`). Once the index is built, you can switch back to server-side ordering if desired for large datasets.
