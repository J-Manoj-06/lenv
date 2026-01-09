import 'package:flutter/material.dart';

const Color _background = Color(0xFF0E0F14);
const Color _card = Color(0xFF1A1C23);
const Color _primary = Color(0xFF146D7A); // institute teal
const Color _tagText = Color(0xFF8BD3DF);
const Color _border = Color(0xFF27303A);

class InstituteMessagesScreen extends StatelessWidget {
  const InstituteMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final communities = _sampleCommunities;

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(),
            const _SearchBar(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                itemCount: communities.length,
                itemBuilder: (context, index) {
                  final c = communities[index];
                  return _CommunityCard(community: c);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: const [
          Expanded(
            child: Text(
              'Communities',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(Icons.search, color: Colors.white70),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _border, width: 0.6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: const [
            Icon(Icons.search, color: Colors.white54, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: TextField(
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search communities...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({required this.community});

  final _Community community;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _LeadingLetter(letter: community.letter),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      community.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _primary.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        community.tag,
                        style: const TextStyle(
                          color: _tagText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.22),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              community.preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadingLetter extends StatelessWidget {
  const _LeadingLetter({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _primary.withOpacity(0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: _primary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Community {
  const _Community({
    required this.title,
    required this.tag,
    required this.preview,
  });

  final String title;
  final String tag;
  final String preview;

  String get letter =>
      title.isNotEmpty ? title.characters.first.toUpperCase() : '?';
}

const List<_Community> _sampleCommunities = [
  _Community(
    title: 'Principal Announcements',
    tag: 'Whole School',
    preview: 'Tomorrow is a holiday due to weather.',
  ),
  _Community(
    title: 'Sports Community',
    tag: 'School Sports',
    preview: 'Practice moved to 4 PM today.',
  ),
  _Community(
    title: 'Events Community',
    tag: 'School Events',
    preview: 'Annual Day practice schedule updated.',
  ),
];
