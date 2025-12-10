import 'package:dio/dio.dart';

class CloudflareService {
  // ✅ YOUR WORKER URL AND API KEY
  static const String baseUrl =
      'https://school-management-worker.giridharannj.workers.dev';
  static const String apiKey =
      'Lehirtb-HyGilYghbkbOH-boevytbGityalmNmbhBvdNBMASHBDSbdndBNNVzXCVZFccgjXjnv';

  final Dio _dio = Dio();

  // 1. Upload File (PDF, JPG, PNG)
  Future<String> uploadFile(String filePath) async {
    try {
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });

      final response = await _dio.post(
        '$baseUrl/uploadFile',
        data: formData,
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );

      return response.data['fileUrl'];
    } catch (e) {
      throw 'Upload failed: $e';
    }
  }

  // 2. Delete File
  Future<bool> deleteFile(String fileName) async {
    try {
      await _dio.post(
        '$baseUrl/deleteFile',
        data: {'fileName': fileName},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );
      return true;
    } catch (e) {
      throw 'Delete failed: $e';
    }
  }

  // 3. Get Signed URL (temporary access)
  Future<String> getSignedUrl(String fileName) async {
    try {
      final response = await _dio.get(
        '$baseUrl/signedUrl',
        queryParameters: {'fileName': fileName},
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );
      return response.data['signedUrl'];
    } catch (e) {
      throw 'Failed to get signed URL: $e';
    }
  }

  // 4. Post Announcement
  Future<Map<String, dynamic>> postAnnouncement({
    required String title,
    required String message,
    required String targetAudience,
    String? standard,
    String? fileUrl,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/announcement',
        data: {
          'title': title,
          'message': message,
          'targetAudience': targetAudience,
          if (standard != null) 'standard': standard,
          if (fileUrl != null) 'fileUrl': fileUrl,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );
      return response.data;
    } catch (e) {
      throw 'Failed to post announcement: $e';
    }
  }

  // 5. Post Group Message
  Future<Map<String, dynamic>> postGroupMessage({
    required String groupId,
    required String senderId,
    required String messageText,
    String? fileUrl,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/groupMessage',
        data: {
          'groupId': groupId,
          'senderId': senderId,
          'messageText': messageText,
          if (fileUrl != null) 'fileUrl': fileUrl,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );
      return response.data;
    } catch (e) {
      throw 'Failed to post message: $e';
    }
  }

  // 6. Schedule Test
  Future<Map<String, dynamic>> scheduleTest({
    required String classId,
    required String subject,
    required String date,
    required String time,
    required int duration,
    required String createdBy,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/scheduleTest',
        data: {
          'classId': classId,
          'subject': subject,
          'date': date,
          'time': time,
          'duration': duration,
          'createdBy': createdBy,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );
      return response.data;
    } catch (e) {
      throw 'Failed to schedule test: $e';
    }
  }

  // 7. Check Status (health check)
  Future<bool> checkStatus() async {
    try {
      final response = await _dio.get('$baseUrl/status');
      return response.data['ok'] == true;
    } catch (e) {
      return false;
    }
  }
}
