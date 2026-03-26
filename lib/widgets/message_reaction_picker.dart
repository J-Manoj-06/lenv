import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> kQuickReactionEmojis = <String>[
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🙏',
  '✋',
];

OverlayEntry? _activeReactionOverlayEntry;
void Function([String? emoji])? _dismissActiveReactionPicker;

bool get isMessageReactionPickerOpen =>
    _activeReactionOverlayEntry != null && _dismissActiveReactionPicker != null;

void dismissMessageReactionPicker([String? emoji]) {
  _dismissActiveReactionPicker?.call(emoji);
}

Future<String?> showMessageReactionPicker({
  required BuildContext context,
  required Offset globalPosition,
  List<String> quickEmojis = kQuickReactionEmojis,
  String? selectedEmoji,
}) async {
  // Ensure only one picker is visible at a time.
  dismissMessageReactionPicker();

  final overlay = Overlay.of(context);

  final completer = Completer<String?>();
  late OverlayEntry entry;
  var removed = false;

  void close([String? emoji]) {
    if (!removed) {
      entry.remove();
      removed = true;
    }

    if (identical(_activeReactionOverlayEntry, entry)) {
      _activeReactionOverlayEntry = null;
      _dismissActiveReactionPicker = null;
    }

    if (!completer.isCompleted) {
      completer.complete(emoji);
    }
  }

  final mediaSize = MediaQuery.of(context).size;
  final mediaPadding = MediaQuery.of(context).padding;
  const barHeight = 48.0;
  // Keep extra safety margin so the trailing "+" button never clips at edges.
  final approximateWidth = quickEmojis.length * 42.0 + 60.0;
  final minLeft = 12.0 + mediaPadding.left;
  final maxLeft =
      (mediaSize.width - approximateWidth - 12.0 - mediaPadding.right).clamp(
        minLeft,
        mediaSize.width,
      );
  final left = (globalPosition.dx - (approximateWidth / 2)).clamp(
    minLeft,
    maxLeft,
  );
  final showAbove = globalPosition.dy > 120;
  final top = showAbove
      ? (globalPosition.dy - barHeight - 14).clamp(8.0, mediaSize.height - 64)
      : (globalPosition.dy + 14).clamp(8.0, mediaSize.height - 64);

  entry = OverlayEntry(
    builder: (context) {
      return Material(
        color: Colors.black26,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => close(),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: AnimatedScale(
                scale: 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: _QuickReactionBar(
                    quickEmojis: quickEmojis,
                    selectedEmoji: selectedEmoji,
                    onEmojiTap: (emoji) => close(emoji),
                    onMoreTap: () async {
                      if (!removed) {
                        entry.remove();
                        removed = true;
                      }
                      if (identical(_activeReactionOverlayEntry, entry)) {
                        _activeReactionOverlayEntry = null;
                        _dismissActiveReactionPicker = null;
                      }
                      final picked = await showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (sheetContext) {
                          return _ExpandedReactionPanel(
                            selectedEmoji: selectedEmoji,
                          );
                        },
                      );
                      close(picked);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  _activeReactionOverlayEntry = entry;
  _dismissActiveReactionPicker = close;
  overlay.insert(entry);
  return completer.future;
}

class _QuickReactionBar extends StatelessWidget {
  final List<String> quickEmojis;
  final String? selectedEmoji;
  final ValueChanged<String> onEmojiTap;
  final VoidCallback onMoreTap;

  const _QuickReactionBar({
    required this.quickEmojis,
    required this.selectedEmoji,
    required this.onEmojiTap,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF202123)
            : Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...quickEmojis.map((emoji) {
            final isSelected = selectedEmoji == emoji;
            return InkWell(
              onTap: () => onEmojiTap(emoji),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
            );
          }),
          const SizedBox(width: 4),
          InkWell(
            onTap: onMoreTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedReactionPanel extends StatelessWidget {
  final String? selectedEmoji;

  const _ExpandedReactionPanel({required this.selectedEmoji});

  @override
  Widget build(BuildContext context) {
    return _ExpandedReactionPanelContent(selectedEmoji: selectedEmoji);
  }
}

class _ExpandedReactionPanelContent extends StatefulWidget {
  final String? selectedEmoji;

  const _ExpandedReactionPanelContent({required this.selectedEmoji});

  @override
  State<_ExpandedReactionPanelContent> createState() =>
      _ExpandedReactionPanelContentState();
}

class _ExpandedReactionPanelContentState
    extends State<_ExpandedReactionPanelContent> {
  static const String _recentStorageKey = 'reaction_recent_emojis_v1';
  static const int _recentLimit = 24;

  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _sectionKeys;
  int _activeCategoryIndex = 0;
  List<String> _recentEmojis = <String>[];

  late final List<_ReactionCategory> _categories = <_ReactionCategory>[
    _ReactionCategory(
      title: 'Recent',
      icon: Icons.access_time_rounded,
      emojis: const <String>[],
    ),
    _ReactionCategory(
      title: 'Smileys & Emotion',
      icon: Icons.sentiment_satisfied_alt_rounded,
      emojis: const <String>[
        '😀',
        '😃',
        '😄',
        '😁',
        '😆',
        '😅',
        '😂',
        '🤣',
        '😊',
        '🙂',
        '😉',
        '😍',
        '🥰',
        '😘',
        '😗',
        '😋',
        '😛',
        '😜',
        '🤪',
        '🤗',
        '🤔',
        '🫡',
        '😐',
        '😶',
        '🙄',
        '😏',
        '😔',
        '😢',
        '😭',
        '😤',
      ],
    ),
    _ReactionCategory(
      title: 'People & Body',
      icon: Icons.person_rounded,
      emojis: const <String>[
        '👍',
        '👎',
        '👌',
        '✌️',
        '🤞',
        '🤟',
        '🤘',
        '🤙',
        '👋',
        '🤚',
        '🖐️',
        '✋',
        '🫶',
        '🙏',
        '💪',
        '🫵',
        '👏',
        '🙌',
        '🤝',
        '🫂',
        '👨',
        '👩',
        '🧑',
        '👶',
        '🧒',
        '👦',
        '👧',
        '🧔',
        '👮',
        '🧑‍🏫',
      ],
    ),
    _ReactionCategory(
      title: 'Animals & Nature',
      icon: Icons.pets_rounded,
      emojis: const <String>[
        '🐶',
        '🐱',
        '🐭',
        '🐹',
        '🐰',
        '🦊',
        '🐻',
        '🐼',
        '🐨',
        '🐯',
        '🦁',
        '🐮',
        '🐷',
        '🐸',
        '🐵',
        '🐔',
        '🐧',
        '🐦',
        '🦄',
        '🐝',
        '🌱',
        '🌲',
        '🌳',
        '🌴',
        '🍀',
        '🌸',
        '🌼',
        '🌻',
        '🌞',
        '🌈',
      ],
    ),
    _ReactionCategory(
      title: 'Food & Drink',
      icon: Icons.restaurant_rounded,
      emojis: const <String>[
        '🍎',
        '🍌',
        '🍉',
        '🍇',
        '🍓',
        '🥭',
        '🍍',
        '🥥',
        '🥑',
        '🍅',
        '🥕',
        '🌽',
        '🍕',
        '🍔',
        '🍟',
        '🌮',
        '🌯',
        '🥪',
        '🍜',
        '🍚',
        '🍦',
        '🍩',
        '🍪',
        '🎂',
        '🍫',
        '☕',
        '🍵',
        '🥤',
        '🧃',
        '🍹',
      ],
    ),
    _ReactionCategory(
      title: 'Activities',
      icon: Icons.sports_soccer_rounded,
      emojis: const <String>[
        '⚽',
        '🏀',
        '🏈',
        '⚾',
        '🎾',
        '🏐',
        '🏉',
        '🎱',
        '🏓',
        '🏸',
        '🥊',
        '🥋',
        '⛳',
        '🏹',
        '🎣',
        '🤿',
        '🎯',
        '🎮',
        '🎲',
        '🧩',
        '♟️',
        '🎭',
        '🎨',
        '🎬',
        '🎤',
        '🎧',
        '🎼',
        '🎹',
        '🥁',
        '🎷',
      ],
    ),
    _ReactionCategory(
      title: 'Travel & Places',
      icon: Icons.directions_car_filled_rounded,
      emojis: const <String>[
        '🚗',
        '🚕',
        '🚌',
        '🚎',
        '🏎️',
        '🚓',
        '🚑',
        '🚒',
        '🚚',
        '🚜',
        '✈️',
        '🛫',
        '🛬',
        '🚆',
        '🚂',
        '🚊',
        '🚲',
        '🛵',
        '🚢',
        '⛵',
        '🏠',
        '🏫',
        '🏥',
        '🏢',
        '🏛️',
        '🕌',
        '🗽',
        '🗼',
        '🌋',
        '🏖️',
      ],
    ),
    _ReactionCategory(
      title: 'Objects',
      icon: Icons.lightbulb_outline_rounded,
      emojis: const <String>[
        '📱',
        '💻',
        '⌚',
        '📷',
        '🎥',
        '💡',
        '📚',
        '✏️',
        '🖊️',
        '📌',
        '📎',
        '🗂️',
        '📦',
        '🎁',
        '🧸',
        '🪄',
        '🔒',
        '🔑',
        '🧯',
        '🧲',
        '🧪',
        '💊',
        '💉',
        '🧬',
        '🪙',
        '💎',
        '🛎️',
        '🪞',
        '🪑',
        '🧴',
      ],
    ),
    _ReactionCategory(
      title: 'Symbols',
      icon: Icons.music_note_rounded,
      emojis: const <String>[
        '❤️',
        '🧡',
        '💛',
        '💚',
        '💙',
        '💜',
        '🖤',
        '🤍',
        '🤎',
        '💔',
        '❣️',
        '💕',
        '💞',
        '💯',
        '✅',
        '✔️',
        '❌',
        '⭕',
        '⚠️',
        '🚫',
        '⭐',
        '🌟',
        '✨',
        '🔥',
        '💥',
        '💫',
        '🎵',
        '🎶',
        '➕',
        '➖',
      ],
    ),
    _ReactionCategory(
      title: 'Flags',
      icon: Icons.flag_rounded,
      emojis: const <String>[
        '🏳️',
        '🏴',
        '🏁',
        '🚩',
        '🇮🇳',
        '🇺🇸',
        '🇬🇧',
        '🇦🇪',
        '🇨🇦',
        '🇦🇺',
        '🇳🇿',
        '🇸🇬',
        '🇯🇵',
        '🇰🇷',
        '🇩🇪',
        '🇫🇷',
        '🇮🇹',
        '🇪🇸',
        '🇧🇷',
        '🇿🇦',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _sectionKeys = List<GlobalKey>.generate(
      _categories.length,
      (_) => GlobalKey(),
    );
    _loadRecents();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_recentStorageKey) ?? <String>[];
    if (!mounted) return;
    setState(() {
      _recentEmojis = saved.where((e) => e.trim().isNotEmpty).toList();
    });
  }

  Future<void> _saveRecent(String emoji) async {
    final updated = <String>[emoji, ..._recentEmojis.where((e) => e != emoji)];
    if (updated.length > _recentLimit) {
      updated.removeRange(_recentLimit, updated.length);
    }

    setState(() {
      _recentEmojis = updated;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentStorageKey, updated);
  }

  Future<void> _selectEmoji(String emoji) async {
    await _saveRecent(emoji);
    if (!mounted) return;
    Navigator.of(context).pop(emoji);
  }

  Future<void> _jumpToCategory(int index) async {
    final targetContext = _sectionKeys[index].currentContext;
    if (targetContext == null) return;

    setState(() {
      _activeCategoryIndex = index;
    });

    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  void _handleScroll() {
    final panelRenderObject = context.findRenderObject();
    if (panelRenderObject is! RenderBox) return;
    final panelTop = panelRenderObject.localToGlobal(Offset.zero).dy;

    int nextIndex = _activeCategoryIndex;
    double bestTop = -1e9;

    for (int i = 0; i < _sectionKeys.length; i++) {
      final sectionContext = _sectionKeys[i].currentContext;
      if (sectionContext == null) continue;
      final ro = sectionContext.findRenderObject();
      if (ro is! RenderBox) continue;

      final top = ro.localToGlobal(Offset.zero).dy - panelTop;
      if (top <= 120 && top > bestTop) {
        bestTop = top;
        nextIndex = i;
      }
    }

    if (nextIndex != _activeCategoryIndex && mounted) {
      setState(() {
        _activeCategoryIndex = nextIndex;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panelColor = theme.brightness == Brightness.dark
        ? const Color(0xFF151618)
        : Colors.white;
    final sections = <_ReactionCategory>[
      _ReactionCategory(
        title: 'Recent',
        icon: Icons.access_time_rounded,
        emojis: _recentEmojis,
      ),
      ..._categories.skip(1),
    ];

    return Container(
      height: MediaQuery.of(context).size.height * 0.56,
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outline.withOpacity(0.35),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
                for (int i = 0; i < sections.length; i++) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      key: _sectionKeys[i],
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Text(
                        sections[i].title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withOpacity(0.62),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                            childAspectRatio: 1.0,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final emoji = sections[i].emojis[index];
                        final isSelected = widget.selectedEmoji == emoji;
                        return InkResponse(
                          onTap: () => _selectEmoji(emoji),
                          radius: 20,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? theme.colorScheme.primary.withOpacity(0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Center(
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 26),
                              ),
                            ),
                          ),
                        );
                      }, childCount: sections[i].emojis.length),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(0.92),
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.15),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (int i = 0; i < sections.length; i++)
                    IconButton(
                      splashRadius: 18,
                      iconSize: 20,
                      color: i == _activeCategoryIndex
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withOpacity(0.48),
                      onPressed: () => _jumpToCategory(i),
                      icon: Icon(sections[i].icon),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionCategory {
  final String title;
  final IconData icon;
  final List<String> emojis;

  const _ReactionCategory({
    required this.title,
    required this.icon,
    required this.emojis,
  });
}
