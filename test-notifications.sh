#!/bin/bash

echo "================================================"
echo "  Testing Notification Worker"
echo "================================================"
echo

WORKER_URL="https://lenv-notification-worker.giridharannj.workers.dev"

# Test 1: Health Check
echo "Test 1: Health Check"
echo "-------------------"
curl -X GET "${WORKER_URL}/health"
echo -e "\n"

# Test 2: Chat Notification
echo "Test 2: Send Chat Notification"
echo "-------------------------------"
curl -X POST "${WORKER_URL}/notify" \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "chat",
    "userId": "test-user-123",
    "title": "Test Message",
    "body": "This is a test notification from curl",
    "data": {
      "messageId": "msg-test-001",
      "chatId": "chat-test-001",
      "senderId": "sender-test-123"
    }
  }'
echo -e "\n"

# Test 3: Assignment Notification
echo "Test 3: Send Assignment Notification"
echo "-------------------------------------"
curl -X POST "${WORKER_URL}/notify" \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "assignment",
    "userId": "test-user-123",
    "title": "New Assignment",
    "body": "Math Assignment Due Tomorrow",
    "data": {
      "assignmentId": "assign-test-001",
      "subjectId": "math-101",
      "dueDate": "2026-02-17T23:59:59Z"
    }
  }'
echo -e "\n"

# Test 4: Announcement Notification
echo "Test 4: Send Announcement Notification"
echo "---------------------------------------"
curl -X POST "${WORKER_URL}/notify" \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "announcement",
    "userId": "test-user-123",
    "title": "School Announcement",
    "body": "Important: School holiday on Monday",
    "data": {
      "announcementId": "announce-test-001",
      "priority": "high"
    }
  }'
echo -e "\n"

echo "================================================"
echo "  Tests Complete!"
echo "================================================"
echo
echo "Check your test device with userId 'test-user-123'"
echo "Or check Firestore 'notifications' collection"
echo
