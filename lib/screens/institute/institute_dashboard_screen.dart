import 'package:flutter/material.dart';

const Color _backgroundDark = Color(0xFF0F172A); // slate-900
const Color _cardColor = Color(0xFF1E293B); // slate-800
const Color _teal = Color(0xFF146D7A); // custom teal
const Color _slate400 = Color(0xFF94A3B8);

class InstituteDashboardScreen extends StatelessWidget {
  const InstituteDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stories = _buildStories();

    return Scaffold(
      backgroundColor: _backgroundDark,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopBar(teal: _teal),
              const _SectionHeader(title: 'Announcements'),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, index) {
                      final item = stories[index];
                      if (item.isAddButton) {
                        return const _AddStoryButton();
                      }
                      return _StoryAvatar(
                        name: item.title,
                        imageUrl: item.imageUrl,
                        teal: _teal,
                        labelColor: _slate400,
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemCount: stories.length,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: const [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.school,
                        label: 'Total Students',
                        value: '1,240',
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.group,
                        label: 'Total Staff',
                        value: '85',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _AttendanceCard(percentage: 0.92),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _QuickActionCard(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  List<_StoryItem> _buildStories() {
    return const [
      _StoryItem(isAddButton: true),
      _StoryItem(
        title: 'Mr. Smith',
        imageUrl:
            'https://lh3.googleusercontent.com/aida-public/AB6AXuAxYMuOwpb1DLblA9biHKSJw_DnR0jgUcdOHHs1MTclYl1mAxPIvZB4OhuavM3fbAIAVlRr-xUROUhpB8cT4EQ3kGwqtqh2TxPUImWGgyzQ21btC-c1Hy1g4SYt_VQOEYXILABA8LvS2xR6_ziihVp92FCWzWaK36uijGu_PWjqASbCSRTXJEHNKu-ery0UvupF7U7Zf6J5gihogANYY8wvbNr7OVrlNFygnjcZDqy6TsTQae5ZtwbWQuhmq2O41tIcOuXsdqxUlAi6',
      ),
      _StoryItem(
        title: 'Ms. Jones',
        imageUrl:
            'https://lh3.googleusercontent.com/aida-public/AB6AXuAxYMuOwpb1DLblA9biHKSJw_DnR0jgUcdOHHs1MTclYl1mAxPIvZB4OhuavM3fbAIAVlRr-xUROUhpB8cT4EQ3kGwqtqh2TxPUImWGgyzQ21btC-c1Hy1g4SYt_VQOEYXILABA8LvS2xR6_ziihVp92FCWzWaK36uijGu_PWjqASbCSRTXJEHNKu-ery0UvupF7U7Zf6J5gihogANYY8wvbNr7OVrlNFygnjcZDqy6TsTQae5ZtwbWQuhmq2O41tIcOuXsdqxUlAi6',
      ),
      _StoryItem(
        title: 'Event',
        imageUrl:
            'https://lh3.googleusercontent.com/aida-public/AB6AXuAxYMuOwpb1DLblA9biHKSJw_DnR0jgUcdOHHs1MTclYl1mAxPIvZB4OhuavM3fbAIAVlRr-xUROUhpB8cT4EQ3kGwqtqh2TxPUImWGgyzQ21btC-c1Hy1g4SYt_VQOEYXILABA8LvS2xR6_ziihVp92FCWzWaK36uijGu_PWjqASbCSRTXJEHNKu-ery0UvupF7U7Zf6J5gihogANYY8wvbNr7OVrlNFygnjcZDqy6TsTQae5ZtwbWQuhmq2O41tIcOuXsdqxUlAi6',
      ),
      _StoryItem(
        title: 'Team',
        imageUrl:
            'https://lh3.googleusercontent.com/aida-public/AB6AXuAxYMuOwpb1DLblA9biHKSJw_DnR0jgUcdOHHs1MTclYl1mAxPIvZB4OhuavM3fbAIAVlRr-xUROUhpB8cT4EQ3kGwqtqh2TxPUImWGgyzQ21btC-c1Hy1g4SYt_VQOEYXILABA8LvS2xR6_ziihVp92FCWzWaK36uijGu_PWjqASbCSRTXJEHNKu-ery0UvupF7U7Zf6J5gihogANYY8wvbNr7OVrlNFygnjcZDqy6TsTQae5ZtwbWQuhmq2O41tIcOuXsdqxUlAi6',
      ),
      _StoryItem(
        title: 'General',
        imageUrl:
            'https://lh3.googleusercontent.com/aida-public/AB6AXuAxYMuOwpb1DLblA9biHKSJw_DnR0jgUcdOHHs1MTclYl1mAxPIvZB4OhuavM3fbAIAVlRr-xUROUhpB8cT4EQ3kGwqtqh2TxPUImWGgyzQ21btC-c1Hy1g4SYt_VQOEYXILABA8LvS2xR6_ziihVp92FCWzWaK36uijGu_PWjqASbCSRTXJEHNKu-ery0UvupF7U7Zf6J5gihogANYY8wvbNr7OVrlNFygnjcZDqy6TsTQae5ZtwbWQuhmq2O41tIcOuXsdqxUlAi6',
      ),
    ];
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.teal});

  final Color teal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              image: const DecorationImage(
                image: NetworkImage(
                  'https://lh3.googleusercontent.com/aida-public/AB6AXuC4rLa-okXKewTcUXRfoGDRTz_zPBMuwI1SrwYIn89cU3YlQu5KQne8DGaF4rcKRVUOr-yBGxx6pEr30ZiC-a2D16o5r8svt6AFFJ5b9nAaZdR4CYbHVTbVCQEHD6G1nV8NnrRKY97DY-VuBfzWgJ5kpSR1-H9RNXvtMNT43Sr1_seTS53O9b4EfnIal8WIURyhqQpSu3uIL124NWamYDjuMknLmg3_HYhouqKgcLuwmU6KlxgMzkv8QmcS78Ckj9k-nIyon8gixkYi',
                ),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Good Morning, Principal',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.account_circle,
              color: Colors.white,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StoryItem {
  const _StoryItem({
    this.title = '',
    this.imageUrl = '',
    this.isAddButton = false,
  });

  final String title;
  final String imageUrl;
  final bool isAddButton;
}

class _AddStoryButton extends StatelessWidget {
  const _AddStoryButton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            Positioned(
              bottom: -4,
              right: -4,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _teal,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Add New', style: TextStyle(color: _slate400, fontSize: 13)),
      ],
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({
    required this.name,
    required this.imageUrl,
    required this.teal,
    required this.labelColor,
  });

  final String name;
  final String imageUrl;
  final Color teal;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: teal, width: 2),
          ),
          child: ClipOval(child: Image.network(imageUrl, fit: BoxFit.cover)),
        ),
        const SizedBox(height: 6),
        Text(name, style: TextStyle(color: labelColor, fontSize: 13)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _teal),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: _slate400,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.percentage});

  final double percentage;

  @override
  Widget build(BuildContext context) {
    final percentText = '${(percentage * 100).round()}%';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Today's Attendance",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                percentText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              FractionallySizedBox(
                widthFactor: percentage.clamp(0, 1),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: _teal,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.campaign, color: _teal),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Broadcast Message',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Send a message to all staff',
                  style: TextStyle(color: _slate400, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: _teal,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_forward, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
