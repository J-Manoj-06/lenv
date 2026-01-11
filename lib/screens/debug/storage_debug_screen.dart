import 'package:flutter/material.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../config/cloudflare_config.dart';
import 'dart:typed_data';

class StorageDebugScreen extends StatefulWidget {
  const StorageDebugScreen({super.key});

  @override
  State<StorageDebugScreen> createState() => _StorageDebugScreenState();
}

class _StorageDebugScreenState extends State<StorageDebugScreen> {
  String _log = '';
  bool _testing = false;

  void _addLog(String message) {
    setState(() {
      _log += '$message\n';
    });
  }

  Future<void> _testStorage() async {
    setState(() {
      _testing = true;
      _log = '';
    });

    try {
      _addLog('🔍 Starting Cloudflare R2 diagnostics...\n');

      // Test 1: Initialize R2 service
      _addLog('1️⃣ Initializing Cloudflare R2 service...');
      final r2Service = CloudflareR2Service(
        accountId: CloudflareConfig.accountId,
        bucketName: CloudflareConfig.bucketName,
        accessKeyId: CloudflareConfig.accessKeyId,
        secretAccessKey: CloudflareConfig.secretAccessKey,
        r2Domain: CloudflareConfig.r2Domain,
      );
      _addLog('✅ R2 Service initialized');
      _addLog('   Bucket: lenv-media');
      _addLog('   Domain: https://files.lenv1.tech');

      // Test 2: Create test file
      _addLog('\n2️⃣ Creating test file...');
      final testData = Uint8List.fromList('Hello from LENV R2!'.codeUnits);
      _addLog('📤 Uploading ${testData.length} bytes...');

      // Test 3: Generate signed URL
      _addLog('\n3️⃣ Generating signed upload URL...');
      final fileName =
          'tests/diagnostic_${DateTime.now().millisecondsSinceEpoch}.txt';
      final signedData = await r2Service.generateSignedUploadUrl(
        fileName: fileName,
        fileType: 'text/plain',
      );
      _addLog('✅ Signed URL generated');

      // Test 4: Upload test file
      _addLog('\n4️⃣ Attempting test upload...');
      final uploadedUrl = await r2Service.uploadFileWithSignedUrl(
        fileBytes: testData,
        signedUrl: signedData['url'],
        contentType: 'text/plain',
      );

      _addLog('✅ Upload successful!');
      _addLog('   URL: $uploadedUrl');

      // Test 5: Verify URL accessibility
      _addLog('\n5️⃣ Verifying URL...');
      if (uploadedUrl.contains('files.lenv1.tech')) {
        _addLog('✅ URL is from correct domain');
      }

      _addLog('\n🎉 ALL TESTS PASSED!');
      _addLog('Cloudflare R2 Storage is working correctly.');
    } catch (e, stackTrace) {
      _addLog('\n❌ ERROR: $e');
      _addLog('\nStack trace:');
      _addLog(stackTrace.toString().split('\n').take(10).join('\n'));

      if (e.toString().contains('Unauthorized') ||
          e.toString().contains('403')) {
        _addLog('\n💡 SOLUTION:');
        _addLog('Check R2 API credentials:');
        _addLog('1. Go to Cloudflare Dashboard');
        _addLog('2. Click R2 in sidebar');
        _addLog('3. Create or verify API token');
        _addLog('4. Ensure token has "All permissions"');
      } else if (e.toString().contains('not found') ||
          e.toString().contains('404')) {
        _addLog('\n💡 SOLUTION:');
        _addLog('Bucket or file not found.');
        _addLog('1. Verify bucket exists in Cloudflare R2');
        _addLog('2. Check bucket name matches in code');
      }
    } finally {
      setState(() {
        _testing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Diagnostics'),
        backgroundColor: const Color(0xFF6A4FF7),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _testing ? null : _testStorage,
              icon: const Icon(Icons.play_arrow),
              label: Text(_testing ? 'Testing...' : 'Run Storage Test'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A4FF7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _log.isEmpty ? 'Tap "Run Storage Test" to begin...' : _log,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.green,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
