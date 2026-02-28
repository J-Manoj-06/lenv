import 'package:flutter/material.dart';

import '../../services/mindmap_service.dart';
import 'mindmap_review_page.dart';

class MindmapCreatePage extends StatefulWidget {
  final String classId;
  final String subjectId;
  final String teacherId;
  final String teacherName;
  final VoidCallback? onMindmapSent;

  const MindmapCreatePage({
    super.key,
    required this.classId,
    required this.subjectId,
    required this.teacherId,
    required this.teacherName,
    this.onMindmapSent,
  });

  @override
  State<MindmapCreatePage> createState() => _MindmapCreatePageState();
}

class _MindmapCreatePageState extends State<MindmapCreatePage> {
  final TextEditingController _topicController = TextEditingController();
  final MindmapService _mindmapService = MindmapService();

  int _topicCount = 4;
  String _depthLevel = 'Medium';
  String _learningStyle = 'Concept Based';
  bool _isGenerating = false;

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a topic')));
      return;
    }

    setState(() => _isGenerating = true);
    try {
      print('🎯 [MindmapCreatePage] Starting generation for topic: $topic');
      final structure = await _mindmapService.generateMindmapDraft(
        classId: widget.classId,
        subjectId: widget.subjectId,
        topic: topic,
        topicCount: _topicCount,
        depthLevel: _depthLevel,
        learningStyle: _learningStyle,
      );

      print(
        '✅ [MindmapCreatePage] Generation successful, structure keys: ${structure.keys}',
      );
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/teacher/group/mindmap/review'),
          builder: (_) => MindmapReviewPage(
            classId: widget.classId,
            subjectId: widget.subjectId,
            teacherId: widget.teacherId,
            teacherName: widget.teacherName,
            topic: topic,
            topicCount: _topicCount,
            depthLevel: _depthLevel,
            learningStyle: _learningStyle,
            initialStructure: structure,
            onMindmapSent: widget.onMindmapSent,
          ),
        ),
      );
    } catch (e) {
      print('❌ [MindmapCreatePage] Error: $e');
      print('❌ [MindmapCreatePage] Stack trace: $e');
      if (!mounted) return;
      final msg = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate mindmap: $msg'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Create Learning Mindmap'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            child: TextField(
              controller: _topicController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Topic',
                hintText: 'Enter the concept or chapter',
              ),
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Number of Main Branches',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    IconButton(
                      onPressed: _topicCount > 3
                          ? () => setState(() => _topicCount--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$_topicCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      onPressed: _topicCount < 8
                          ? () => setState(() => _topicCount++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    const Spacer(),
                    const Text(
                      'Range: 3-8',
                      style: TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            child: DropdownButtonFormField<String>(
              value: _depthLevel,
              dropdownColor: const Color(0xFF1F1F24),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Depth Level'),
              items: const [
                DropdownMenuItem(value: 'Basic', child: Text('Basic')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                DropdownMenuItem(value: 'Advanced', child: Text('Advanced')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _depthLevel = value);
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Learning Style',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['Concept Based', 'Question Based', 'Example Based']
                      .map((style) {
                        return ChoiceChip(
                          selected: _learningStyle == style,
                          label: Text(style),
                          onSelected: (_) =>
                              setState(() => _learningStyle = style),
                        );
                      })
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7A5CFF), Color(0xFF5A39E6)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _isGenerating ? null : _generate,
                child: _isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Generate Mindmap'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181D),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            labelStyle: TextStyle(color: Colors.white70),
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF303040)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF7A5CFF), width: 1.4),
            ),
          ),
          chipTheme: Theme.of(context).chipTheme.copyWith(
            selectedColor: const Color(0xFF7A5CFF),
            backgroundColor: const Color(0xFF232331),
            labelStyle: const TextStyle(color: Colors.white),
            secondaryLabelStyle: const TextStyle(color: Colors.white),
          ),
        ),
        child: child,
      ),
    );
  }
}
