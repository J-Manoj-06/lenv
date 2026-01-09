import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:new_reward/providers/media_chat_provider.dart';

class TestMediaUploadScreen extends StatefulWidget {
  const TestMediaUploadScreen({super.key});

  @override
  State<TestMediaUploadScreen> createState() => _TestMediaUploadScreenState();
}

class _TestMediaUploadScreenState extends State<TestMediaUploadScreen> {
  late MediaChatProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = MediaChatProvider(conversationId: 'test-conv-123');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📸 Test Media Upload'),
        backgroundColor: Colors.green[700],
      ),
      body: ChangeNotifierProvider<MediaChatProvider>.value(
        value: _provider,
        child: Consumer<MediaChatProvider>(
          builder: (context, provider, child) => Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // Instructions
                  Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Click a button below to upload an image.\n'
                      'Watch the progress and check:\n'
                      '1. Upload progress bar\n'
                      '2. Cloudflare R2 console\n'
                      '3. Firebase Firestore console',
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Upload Buttons
                  ElevatedButton.icon(
                    onPressed: () => provider.pickAndUploadImage(),
                    icon: const Icon(Icons.photo_library, size: 28),
                    label: const Text(
                      'Pick Image from Gallery',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  ElevatedButton.icon(
                    onPressed: () => provider.captureAndUploadImage(),
                    icon: const Icon(Icons.camera_alt, size: 28),
                    label: const Text(
                      'Capture Photo with Camera',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Upload Progress Section
                  const Text(
                    'Upload Progress:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  if (provider.uploadProgress.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No uploads yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: provider.uploadProgress.entries
                            .map(
                              (entry) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'File: ${entry.key}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: entry.value / 100,
                                        minHeight: 10,
                                        backgroundColor: Colors.grey[300],
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.green[400]!,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${entry.value.toStringAsFixed(0)}%',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Error Display
                  if (provider.currentError != null)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Error:',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            provider.currentError ?? '',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 40),

                  // Debug Info
                  Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Debug Info:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Conversation ID: test-conv-123',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'User ID: ${FirebaseAuth.instance.currentUser?.uid ?? "Not logged in"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Firestore Path: conversations/test-conv-123/media/{id}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
