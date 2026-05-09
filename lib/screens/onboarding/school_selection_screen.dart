import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:video_player/video_player.dart';
import '../../models/school_model.dart';
import '../../services/school_service.dart';
import '../../services/school_storage_service.dart';

/// School selection screen - users select their school here
class SchoolSelectionScreen extends StatefulWidget {
  const SchoolSelectionScreen({super.key});

  @override
  State<SchoolSelectionScreen> createState() => _SchoolSelectionScreenState();
}

class _SchoolSelectionScreenState extends State<SchoolSelectionScreen>
    with TickerProviderStateMixin {
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;
  late AnimationController _backgroundController;
  late VideoPlayerController _videoController;
  bool _isLoading = false;
  final SchoolService _schoolService = SchoolService();
  List<SchoolModel> _schools = [];
  bool _isLoadingSchools = true;
  String? _schoolLoadError;
  bool _schoolLoadIsWarning = false;
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _isSearchFocused = _searchFocusNode.hasFocus;
      });
    });
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
    _videoController = VideoPlayerController.asset('assets/enter_video.mp4')
      ..setLooping(true)
      ..setVolume(0);
    _videoController
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _videoController.play();
        })
        .catchError((_) {
          if (mounted) {
            setState(() {});
          }
        });
    _loadSchools();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _backgroundController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  List<SchoolModel> get _filteredSchools {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _schools;
    }

    return _schools.where((school) {
      return school.name.toLowerCase().contains(query) ||
          school.id.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _loadSchools() async {
    setState(() {
      _isLoadingSchools = true;
      _schoolLoadError = null;
      _schoolLoadIsWarning = false;
    });

    try {
      final schools = await _schoolService.fetchSchools();
      if (!mounted) return;

      setState(() {
        _schools = schools;
        _isLoadingSchools = false;

        if (_schoolService.lastFetchUsedCache && schools.isNotEmpty) {
          _schoolLoadError = 'Offline mode: showing previously loaded schools.';
          _schoolLoadIsWarning = true;
        }
      });

      if (schools.isEmpty) {
        setState(() {
          _schoolLoadError = 'No schools found. Please contact admin.';
          _schoolLoadIsWarning = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      final bool isNetworkIssue = e is SchoolFetchException && e.isNetworkIssue;
      setState(() {
        _isLoadingSchools = false;
        _schoolLoadError = e is SchoolFetchException
            ? e.message
            : 'Failed to load schools.';
        _schoolLoadIsWarning = isNetworkIssue;
      });
    }
  }

  /// Select a school from the list
  Future<void> _selectSchool(SchoolModel school) async {
    setState(() => _isLoading = true);

    try {
      await schoolStorageService.initialize();
      await schoolStorageService.saveSchoolData(
        schoolId: school.id,
        schoolName: school.name,
        schoolLogo: '',
      );

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/role-selection');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildAnimatedBackground(),
          SafeArea(
            child: _isLoadingSchools
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFA726)),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 18),
                        _buildSearchBar(),
                        const SizedBox(height: 16),
                        if (_schoolLoadError != null) _buildErrorBanner(),
                        if (_schoolLoadError != null)
                          const SizedBox(height: 14),
                        if (_filteredSchools.isEmpty)
                          _buildEmptyState()
                        else
                          ...List.generate(
                            _filteredSchools.length,
                            (index) => _AnimatedSchoolCard(
                              school: _filteredSchools[index],
                              index: index,
                              onTap: () =>
                                  _selectSchool(_filteredSchools[index]),
                            ),
                          ),
                        const SizedBox(height: 12),
                        _buildSupportCard(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFFFFA726)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _backgroundController,
      builder: (context, _) {
        final t = _backgroundController.value;
        final shiftX = math.sin(t * math.pi * 2) * 0.2;
        final shiftY = math.cos(t * math.pi * 2) * 0.2;

        return Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoBackground(),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-0.8 + shiftX, -1 + shiftY),
                  end: Alignment(0.9 - shiftX, 1 - shiftY),
                  colors: [
                    const Color(0xFF0F0F0F).withValues(alpha: 0.50),
                    const Color(0xFF14100A).withValues(alpha: 0.42),
                    const Color(0xFF1A1205).withValues(alpha: 0.34),
                  ],
                ),
              ),
            ),
            Container(color: Colors.black.withValues(alpha: 0.24)),
            CustomPaint(
              painter: _ParticlePainter(progress: t),
              child: const SizedBox.expand(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVideoBackground() {
    final controller = _videoController;

    if (!controller.value.isInitialized) {
      return Container(color: const Color(0xFF0F0F0F));
    }

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: Opacity(opacity: 0.92, child: VideoPlayer(controller)),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMascot(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Select Your ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) {
                          return const LinearGradient(
                            colors: [Color(0xFFFFC05A), Color(0xFFFFA726)],
                          ).createShader(bounds);
                        },
                        child: const Text(
                          'School',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Let\'s find your school and get started',
                    style: TextStyle(
                      color: Color(0xFFB0B0B0),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMascot() {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x33FFA726), Color(0x11FFA726)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFA726).withValues(alpha: 0.34),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Icon(Icons.person, size: 34, color: Colors.white),
          Positioned(
            right: 8,
            bottom: 8,
            child: Icon(
              Icons.menu_book_rounded,
              size: 14,
              color: Color(0xFFFFA726),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return AnimatedScale(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      scale: _isSearchFocused ? 1.01 : 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF1B1B1B), Color(0xFF141414)],
          ),
          border: Border.all(
            color: _isSearchFocused
                ? const Color(0xAAFFA726)
                : const Color(0x33FFFFFF),
            width: _isSearchFocused ? 1.4 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: (_isSearchFocused ? const Color(0xFFFFA726) : Colors.black)
                  .withValues(alpha: _isSearchFocused ? 0.30 : 0.26),
              blurRadius: _isSearchFocused ? 18 : 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
          decoration: const InputDecoration(
            hintText: 'Search your school...',
            hintStyle: TextStyle(color: Color(0xFFB0B0B0)),
            prefixIcon: Icon(Icons.search_rounded, color: Color(0xFFD0D0D0)),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    final accent = _schoolLoadIsWarning
        ? const Color(0xFFFFA726)
        : const Color(0xFFFF6B6B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: accent.withValues(alpha: 0.08),
        border: Border.all(color: accent.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          Icon(
            _schoolLoadIsWarning ? Icons.wifi_off_rounded : Icons.error_outline,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _schoolLoadError!,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (!_schoolLoadIsWarning)
            TextButton(
              onPressed: _loadSchools,
              child: const Text(
                'Retry',
                style: TextStyle(color: Color(0xFFFFA726)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isTrulyEmpty = _schools.isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF121212)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFA726)),
      ),
      child: Column(
        children: [
          const Icon(Icons.school_outlined, color: Color(0xFFFFA726), size: 36),
          const SizedBox(height: 8),
          Text(
            isTrulyEmpty
                ? 'No schools available'
                : 'No schools match your search',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: isTrulyEmpty
                ? _loadSchools
                : () {
                    _searchController.clear();
                    setState(() {});
                  },
            child: Text(
              isTrulyEmpty ? 'Refresh' : 'Clear Search',
              style: const TextStyle(color: Color(0xFFFFA726)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF161616), Color(0xFF101010)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x2EFFA726)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFA726).withValues(alpha: 0.12),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.support_agent_rounded, color: Color(0xFFFFA726), size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Can\'t find your school?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Contact your school administrator for help',
                  style: TextStyle(
                    color: Color(0xFFB0B0B0),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedSchoolCard extends StatefulWidget {
  final SchoolModel school;
  final int index;
  final VoidCallback onTap;

  const _AnimatedSchoolCard({
    required this.school,
    required this.index,
    required this.onTap,
  });

  @override
  State<_AnimatedSchoolCard> createState() => _AnimatedSchoolCardState();
}

class _AnimatedSchoolCardState extends State<_AnimatedSchoolCard> {
  bool _visible = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.index * 100), () {
      if (!mounted) return;
      setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasAddress = (widget.school.address ?? '').trim().isNotEmpty;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      opacity: _visible ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        offset: _visible ? Offset.zero : const Offset(0, 0.08),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            scale: _pressed ? 1.02 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A1A1A), Color(0xFF111111)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _pressed
                      ? const Color(0x80FFA726)
                      : const Color(0x30FFFFFF),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: const Color(
                      0xFFFFA726,
                    ).withValues(alpha: _pressed ? 0.24 : 0.12),
                    blurRadius: _pressed ? 20 : 14,
                    spreadRadius: _pressed ? 1.4 : 0.4,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFFFFA726).withValues(alpha: 0.14),
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: Color(0xFFFFA726),
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.school.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'School ID: ${widget.school.id}',
                          style: const TextStyle(
                            color: Color(0xFFB0B0B0),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (hasAddress) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.school.address!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF969696),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedSlide(
                    duration: const Duration(milliseconds: 150),
                    offset: _pressed ? const Offset(0.16, 0) : Offset.zero,
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFFFA726),
                      size: 30,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final double progress;

  _ParticlePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const points = [
      Offset(0.15, 0.2),
      Offset(0.75, 0.15),
      Offset(0.32, 0.48),
      Offset(0.86, 0.52),
      Offset(0.24, 0.75),
      Offset(0.67, 0.84),
    ];

    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final drift = math.sin((progress * math.pi * 2) + i) * 6;
      final dx = (p.dx * size.width) + drift;
      final dy = (p.dy * size.height) + drift * 0.35;
      paint.color = const Color(
        0xFFFFA726,
      ).withValues(alpha: 0.10 + (i * 0.01));
      canvas.drawCircle(Offset(dx, dy), 2.0 + (i % 3), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
