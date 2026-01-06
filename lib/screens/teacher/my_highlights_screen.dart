import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/status_model.dart';
import 'status_view_screen.dart';

/// Screen showing teacher's own classroom highlights/statuses
class MyHighlightsScreen extends StatelessWidget {
  const MyHighlightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final teacherId = authProvider.currentUser?.uid;

    if (teacherId == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'My Highlights',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'My Highlights',
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('class_highlights')
            .where('teacherId', isEqualTo: teacherId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final statuses = docs
              .map((d) => StatusModel.fromFirestore(d))
              .toList();

          if (statuses.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.highlight_off,
                    size: 80,
                    color: theme.iconTheme.color?.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No highlights yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first classroom highlight\nfrom the dashboard',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: statuses.length,
            itemBuilder: (context, index) {
              final status = statuses[index];
              return _HighlightCard(
                status: status,
                onTap: () => _viewStatus(context, statuses, index, teacherId),
                onDelete: () => _deleteStatus(context, status.id),
              );
            },
          );
        },
      ),
    );
  }

  void _viewStatus(
    BuildContext context,
    List<StatusModel> statuses,
    int index,
    String currentUserId,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatusViewScreen(
          statuses: statuses,
          initialIndex: index,
          currentUserId: currentUserId,
          onStatusDeleted: () {
            // Refresh handled by StreamBuilder
          },
        ),
      ),
    );
  }

  Future<void> _deleteStatus(BuildContext context, String statusId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Highlight?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('class_highlights')
            .doc(statusId)
            .delete();
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Highlight deleted')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }
}

class _HighlightCard extends StatelessWidget {
  final StatusModel status;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HighlightCard({
    required this.status,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpired = !status.isValid;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7E57C2), Color(0xFFB388FF)],
                      ),
                    ),
                    child: status.hasImage
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              status.imageUrl!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.text_fields, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status.className,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatDate(status.createdAt)} • ${status.timeRemainingFormatted}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isExpired ? Colors.red : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onDelete,
                  ),
                ],
              ),

              if (status.hasText) ...[
                const SizedBox(height: 12),
                Text(
                  status.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Audience badge
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Chip(
                    avatar: Icon(
                      _getAudienceIcon(status.audienceType),
                      size: 16,
                      color: Colors.white,
                    ),
                    label: Text(_getAudienceLabel(status)),
                    backgroundColor: const Color(0xFF7E57C2),
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  if (isExpired)
                    const Chip(
                      label: Text('Expired'),
                      backgroundColor: Colors.red,
                      labelStyle: TextStyle(color: Colors.white, fontSize: 12),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getAudienceIcon(String audienceType) {
    switch (audienceType) {
      case 'school':
        return Icons.school;
      case 'standard':
        return Icons.class_;
      case 'section':
        return Icons.group;
      default:
        return Icons.public;
    }
  }

  String _getAudienceLabel(StatusModel status) {
    switch (status.audienceType) {
      case 'school':
        return 'Entire School';
      case 'standard':
        return 'Standards: ${status.standards.join(", ")}';
      case 'section':
        return 'Sections: ${status.sections.join(", ")}';
      default:
        return 'Unknown';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
