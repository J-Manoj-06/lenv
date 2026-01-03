import 'dart:io';
import 'cloudflare_r2_service.dart';
import '../config/cloudflare_config.dart';

class StorageService {
  final CloudflareR2Service _r2Service = CloudflareR2Service(
    accountId: CloudflareConfig.accountId,
    bucketName: CloudflareConfig.bucketName,
    accessKeyId: CloudflareConfig.accessKeyId,
    secretAccessKey: CloudflareConfig.secretAccessKey,
    r2Domain: CloudflareConfig.r2Domain,
  );

  // Upload profile image
  Future<String> uploadProfileImage(File file, String userId) async {
    try {
      final fileBytes = await file.readAsBytes();
      final fileName = 'profiles/$userId.jpg';
      
      final signedData = await _r2Service.generateSignedUploadUrl(
        fileName: fileName,
        fileType: 'image/jpeg',
      );
      
      return await _r2Service.uploadFileWithSignedUrl(
        fileBytes: fileBytes,
        signedUrl: signedData['url'],
        contentType: 'image/jpeg',
      );
    } catch (e) {
      throw Exception('Failed to upload profile image: ${e.toString()}');
    }
  }

  // Upload reward image
  Future<String> uploadRewardImage(File file, String rewardId) async {
    try {
      final fileBytes = await file.readAsBytes();
      final fileName = 'rewards/$rewardId.jpg';
      
      final signedData = await _r2Service.generateSignedUploadUrl(
        fileName: fileName,
        fileType: 'image/jpeg',
      );
      
      return await _r2Service.uploadFileWithSignedUrl(
        fileBytes: fileBytes,
        signedUrl: signedData['url'],
        contentType: 'image/jpeg',
      );
    } catch (e) {
      throw Exception('Failed to upload reward image: ${e.toString()}');
    }
  }

  // Upload test attachment
  Future<String> uploadTestAttachment(
    File file,
    String testId,
    String fileName,
  ) async {
    try {
      final fileBytes = await file.readAsBytes();
      final fullPath = 'tests/$testId/$fileName';
      
      final signedData = await _r2Service.generateSignedUploadUrl(
        fileName: fullPath,
        fileType: 'application/octet-stream',
      );
      
      return await _r2Service.uploadFileWithSignedUrl(
        fileBytes: fileBytes,
        signedUrl: signedData['url'],
        contentType: 'application/octet-stream',
      );
    } catch (e) {
      throw Exception('Failed to upload test attachment: ${e.toString()}');
    }
  }

  // Delete file (R2 doesn't have direct delete in this service, would need separate implementation)
  Future<void> deleteFile(String fileName) async {
    try {
      // Note: CloudflareR2Service doesn't have deleteMedia method
      // This would need to be implemented if file deletion is required
      throw UnimplementedError('Delete not implemented for R2 service');
    } catch (e) {
      throw Exception('Failed to delete file: ${e.toString()}');
    }
  }

  // Get download URL (R2 files are directly accessible via domain)
  Future<String> getDownloadUrl(String path) async {
    try {
      return 'https://files.lenv1.tech/$path';
    } catch (e) {
      throw Exception('Failed to get download URL: ${e.toString()}');
    }
  }
}
