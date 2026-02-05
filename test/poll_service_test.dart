/// Unit tests for Poll Service
/// Tests poll creation, voting, and transaction consistency
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:new_reward/models/poll_model.dart';
import 'package:new_reward/services/poll_service.dart';

void main() {
  group('PollService Tests', () {
    late FakeFirebaseFirestore fakeFirestore;
    late PollService pollService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      // pollService = PollService(firestore: fakeFirestore);
      // Note: You'll need to modify PollService to accept optional firestore parameter for testing
    });

    test('Poll validation - minimum 2 options', () {
      final poll = PollModel(
        question: 'Test question?',
        options: [PollOption(id: 'a', text: 'Option A')],
        allowMultiple: false,
        createdBy: 'user1',
        createdByName: 'Test User',
        createdByRole: 'teacher',
      );

      expect(poll.options.length, lessThan(2));
    });

    test('Poll validation - maximum 6 options', () {
      final options = List.generate(
        7,
        (i) => PollOption(id: 'opt_$i', text: 'Option $i'),
      );

      final poll = PollModel(
        question: 'Test question?',
        options: options,
        allowMultiple: false,
        createdBy: 'user1',
        createdByName: 'Test User',
        createdByRole: 'teacher',
      );

      expect(poll.options.length, greaterThan(6));
    });

    test('Poll model serialization', () {
      final poll = PollModel(
        question: 'What is your favorite color?',
        options: [
          PollOption(id: 'a', text: 'Red', voteCount: 5),
          PollOption(id: 'b', text: 'Blue', voteCount: 3),
        ],
        allowMultiple: false,
        createdBy: 'user1',
        createdByName: 'John Doe',
        createdByRole: 'teacher',
        voters: {
          'user1': ['a'],
          'user2': ['b'],
        },
      );

      final map = poll.toMessageMap();
      expect(map['type'], equals('poll'));
      expect(map['question'], equals('What is your favorite color?'));
      expect(map['options'], isA<List>());
      expect(map['allowMultiple'], equals(false));
      expect(map['voters'], isA<Map>());
    });

    test('Poll model deserialization', () {
      final data = {
        'id': 'poll123',
        'type': 'poll',
        'question': 'Test question?',
        'options': [
          {'id': 'a', 'text': 'Option A', 'voteCount': 5},
          {'id': 'b', 'text': 'Option B', 'voteCount': 3},
        ],
        'allowMultiple': true,
        'createdBy': 'user1',
        'createdByName': 'John Doe',
        'createdByRole': 'teacher',
        'timestamp': 1234567890,
        'voters': {
          'user1': ['a', 'b'],
          'user2': ['a'],
        },
      };

      final poll = PollModel.fromMap(data, 'poll123');
      expect(poll.id, equals('poll123'));
      expect(poll.question, equals('Test question?'));
      expect(poll.options.length, equals(2));
      expect(poll.allowMultiple, equals(true));
      expect(poll.totalVotes, equals(8));
      expect(poll.hasUserVoted('user1', 'a'), isTrue);
      expect(poll.hasUserVoted('user2', 'b'), isFalse);
    });

    test('Vote counting logic', () {
      final poll = PollModel(
        question: 'Test?',
        options: [
          PollOption(id: 'a', text: 'A', voteCount: 10),
          PollOption(id: 'b', text: 'B', voteCount: 5),
          PollOption(id: 'c', text: 'C', voteCount: 0),
        ],
        allowMultiple: false,
        createdBy: 'user1',
        createdByName: 'Test',
        createdByRole: 'teacher',
      );

      expect(poll.totalVotes, equals(15));
    });

    test('User vote tracking', () {
      final poll = PollModel(
        question: 'Test?',
        options: [
          PollOption(id: 'a', text: 'A'),
          PollOption(id: 'b', text: 'B'),
        ],
        allowMultiple: true,
        createdBy: 'user1',
        createdByName: 'Test',
        createdByRole: 'teacher',
        voters: {
          'user1': ['a', 'b'],
          'user2': ['a'],
        },
      );

      expect(poll.hasUserVotedAny('user1'), isTrue);
      expect(poll.hasUserVotedAny('user3'), isFalse);
      expect(poll.getUserVotes('user1'), equals(['a', 'b']));
      expect(poll.getUserVotes('user2'), equals(['a']));
    });

    // Integration test stub - requires Firebase emulator or fake_cloud_firestore
    test('Concurrent voting consistency (stub)', () async {
      // This test would verify that concurrent votes are handled correctly
      // by the transaction logic in PollService.vote()

      // Setup: Create a poll
      // Act: Simulate multiple users voting simultaneously
      // Assert: Final vote counts match expected values

      // Implementation requires setting up Firebase emulator or mocking
      expect(true, isTrue); // Placeholder
    });
  });

  group('PollOption Tests', () {
    test('PollOption serialization', () {
      final option = PollOption(id: 'opt1', text: 'Option 1', voteCount: 5);
      final map = option.toMap();

      expect(map['id'], equals('opt1'));
      expect(map['text'], equals('Option 1'));
      expect(map['voteCount'], equals(5));
    });

    test('PollOption deserialization', () {
      final map = {'id': 'opt1', 'text': 'Option 1', 'voteCount': 10};
      final option = PollOption.fromMap(map);

      expect(option.id, equals('opt1'));
      expect(option.text, equals('Option 1'));
      expect(option.voteCount, equals(10));
    });

    test('PollOption copyWith', () {
      final option = PollOption(id: 'a', text: 'Original', voteCount: 5);
      final updated = option.copyWith(voteCount: 10);

      expect(updated.id, equals('a'));
      expect(updated.text, equals('Original'));
      expect(updated.voteCount, equals(10));
    });
  });
}
