import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WhatsAppEmojiPicker extends StatefulWidget {
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onBackspacePressed;
  final Color accentColor;
  final Color backgroundColor;

  const WhatsAppEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    required this.onBackspacePressed,
    required this.accentColor,
    required this.backgroundColor,
  });

  @override
  State<WhatsAppEmojiPicker> createState() => _WhatsAppEmojiPickerState();
}

class _WhatsAppEmojiPickerState extends State<WhatsAppEmojiPicker> {
  static const String _recentStorageKey = 'chat_recent_emojis_v1';
  static const int _maxRecent = 30;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _query = '';
  List<String> _recent = const <String>[];
  EmojiCategoryType _activeCategory = EmojiCategoryType.recent;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = prefs.getStringList(_recentStorageKey) ?? <String>[];
    if (!mounted) return;
    setState(() {
      _recent = loaded.take(_maxRecent).toList(growable: false);
    });
  }

  Future<void> _saveRecent(String emoji) async {
    final next = <String>[
      emoji,
      ..._recent.where((e) => e != emoji),
    ].take(_maxRecent).toList(growable: false);
    setState(() => _recent = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentStorageKey, next);
  }

  void _onScroll() {
    if (_query.isNotEmpty || !_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    double cumulative = 0;
    var detected = EmojiCategoryType.recent;
    for (final section in _visibleSections) {
      cumulative += _sectionHeight(section);
      if (offset <= cumulative - 1) {
        detected = section.type;
        break;
      }
    }
    if (detected != _activeCategory) {
      setState(() => _activeCategory = detected);
    }
  }

  List<EmojiSection> get _visibleSections {
    final recentSection = EmojiSection(
      type: EmojiCategoryType.recent,
      title: 'Recent',
      entries: _recent
          .map(
            (emoji) => EmojiEntry(
              emoji: emoji,
              name: 'recent',
              keywords: const <String>['recent'],
            ),
          )
          .toList(growable: false),
    );

    return <EmojiSection>[recentSection, ..._staticSections];
  }

  double _sectionHeight(EmojiSection section) {
    final count = section.entries.length;
    if (count == 0) return 46;
    const columns = 8;
    final rows = (count / columns).ceil();
    return 42 + (rows * 44.0) + 10;
  }

  List<EmojiEntry> get _searchResults {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const <EmojiEntry>[];

    final all = <EmojiEntry>[..._visibleSections.expand((s) => s.entries)];

    final deduped = <String, EmojiEntry>{};
    for (final item in all) {
      deduped[item.emoji] = item;
    }

    return deduped.values
        .where((item) {
          if (item.name.toLowerCase().contains(q)) return true;
          for (final keyword in item.keywords) {
            if (keyword.toLowerCase().contains(q)) return true;
          }
          return false;
        })
        .toList(growable: false);
  }

  void _handleEmojiTap(String emoji) {
    widget.onEmojiSelected(emoji);
    _saveRecent(emoji);
  }

  void _scrollToCategory(EmojiCategoryType type) {
    if (_query.isNotEmpty || !_scrollController.hasClients) return;

    double target = 0;
    for (final section in _visibleSections) {
      if (section.type == type) break;
      target += _sectionHeight(section);
    }

    _scrollController.animateTo(
      target.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );

    if (_activeCategory != type) {
      setState(() => _activeCategory = type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final muted = onSurface.withValues(alpha: isDark ? 0.62 : 0.56);

    final searching = _query.trim().isNotEmpty;
    final results = _searchResults;

    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        border: Border(
          top: BorderSide(color: onSurface.withValues(alpha: 0.08), width: 0.7),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: isDark ? 0.08 : 0.05),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Icon(Icons.search, size: 18, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      style: TextStyle(color: onSurface, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search emoji',
                        hintStyle: TextStyle(color: muted),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Backspace',
                    onPressed: widget.onBackspacePressed,
                    icon: Icon(
                      Icons.backspace_outlined,
                      size: 18,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: searching
                ? _buildSearchResults(results, muted)
                : _buildSectionsList(muted),
          ),
          if (!searching) _buildBottomNav(muted),
        ],
      ),
    );
  }

  Widget _buildSearchResults(List<EmojiEntry> results, Color muted) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(color: muted, fontSize: 13),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        childAspectRatio: 1,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        return _EmojiCell(
          emoji: item.emoji,
          onTap: () => _handleEmojiTap(item.emoji),
        );
      },
    );
  }

  Widget _buildSectionsList(Color muted) {
    final sections = _visibleSections;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        final entries = section.entries;

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
                child: Text(
                  section.title,
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (entries.isEmpty)
                const SizedBox(height: 4)
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, gridIndex) {
                    final item = entries[gridIndex];
                    return _EmojiCell(
                      emoji: item.emoji,
                      onTap: () => _handleEmojiTap(item.emoji),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomNav(Color muted) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: muted.withValues(alpha: 0.16), width: 0.6),
        ),
      ),
      child: Row(
        children: EmojiCategoryType.values
            .map((type) {
              final selected = type == _activeCategory;
              final color = selected ? widget.accentColor : muted;
              return Expanded(
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  splashRadius: 18,
                  onPressed: () => _scrollToCategory(type),
                  icon: Icon(_categoryIcon(type), size: 20, color: color),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  IconData _categoryIcon(EmojiCategoryType type) {
    switch (type) {
      case EmojiCategoryType.recent:
        return Icons.access_time_rounded;
      case EmojiCategoryType.smileys:
        return Icons.emoji_emotions_outlined;
      case EmojiCategoryType.people:
        return Icons.person_outline_rounded;
      case EmojiCategoryType.animals:
        return Icons.pets_outlined;
      case EmojiCategoryType.food:
        return Icons.fastfood_outlined;
      case EmojiCategoryType.activities:
        return Icons.sports_esports_outlined;
      case EmojiCategoryType.travel:
        return Icons.directions_car_outlined;
      case EmojiCategoryType.objects:
        return Icons.lightbulb_outline_rounded;
      case EmojiCategoryType.symbols:
        return Icons.music_note_outlined;
      case EmojiCategoryType.flags:
        return Icons.flag_outlined;
    }
  }
}

class _EmojiCell extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;

  const _EmojiCell({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Center(
        child: Text(
          emoji.characters.string,
          style: const TextStyle(fontSize: 28, height: 1),
        ),
      ),
    );
  }
}

enum EmojiCategoryType {
  recent,
  smileys,
  people,
  animals,
  food,
  activities,
  travel,
  objects,
  symbols,
  flags,
}

class EmojiEntry {
  final String emoji;
  final String name;
  final List<String> keywords;

  const EmojiEntry({
    required this.emoji,
    required this.name,
    required this.keywords,
  });
}

class EmojiSection {
  final EmojiCategoryType type;
  final String title;
  final List<EmojiEntry> entries;

  const EmojiSection({
    required this.type,
    required this.title,
    required this.entries,
  });
}

const List<EmojiSection> _staticSections = <EmojiSection>[
  EmojiSection(
    type: EmojiCategoryType.smileys,
    title: 'Smileys & Emotion',
    entries: <EmojiEntry>[
      EmojiEntry(
        emoji: '😀',
        name: 'grinning face',
        keywords: <String>['smile', 'happy', 'grin'],
      ),
      EmojiEntry(
        emoji: '😃',
        name: 'grinning face with big eyes',
        keywords: <String>['smile', 'happy', 'joy'],
      ),
      EmojiEntry(
        emoji: '😄',
        name: 'grinning face with smiling eyes',
        keywords: <String>['smile', 'happy'],
      ),
      EmojiEntry(
        emoji: '😁',
        name: 'beaming face',
        keywords: <String>['smile', 'happy'],
      ),
      EmojiEntry(
        emoji: '😊',
        name: 'smiling face with smiling eyes',
        keywords: <String>['smile', 'blush'],
      ),
      EmojiEntry(
        emoji: '🙂',
        name: 'slightly smiling face',
        keywords: <String>['smile', 'calm'],
      ),
      EmojiEntry(emoji: '😉', name: 'winking face', keywords: <String>['wink']),
      EmojiEntry(
        emoji: '😍',
        name: 'smiling face with heart eyes',
        keywords: <String>['love', 'heart'],
      ),
      EmojiEntry(
        emoji: '😘',
        name: 'face blowing kiss',
        keywords: <String>['kiss', 'love'],
      ),
      EmojiEntry(
        emoji: '😇',
        name: 'smiling face with halo',
        keywords: <String>['angel', 'good'],
      ),
      EmojiEntry(
        emoji: '😂',
        name: 'face with tears of joy',
        keywords: <String>['laugh', 'lol'],
      ),
      EmojiEntry(
        emoji: '🤣',
        name: 'rolling on the floor laughing',
        keywords: <String>['laugh', 'lol'],
      ),
      EmojiEntry(
        emoji: '🥲',
        name: 'smiling face with tear',
        keywords: <String>['happy', 'sad'],
      ),
      EmojiEntry(
        emoji: '😭',
        name: 'loudly crying face',
        keywords: <String>['cry', 'sad'],
      ),
      EmojiEntry(
        emoji: '😢',
        name: 'crying face',
        keywords: <String>['cry', 'sad'],
      ),
      EmojiEntry(
        emoji: '😎',
        name: 'smiling face with sunglasses',
        keywords: <String>['cool'],
      ),
      EmojiEntry(
        emoji: '🤔',
        name: 'thinking face',
        keywords: <String>['think', 'hmm'],
      ),
      EmojiEntry(
        emoji: '😴',
        name: 'sleeping face',
        keywords: <String>['sleep'],
      ),
      EmojiEntry(
        emoji: '😡',
        name: 'pouting face',
        keywords: <String>['angry', 'mad'],
      ),
      EmojiEntry(
        emoji: '🔥',
        name: 'fire',
        keywords: <String>['fire', 'lit', 'hot'],
      ),
      EmojiEntry(
        emoji: '❤️',
        name: 'red heart',
        keywords: <String>['love', 'heart'],
      ),
      EmojiEntry(
        emoji: '💕',
        name: 'two hearts',
        keywords: <String>['love', 'heart'],
      ),
      EmojiEntry(
        emoji: '💯',
        name: 'hundred points',
        keywords: <String>['perfect', '100'],
      ),
      EmojiEntry(
        emoji: '✨',
        name: 'sparkles',
        keywords: <String>['sparkle', 'shine'],
      ),
    ],
  ),
  EmojiSection(
    type: EmojiCategoryType.people,
    title: 'People & Body',
    entries: <EmojiEntry>[
      EmojiEntry(
        emoji: '👍',
        name: 'thumbs up',
        keywords: <String>['ok', 'yes'],
      ),
      EmojiEntry(emoji: '👎', name: 'thumbs down', keywords: <String>['no']),
      EmojiEntry(
        emoji: '👏',
        name: 'clapping hands',
        keywords: <String>['applause'],
      ),
      EmojiEntry(
        emoji: '🙌',
        name: 'raising hands',
        keywords: <String>['praise'],
      ),
      EmojiEntry(
        emoji: '🙏',
        name: 'folded hands',
        keywords: <String>['please', 'thanks'],
      ),
      EmojiEntry(
        emoji: '👋',
        name: 'waving hand',
        keywords: <String>['hi', 'bye'],
      ),
      EmojiEntry(
        emoji: '🤝',
        name: 'handshake',
        keywords: <String>['deal', 'agreement'],
      ),
      EmojiEntry(
        emoji: '💪',
        name: 'flexed biceps',
        keywords: <String>['strong'],
      ),
      EmojiEntry(emoji: '🫶', name: 'heart hands', keywords: <String>['love']),
      EmojiEntry(
        emoji: '🫡',
        name: 'saluting face',
        keywords: <String>['respect'],
      ),
      EmojiEntry(emoji: '👨', name: 'man', keywords: <String>['male']),
      EmojiEntry(emoji: '👩', name: 'woman', keywords: <String>['female']),
      EmojiEntry(emoji: '🧑', name: 'person', keywords: <String>['human']),
      EmojiEntry(emoji: '👦', name: 'boy', keywords: <String>['child']),
      EmojiEntry(emoji: '👧', name: 'girl', keywords: <String>['child']),
      EmojiEntry(
        emoji: '🧑\u200d🏫',
        name: 'teacher',
        keywords: <String>['school', 'teach'],
      ),
      EmojiEntry(
        emoji: '👨\u200d💻',
        name: 'technologist man',
        keywords: <String>['developer', 'coder'],
      ),
      EmojiEntry(
        emoji: '👩\u200d💻',
        name: 'technologist woman',
        keywords: <String>['developer', 'coder'],
      ),
      EmojiEntry(
        emoji: '🧠',
        name: 'brain',
        keywords: <String>['smart', 'idea'],
      ),
      EmojiEntry(
        emoji: '🫀',
        name: 'anatomical heart',
        keywords: <String>['heart'],
      ),
    ],
  ),
  EmojiSection(
    type: EmojiCategoryType.animals,
    title: 'Animals & Nature',
    entries: <EmojiEntry>[
      EmojiEntry(emoji: '🐶', name: 'dog face', keywords: <String>['dog']),
      EmojiEntry(emoji: '🐱', name: 'cat face', keywords: <String>['cat']),
      EmojiEntry(emoji: '🐭', name: 'mouse face', keywords: <String>['mouse']),
      EmojiEntry(
        emoji: '🐰',
        name: 'rabbit face',
        keywords: <String>['rabbit'],
      ),
      EmojiEntry(emoji: '🦁', name: 'lion', keywords: <String>['lion']),
      EmojiEntry(emoji: '🐼', name: 'panda', keywords: <String>['panda']),
      EmojiEntry(emoji: '🐸', name: 'frog', keywords: <String>['frog']),
      EmojiEntry(
        emoji: '🐵',
        name: 'monkey face',
        keywords: <String>['monkey'],
      ),
      EmojiEntry(
        emoji: '🦋',
        name: 'butterfly',
        keywords: <String>['butterfly'],
      ),
      EmojiEntry(emoji: '🐝', name: 'honeybee', keywords: <String>['bee']),
      EmojiEntry(
        emoji: '🌱',
        name: 'seedling',
        keywords: <String>['plant', 'nature'],
      ),
      EmojiEntry(
        emoji: '🌳',
        name: 'deciduous tree',
        keywords: <String>['tree'],
      ),
      EmojiEntry(emoji: '🌴', name: 'palm tree', keywords: <String>['tree']),
      EmojiEntry(
        emoji: '🌸',
        name: 'cherry blossom',
        keywords: <String>['flower'],
      ),
      EmojiEntry(
        emoji: '🌞',
        name: 'sun with face',
        keywords: <String>['sun', 'day'],
      ),
      EmojiEntry(
        emoji: '🌙',
        name: 'crescent moon',
        keywords: <String>['moon', 'night'],
      ),
      EmojiEntry(emoji: '⭐', name: 'star', keywords: <String>['star']),
      EmojiEntry(
        emoji: '⚡',
        name: 'high voltage',
        keywords: <String>['electric', 'lightning'],
      ),
      EmojiEntry(emoji: '🌈', name: 'rainbow', keywords: <String>['rainbow']),
      EmojiEntry(
        emoji: '☔',
        name: 'umbrella with rain drops',
        keywords: <String>['rain'],
      ),
    ],
  ),
  EmojiSection(
    type: EmojiCategoryType.food,
    title: 'Food & Drink',
    entries: <EmojiEntry>[
      EmojiEntry(emoji: '🍎', name: 'red apple', keywords: <String>['fruit']),
      EmojiEntry(emoji: '🍌', name: 'banana', keywords: <String>['fruit']),
      EmojiEntry(emoji: '🍇', name: 'grapes', keywords: <String>['fruit']),
      EmojiEntry(emoji: '🍉', name: 'watermelon', keywords: <String>['fruit']),
      EmojiEntry(emoji: '🥭', name: 'mango', keywords: <String>['fruit']),
      EmojiEntry(emoji: '🍕', name: 'pizza', keywords: <String>['food']),
      EmojiEntry(emoji: '🍔', name: 'hamburger', keywords: <String>['food']),
      EmojiEntry(emoji: '🍟', name: 'french fries', keywords: <String>['food']),
      EmojiEntry(emoji: '🌮', name: 'taco', keywords: <String>['food']),
      EmojiEntry(
        emoji: '🍜',
        name: 'steaming bowl',
        keywords: <String>['food'],
      ),
      EmojiEntry(emoji: '🍩', name: 'doughnut', keywords: <String>['sweet']),
      EmojiEntry(
        emoji: '🎂',
        name: 'birthday cake',
        keywords: <String>['cake'],
      ),
      EmojiEntry(emoji: '🍪', name: 'cookie', keywords: <String>['sweet']),
      EmojiEntry(
        emoji: '☕',
        name: 'hot beverage',
        keywords: <String>['coffee'],
      ),
      EmojiEntry(emoji: '🫖', name: 'teapot', keywords: <String>['tea']),
      EmojiEntry(
        emoji: '🥤',
        name: 'cup with straw',
        keywords: <String>['drink'],
      ),
      EmojiEntry(
        emoji: '🧃',
        name: 'beverage box',
        keywords: <String>['juice'],
      ),
      EmojiEntry(emoji: '🍺', name: 'beer mug', keywords: <String>['drink']),
      EmojiEntry(
        emoji: '🍽️',
        name: 'fork and knife with plate',
        keywords: <String>['meal'],
      ),
      EmojiEntry(
        emoji: '🥗',
        name: 'green salad',
        keywords: <String>['healthy'],
      ),
    ],
  ),
  EmojiSection(
    type: EmojiCategoryType.activities,
    title: 'Activities',
    entries: <EmojiEntry>[
      EmojiEntry(emoji: '⚽', name: 'soccer ball', keywords: <String>['sport']),
      EmojiEntry(emoji: '🏀', name: 'basketball', keywords: <String>['sport']),
      EmojiEntry(
        emoji: '🏏',
        name: 'cricket game',
        keywords: <String>['sport'],
      ),
      EmojiEntry(emoji: '🏸', name: 'badminton', keywords: <String>['sport']),
      EmojiEntry(emoji: '🎾', name: 'tennis', keywords: <String>['sport']),
      EmojiEntry(emoji: '🎯', name: 'direct hit', keywords: <String>['target']),
      EmojiEntry(emoji: '🎮', name: 'video game', keywords: <String>['game']),
      EmojiEntry(
        emoji: '🧩',
        name: 'puzzle piece',
        keywords: <String>['puzzle'],
      ),
      EmojiEntry(
        emoji: '🎨',
        name: 'artist palette',
        keywords: <String>['art'],
      ),
      EmojiEntry(emoji: '🎤', name: 'microphone', keywords: <String>['sing']),
      EmojiEntry(emoji: '🎧', name: 'headphone', keywords: <String>['music']),
      EmojiEntry(
        emoji: '🎬',
        name: 'clapper board',
        keywords: <String>['movie'],
      ),
      EmojiEntry(emoji: '🎲', name: 'game die', keywords: <String>['game']),
      EmojiEntry(emoji: '♟️', name: 'chess pawn', keywords: <String>['chess']),
      EmojiEntry(
        emoji: '🏆',
        name: 'trophy',
        keywords: <String>['win', 'award'],
      ),
      EmojiEntry(
        emoji: '🥇',
        name: 'first place medal',
        keywords: <String>['gold', 'award'],
      ),
      EmojiEntry(
        emoji: '🥈',
        name: 'second place medal',
        keywords: <String>['silver', 'award'],
      ),
      EmojiEntry(
        emoji: '🥉',
        name: 'third place medal',
        keywords: <String>['bronze', 'award'],
      ),
      EmojiEntry(
        emoji: '🏅',
        name: 'sports medal',
        keywords: <String>['award'],
      ),
      EmojiEntry(emoji: '🕹️', name: 'joystick', keywords: <String>['game']),
    ],
  ),
  EmojiSection(
    type: EmojiCategoryType.travel,
    title: 'Travel & Places',
    entries: <EmojiEntry>[
      EmojiEntry(emoji: '🚗', name: 'automobile', keywords: <String>['car']),
      EmojiEntry(emoji: '🚕', name: 'taxi', keywords: <String>['car']),
      EmojiEntry(emoji: '🚌', name: 'bus', keywords: <String>['transport']),
      EmojiEntry(emoji: '🚆', name: 'train', keywords: <String>['transport']),
      EmojiEntry(emoji: '✈️', name: 'airplane', keywords: <String>['flight']),
      EmojiEntry(
        emoji: '🛫',
        name: 'airplane departure',
        keywords: <String>['travel'],
      ),
      EmojiEntry(
        emoji: '🛬',
        name: 'airplane arrival',
        keywords: <String>['travel'],
      ),
      EmojiEntry(emoji: '🚀', name: 'rocket', keywords: <String>['space']),
      EmojiEntry(emoji: '🗺️', name: 'world map', keywords: <String>['map']),
      EmojiEntry(
        emoji: '🧭',
        name: 'compass',
        keywords: <String>['navigation'],
      ),
      EmojiEntry(emoji: '🏠', name: 'house', keywords: <String>['home']),
      EmojiEntry(emoji: '🏫', name: 'school', keywords: <String>['education']),
      EmojiEntry(
        emoji: '🏢',
        name: 'office building',
        keywords: <String>['work'],
      ),
      EmojiEntry(emoji: '🏥', name: 'hospital', keywords: <String>['health']),
      EmojiEntry(
        emoji: '🏖️',
        name: 'beach with umbrella',
        keywords: <String>['vacation'],
      ),
      EmojiEntry(
        emoji: '🏔️',
        name: 'snow capped mountain',
        keywords: <String>['mountain'],
      ),
      EmojiEntry(emoji: '🌋', name: 'volcano', keywords: <String>['mountain']),
      EmojiEntry(
        emoji: '🗽',
        name: 'statue of liberty',
        keywords: <String>['landmark'],
      ),
      EmojiEntry(emoji: '⛽', name: 'fuel pump', keywords: <String>['gas']),
      EmojiEntry(emoji: '🛣️', name: 'motorway', keywords: <String>['road']),
    ],
  ),
  EmojiSection(
    type: EmojiCategoryType.objects,
    title: 'Objects',
    entries: <EmojiEntry>[
      EmojiEntry(
        emoji: '📱',
        name: 'mobile phone',
        keywords: <String>['phone'],
      ),
      EmojiEntry(emoji: '💻', name: 'laptop', keywords: <String>['computer']),
      EmojiEntry(emoji: '⌚', name: 'watch', keywords: <String>['time']),
      EmojiEntry(emoji: '📷', name: 'camera', keywords: <String>['photo']),
      EmojiEntry(
        emoji: '🎥',
        name: 'movie camera',
        keywords: <String>['video'],
      ),
      EmojiEntry(emoji: '📺', name: 'television', keywords: <String>['tv']),
      EmojiEntry(emoji: '📚', name: 'books', keywords: <String>['study']),
      EmojiEntry(emoji: '📝', name: 'memo', keywords: <String>['note']),
      EmojiEntry(emoji: '✏️', name: 'pencil', keywords: <String>['write']),
      EmojiEntry(emoji: '📌', name: 'pushpin', keywords: <String>['pin']),
      EmojiEntry(emoji: '📎', name: 'paperclip', keywords: <String>['clip']),
      EmojiEntry(
        emoji: '🗂️',
        name: 'card index dividers',
        keywords: <String>['folder'],
      ),
      EmojiEntry(emoji: '🔒', name: 'locked', keywords: <String>['lock']),
      EmojiEntry(emoji: '🔑', name: 'key', keywords: <String>['key']),
      EmojiEntry(
        emoji: '💡',
        name: 'light bulb',
        keywords: <String>['idea', 'bulb'],
      ),
      EmojiEntry(emoji: '🔦', name: 'flashlight', keywords: <String>['light']),
      EmojiEntry(
        emoji: '🧯',
        name: 'fire extinguisher',
        keywords: <String>['safety', 'fire'],
      ),
      EmojiEntry(emoji: '🧰', name: 'toolbox', keywords: <String>['tools']),
      EmojiEntry(
        emoji: '🛒',
        name: 'shopping cart',
        keywords: <String>['shop'],
      ),
      EmojiEntry(emoji: '🎁', name: 'wrapped gift', keywords: <String>['gift']),
    ],
  ),
  EmojiSection(
    type: EmojiCategoryType.symbols,
    title: 'Symbols',
    entries: <EmojiEntry>[
      EmojiEntry(
        emoji: '✅',
        name: 'check mark button',
        keywords: <String>['done', 'ok'],
      ),
      EmojiEntry(
        emoji: '❌',
        name: 'cross mark',
        keywords: <String>['wrong', 'no'],
      ),
      EmojiEntry(emoji: '⚠️', name: 'warning', keywords: <String>['alert']),
      EmojiEntry(
        emoji: '❗',
        name: 'red exclamation mark',
        keywords: <String>['important'],
      ),
      EmojiEntry(emoji: '❓', name: 'question mark', keywords: <String>['ask']),
      EmojiEntry(emoji: '➕', name: 'plus', keywords: <String>['add']),
      EmojiEntry(emoji: '➖', name: 'minus', keywords: <String>['subtract']),
      EmojiEntry(emoji: '➗', name: 'divide', keywords: <String>['math']),
      EmojiEntry(emoji: '✖️', name: 'multiply', keywords: <String>['math']),
      EmojiEntry(
        emoji: '♻️',
        name: 'recycling symbol',
        keywords: <String>['recycle'],
      ),
      EmojiEntry(emoji: '🆗', name: 'ok button', keywords: <String>['ok']),
      EmojiEntry(emoji: '🆕', name: 'new button', keywords: <String>['new']),
      EmojiEntry(emoji: '🔔', name: 'bell', keywords: <String>['notification']),
      EmojiEntry(
        emoji: '🎵',
        name: 'musical note',
        keywords: <String>['music'],
      ),
      EmojiEntry(emoji: '♾️', name: 'infinity', keywords: <String>['forever']),
      EmojiEntry(
        emoji: '💲',
        name: 'heavy dollar sign',
        keywords: <String>['money'],
      ),
      EmojiEntry(
        emoji: '₹',
        name: 'indian rupee sign',
        keywords: <String>['money'],
      ),
      EmojiEntry(emoji: '©️', name: 'copyright', keywords: <String>['legal']),
      EmojiEntry(emoji: '®️', name: 'registered', keywords: <String>['legal']),
      EmojiEntry(emoji: '™️', name: 'trade mark', keywords: <String>['legal']),
    ],
  ),
  EmojiSection(
    type: EmojiCategoryType.flags,
    title: 'Flags',
    entries: <EmojiEntry>[
      EmojiEntry(emoji: '🏳️', name: 'white flag', keywords: <String>['flag']),
      EmojiEntry(emoji: '🏴', name: 'black flag', keywords: <String>['flag']),
      EmojiEntry(
        emoji: '🚩',
        name: 'triangular flag',
        keywords: <String>['flag'],
      ),
      EmojiEntry(
        emoji: '🏁',
        name: 'chequered flag',
        keywords: <String>['race'],
      ),
      EmojiEntry(
        emoji: '🇮🇳',
        name: 'flag india',
        keywords: <String>['india'],
      ),
      EmojiEntry(
        emoji: '🇺🇸',
        name: 'flag united states',
        keywords: <String>['usa'],
      ),
      EmojiEntry(
        emoji: '🇬🇧',
        name: 'flag united kingdom',
        keywords: <String>['uk'],
      ),
      EmojiEntry(
        emoji: '🇦🇪',
        name: 'flag united arab emirates',
        keywords: <String>['uae'],
      ),
      EmojiEntry(
        emoji: '🇨🇦',
        name: 'flag canada',
        keywords: <String>['canada'],
      ),
      EmojiEntry(
        emoji: '🇦🇺',
        name: 'flag australia',
        keywords: <String>['australia'],
      ),
      EmojiEntry(
        emoji: '🇯🇵',
        name: 'flag japan',
        keywords: <String>['japan'],
      ),
      EmojiEntry(
        emoji: '🇩🇪',
        name: 'flag germany',
        keywords: <String>['germany'],
      ),
      EmojiEntry(
        emoji: '🇫🇷',
        name: 'flag france',
        keywords: <String>['france'],
      ),
      EmojiEntry(
        emoji: '🇸🇬',
        name: 'flag singapore',
        keywords: <String>['singapore'],
      ),
      EmojiEntry(
        emoji: '🇳🇵',
        name: 'flag nepal',
        keywords: <String>['nepal'],
      ),
      EmojiEntry(
        emoji: '🇱🇰',
        name: 'flag sri lanka',
        keywords: <String>['sri lanka'],
      ),
      EmojiEntry(
        emoji: '🇧🇩',
        name: 'flag bangladesh',
        keywords: <String>['bangladesh'],
      ),
      EmojiEntry(
        emoji: '🇧🇹',
        name: 'flag bhutan',
        keywords: <String>['bhutan'],
      ),
      EmojiEntry(
        emoji: '🇲🇾',
        name: 'flag malaysia',
        keywords: <String>['malaysia'],
      ),
      EmojiEntry(
        emoji: '🇿🇦',
        name: 'flag south africa',
        keywords: <String>['south africa'],
      ),
    ],
  ),
];
