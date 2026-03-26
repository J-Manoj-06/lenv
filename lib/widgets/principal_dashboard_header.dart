import 'dart:ui';

import 'package:flutter/material.dart';

class PrincipalDashboardHeader extends StatefulWidget {
  const PrincipalDashboardHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.actionIcon,
    this.onActionTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final IconData? actionIcon;
  final VoidCallback? onActionTap;

  @override
  State<PrincipalDashboardHeader> createState() =>
      _PrincipalDashboardHeaderState();
}

class _PrincipalDashboardHeaderState extends State<PrincipalDashboardHeader> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = const Color(0xFFE5E7EB);
    final subtitleColor = const Color(0xFF9CA3AF);

    final cardGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
          );

    final iconGradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0EA5E9), Color(0xFF146D7A)],
    );

    final cardBorderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);

    final cardShadowColor = isDark
        ? const Color.fromRGBO(2, 6, 23, 0.5)
        : const Color.fromRGBO(15, 23, 42, 0.1);

    final interactiveScale = (_isHovered || _isFocused) ? 1.01 : 1.0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: child,
          ),
        );
      },
      child: FocusableActionDetector(
        onShowFocusHighlight: (focused) {
          if (_isFocused != focused) {
            setState(() {
              _isFocused = focused;
            });
          }
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Column(
            children: [
              AnimatedScale(
                scale: interactiveScale,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: cardGradient,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cardBorderColor, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: cardShadowColor,
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color.fromRGBO(
                                          14,
                                          165,
                                          233,
                                          0.28,
                                        ),
                                        blurRadius: 16,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    gradient: iconGradient,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    widget.icon,
                                    color: Colors.white,
                                    size: 21,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isDark
                                          ? titleColor
                                          : const Color(0xFF0F172A),
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isDark
                                          ? subtitleColor
                                          : const Color(0xFF64748B),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.actionIcon != null &&
                                widget.onActionTap != null)
                              IconButton(
                                onPressed: widget.onActionTap,
                                icon: Icon(
                                  widget.actionIcon,
                                  color: subtitleColor,
                                ),
                                splashRadius: 22,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                height: 1,
                color: isDark
                    ? const Color.fromRGBO(255, 255, 255, 0.08)
                    : const Color.fromRGBO(15, 23, 42, 0.08),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
