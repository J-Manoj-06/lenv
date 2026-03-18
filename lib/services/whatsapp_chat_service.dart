import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service to handle WhatsApp chat launching with optional auto contact save
/// This service is ONLY used for Parent-Teacher Individual Chat
class WhatsAppChatService {
  /// Start WhatsApp chat with a parent
  /// Automatically creates contact if it doesn't exist
  ///
  /// Parameters:
  /// - [studentName]: Name of the student (used for contact name)
  /// - [parentPhoneNumber]: Phone number of the parent (must include country code)
  ///
  /// Returns: true if WhatsApp was successfully opened, false otherwise
  Future<bool> startParentWhatsAppChat({
    required String studentName,
    required String parentPhoneNumber,
  }) async {
    try {
      // Clean the phone number
      final cleanedNumber = _cleanPhoneNumber(parentPhoneNumber);

      if (cleanedNumber.isEmpty) {
        return false;
      }

      // Step 1: Check and request permissions
      final hasPermission = await _checkContactsPermission();

      if (hasPermission) {
        // Step 2: Check if contact exists
        final contactExists = await _checkIfContactExists(cleanedNumber);

        // Step 3: Create contact if it doesn't exist
        if (!contactExists) {
          await _createContact(studentName, cleanedNumber);
        }
      } else {}

      // Step 4: Open WhatsApp chat
      return await _openWhatsAppChat(cleanedNumber);
    } catch (e) {
      return false;
    }
  }

  /// Check and request contacts permissions
  Future<bool> _checkContactsPermission() async {
    try {
      // Check if permissions are already granted
      final readStatus = await Permission.contacts.status;

      if (readStatus.isGranted) {
        return true;
      }

      // Request permissions
      final result = await Permission.contacts.request();

      return result.isGranted;
    } catch (e) {
      return false;
    }
  }

  /// Check if a contact with the given phone number exists
  Future<bool> _checkIfContactExists(String phoneNumber) async {
    try {
      // Fetch all contacts
      final List<Contact> contacts = await FlutterContacts.getContacts(
        withProperties: true,
      );

      // Check if any contact has this phone number
      for (final contact in contacts) {
        for (final phone in contact.phones) {
          final contactPhone = _cleanPhoneNumber(phone.number);
          if (contactPhone == phoneNumber) {
            return true;
          }
        }
      }

      return false;
    } catch (e) {
      // If we can't check, assume it doesn't exist
      return false;
    }
  }

  /// Create a new contact with the format "StudentName Parent"
  Future<void> _createContact(String studentName, String phoneNumber) async {
    try {
      final newContact = Contact(
        name: Name(first: studentName, last: 'Parent'),
        phones: [Phone(phoneNumber, label: PhoneLabel.mobile)],
      );

      await FlutterContacts.insertContact(newContact);
    } catch (e) {
      // Don't throw error, just continue to WhatsApp
    }
  }

  /// Open WhatsApp chat with the given phone number
  Future<bool> _openWhatsAppChat(String phoneNumber) async {
    try {
      // Construct WhatsApp deep link
      final whatsappUrl = 'https://wa.me/$phoneNumber';
      final uri = Uri.parse(whatsappUrl);

      // Check if WhatsApp can be launched
      final canLaunch = await canLaunchUrl(uri);

      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Clean phone number by removing spaces, hyphens, brackets, etc.
  /// Ensures the number includes country code
  String _cleanPhoneNumber(String phoneNumber) {
    // Remove all non-digit characters except +
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

    // Ensure it starts with +
    if (!cleaned.startsWith('+')) {
      // If it doesn't start with +, assume it might be missing
      // This is a fallback - ideally numbers should already have country code
      cleaned = '+$cleaned';
    }

    return cleaned;
  }
}
