import 'package:flutter/material.dart';
import '../models/class_attendance_model.dart';

class ClassAttendanceTile extends StatefulWidget {
  final ClassAttendanceModel classData;
  final Color cardColor;
  final Color textColor;
  final Color subtitleColor;

  const ClassAttendanceTile({
    super.key,
    required this.classData,
    required this.cardColor,
    required this.textColor,
    required this.subtitleColor,
  });

  @override
  State<ClassAttendanceTile> createState() => _ClassAttendanceTileState();
}

class _ClassAttendanceTileState extends State<ClassAttendanceTile>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _controller;
  late Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _iconTurns = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: widget.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.classData.className,
                              style: TextStyle(
                                color: widget.textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.classData.presentCount} / ${widget.classData.totalStudents}',
                              style: TextStyle(
                                color: widget.subtitleColor,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${widget.classData.percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: widget.textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: widget.classData.statusColor.withOpacity(
                                0.2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              widget.classData.attendanceStatus,
                              style: TextStyle(
                                color: widget.classData.statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      RotationTransition(
                        turns: _iconTurns,
                        child: Icon(
                          Icons.expand_more,
                          color: widget.subtitleColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: widget.classData.percentage / 100,
                      backgroundColor: widget.subtitleColor.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.classData.statusColor,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildStudentList(),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentList() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          ...widget.classData.students.map((student) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.subtitleColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: student.isPresent
                          ? const Color(0xFF34D399).withOpacity(0.2)
                          : const Color(0xFFFB7185).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      student.isPresent ? Icons.check : Icons.close,
                      size: 16,
                      color: student.isPresent
                          ? const Color(0xFF34D399)
                          : const Color(0xFFFB7185),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.name,
                          style: TextStyle(
                            color: widget.textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (student.absentReason != null)
                          Text(
                            student.absentReason!,
                            style: TextStyle(
                              color: widget.subtitleColor,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    'Roll ${student.rollNo}',
                    style: TextStyle(color: widget.subtitleColor, fontSize: 12),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
