/// Create Poll Screen - Premium Redesigned UI matching Insights style
/// Calm teal/green palette, premium rounded corners, smooth animations
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/poll_model.dart';
import '../models/user_model.dart';
import '../services/poll_service.dart';
import '../core/constants/app_colors.dart';
import '../providers/auth_provider.dart' as local_auth;

class CreatePollScreen extends StatefulWidget {
  final String chatId;
  final String chatType;

  const CreatePollScreen({
    super.key,
    required this.chatId,
    required this.chatType,
  });

  @override
  State<CreatePollScreen> createState() => _CreatePollScreenState();
}

class _CreatePollScreenState extends State<CreatePollScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  bool _allowMultiple = false;
  bool _isSending = false;
  String? _errorMessage;

  final int _minOptions = 2;
  final int _maxOptions = 6;

  late AnimationController _animController;

  Color _getAccentColor(UserRole? role) {
    switch (role) {
      case UserRole.teacher:
        return AppColors.teacherColor;
      case UserRole.student:
        return AppColors.studentColor;
      case UserRole.parent:
        return AppColors.parentColor;
      case UserRole.institute:
      default:
        return AppColors.insightsTeal;
    }
  }

  Color _getAccentDark(Color color) {
    return Color.lerp(color, Colors.black, 0.2) ?? color;
  }

  LinearGradient _getAccentGradient(Color base, Color dark) {
    return LinearGradient(
      colors: [base, dark],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    _animController.dispose();
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length < _maxOptions) {
      setState(() {
        _optionControllers.add(TextEditingController());
      });
    }
  }

  void _removeOption(int index) {
    if (_optionControllers.length > _minOptions) {
      setState(() {
        _optionControllers[index].dispose();
        _optionControllers.removeAt(index);
      });
    }
  }

  bool _isValid() {
    final question = _questionController.text.trim();
    if (question.isEmpty) return false;

    int validOptions = 0;
    for (final controller in _optionControllers) {
      if (controller.text.trim().isNotEmpty) {
        validOptions++;
      }
    }

    return validOptions >= _minOptions;
  }

  // BACKEND INTEGRATION POINT: Keep existing sendPoll() logic unchanged
  Future<void> _sendPoll() async {
    if (!_isValid()) {
      setState(() {
        _errorMessage =
            'Please enter a question and at least $_minOptions options';
      });
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<local_auth.AuthProvider>(
        context,
        listen: false,
      );
      final creatorId = authProvider.currentUser?.uid ?? '';
      final creatorName = authProvider.currentUser?.name ?? 'Anonymous';
      final creatorRole =
          authProvider.currentUser?.role.toString() ?? 'unknown';

      final options = <PollOption>[];
      for (int i = 0; i < _optionControllers.length; i++) {
        final text = _optionControllers[i].text.trim();
        if (text.isNotEmpty) {
          options.add(PollOption(id: 'option_$i', text: text));
        }
      }

      final poll = PollModel(
        question: _questionController.text.trim(),
        options: options,
        allowMultiple: _allowMultiple,
        createdBy: creatorId,
        createdByName: creatorName,
        createdByRole: creatorRole,
        createdAt: DateTime.now(),
      );

      final pollService = PollService();
      await pollService.sendPoll(
        chatId: widget.chatId,
        poll: poll,
        chatType: widget.chatType,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Poll sent successfully!'),
            backgroundColor: AppColors.accentSuccess,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSending = false;
        _errorMessage = 'Failed to send poll: ${e.toString()}';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: AppColors.accentDanger,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<local_auth.AuthProvider>(
      context,
      listen: false,
    );
    final currentUserRole = authProvider.currentUser?.role;
    final accentColor = _getAccentColor(currentUserRole);
    final accentDark = _getAccentDark(accentColor);
    final accentGradient = _getAccentGradient(accentColor, accentDark);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.surfaceDark : AppColors.background;
    final cardColor = isDark ? AppColors.surfaceCard : Colors.white;

    return WillPopScope(
      onWillPop: () async {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        }
        return false;
      },
      child: Theme(
        data: Theme.of(context).copyWith(
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: accentColor,
            selectionColor: accentColor.withOpacity(0.25),
            selectionHandleColor: accentColor,
          ),
        ),
        child: Scaffold(
          backgroundColor: bgColor,
          // Premium header with centered title
          appBar: AppBar(
            backgroundColor: isDark ? AppColors.surfaceDark : accentColor,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => Navigator.of(context).maybePop(),
              color: isDark ? AppColors.textOnDark : Colors.white,
            ),
            title: Text(
              'Create Poll',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textOnDark : Colors.white,
              ),
            ),
          ),
          body: Form(
            key: _formKey,
            child: Column(
              children: [
                // Scrollable content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16), // Outer padding 16px
                    children: [
                      // Question input - large rounded field
                      _buildQuestionField(isDark, cardColor, accentColor),
                      const SizedBox(height: 24), // Vertical rhythm 24px
                      // Options header
                      _buildOptionsHeader(accentColor),
                      const SizedBox(height: 12),

                      // Options list
                      ..._buildOptionsList(isDark, cardColor, accentColor),

                      // Add option button
                      if (_optionControllers.length < _maxOptions)
                        _buildAddOptionButton(isDark, accentColor),
                      const SizedBox(height: 24),

                      // Controls (toggles)
                      _buildControls(isDark, cardColor, accentColor),
                      const SizedBox(height: 16),

                      // Validation hint
                      if (_errorMessage != null) _buildErrorMessage(),
                    ],
                  ),
                ),

                // Sticky bottom bar with blur/elevation
                _buildBottomBar(isDark, accentColor, accentGradient),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Question field with icon, counter, premium styling
  Widget _buildQuestionField(bool isDark, Color cardColor, Color accentColor) {
    final charCount = _questionController.text.length;
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16), // Premium radius 16px
        border: Border.all(
          color: isDark ? AppColors.borderSubtle : Colors.grey.shade300,
          width: 1,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: _questionController,
            maxLines: 3,
            maxLength: 200,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: 'Enter poll question (max 200 chars)',
              hintStyle: TextStyle(
                color: isDark ? AppColors.textMuted : Colors.grey.shade500,
                fontSize: 15,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: accentColor, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: isDark ? AppColors.borderSubtle : Colors.grey.shade300,
                  width: 1,
                ),
              ),
              prefixIcon: Icon(
                Icons.poll_outlined,
                color: accentColor,
                size: 22,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              counterText: '', // Hide default counter
            ),
            onChanged: (val) => setState(() {}),
          ),
          // Custom counter
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 12),
            child: Text(
              '$charCount/200',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.textMuted : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsHeader(Color accentColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Options',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.textOnDark
                : AppColors.textPrimary,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${_optionControllers.length}/$_maxOptions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildOptionsList(
    bool isDark,
    Color cardColor,
    Color accentColor,
  ) {
    return _optionControllers.asMap().entries.map((entry) {
      final index = entry.key;
      final controller = entry.value;
      final label = String.fromCharCode(65 + index); // A, B, C, ...

      return Padding(
        padding: const EdgeInsets.only(bottom: 12), // Spacing 12px
        child: _buildOptionRow(
          index: index,
          label: label,
          controller: controller,
          isDark: isDark,
          cardColor: cardColor,
          accentColor: accentColor,
        ),
      );
    }).toList();
  }

  // Option row with circular label, text field, drag handle, remove icon
  Widget _buildOptionRow({
    required int index,
    required String label,
    required TextEditingController controller,
    required bool isDark,
    required Color cardColor,
    required Color accentColor,
  }) {
    final charCount = controller.text.length;
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14), // Radius 14px
        border: Border.all(
          color: isDark ? AppColors.borderSubtle : Colors.grey.shade300,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Row(
        children: [
          // Circular label (A/B/C)
          Container(
            margin: const EdgeInsets.all(12),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
            ),
          ),
          // Text field
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextField(
                  controller: controller,
                  maxLength: 100,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark
                        ? AppColors.textOnDark
                        : AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Option ${index + 1}',
                    hintStyle: TextStyle(
                      color: isDark
                          ? AppColors.textMuted
                          : Colors.grey.shade500,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: accentColor, width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppColors.borderSubtle
                            : Colors.grey.shade300,
                        width: 1,
                      ),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    counterText: '',
                  ),
                  onChanged: (val) => setState(() {}),
                ),
                if (charCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 12, bottom: 8),
                    child: Text(
                      '$charCount/100',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.textMuted : Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Drag handle (UI only)
          Icon(
            Icons.drag_indicator,
            color: isDark ? AppColors.textMuted : Colors.grey.shade400,
            size: 20,
          ),
          const SizedBox(width: 4),
          // Remove button
          if (_optionControllers.length > _minOptions)
            IconButton(
              icon: Icon(
                Icons.close,
                color: isDark ? AppColors.textMuted : Colors.grey.shade500,
                size: 20,
              ),
              onPressed: () => _removeOption(index),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            )
          else
            const SizedBox(width: 8),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildAddOptionButton(bool isDark, Color accentColor) {
    return OutlinedButton.icon(
      onPressed: _addOption,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Add Option'),
      style: OutlinedButton.styleFrom(
        foregroundColor: accentColor,
        side: BorderSide(
          color: isDark ? AppColors.borderMedium : accentColor.withOpacity(0.3),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    );
  }

  Widget _buildControls(bool isDark, Color cardColor, Color accentColor) {
    return Column(
      children: [
        // Allow multiple answers toggle
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? AppColors.borderSubtle : Colors.grey.shade300,
            ),
          ),
          child: SwitchListTile(
            title: Text(
              'Allow multiple answers',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.textOnDark : AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              'Users can select more than one option',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.textMuted : Colors.grey.shade600,
              ),
            ),
            value: _allowMultiple,
            activeThumbColor: accentColor,
            onChanged: (value) {
              setState(() {
                _allowMultiple = value;
              });
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentDanger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accentDanger.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.accentDanger,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.accentDanger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Sticky bottom bar with blur, elevation, buttons
  Widget _buildBottomBar(
    bool isDark,
    Color accentColor,
    LinearGradient accentGradient,
  ) {
    final isValid = _isValid();
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceElevated.withOpacity(0.95)
            : Colors.white.withOpacity(0.95),
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.borderSubtle : Colors.grey.shade200,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Preview button (outline)
            Expanded(
              child: OutlinedButton(
                onPressed: isValid ? () {} : null, // Preview action (UI only)
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentColor,
                  side: BorderSide(
                    color: isValid
                        ? accentColor
                        : (isDark ? AppColors.textMuted : Colors.grey.shade400),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  'Preview',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isValid
                        ? accentColor
                        : (isDark ? AppColors.textMuted : Colors.grey),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Send Poll button (gradient fill)
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTapDown: (_) => _animController.forward(),
                onTapUp: (_) {
                  _animController.reverse();
                  if (!_isSending && isValid) _sendPoll();
                },
                onTapCancel: () => _animController.reverse(),
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1.0 - (_animController.value * 0.05),
                      child: child,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: isValid && !_isSending ? accentGradient : null,
                      color: isValid && !_isSending
                          ? null
                          : (isDark
                                ? AppColors.textMuted
                                : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: isValid && !_isSending
                          ? [
                              BoxShadow(
                                color: accentColor.withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [],
                    ),
                    child: Center(
                      child: _isSending
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Send Poll',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
