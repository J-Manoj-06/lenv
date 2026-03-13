import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/profile_dp_provider.dart';

class StaffRoomAvatarWidget extends StatelessWidget {
  final String roomId;
  final String roomName;
  final double size;
  final bool canEdit;
  final VoidCallback? onTap;

  const StaffRoomAvatarWidget({
    super.key,
    required this.roomId,
    required this.roomName,
    this.size = 48,
    this.canEdit = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileDPProvider>(
      builder: (ctx, dpProvider, _) {
        final validRoomId = roomId.trim();
        if (validRoomId.isNotEmpty) {
          dpProvider.watchStaffRoomDP(validRoomId);
        }
        final imageUrl = validRoomId.isNotEmpty
            ? dpProvider.getStaffRoomDP(validRoomId)
            : null;
        final hasImage = imageUrl != null && imageUrl.isNotEmpty;

        return GestureDetector(
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF355872).withOpacity(0.18),
                  border: Border.all(
                    color: const Color(0xFF355872).withOpacity(0.35),
                    width: 1.5,
                  ),
                ),
                child: ClipOval(
                  child: hasImage
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          cacheKey: dpProvider.getStaffRoomCacheKey(
                            validRoomId,
                          ),
                          fit: BoxFit.cover,
                          width: size,
                          height: size,
                          fadeInDuration: const Duration(milliseconds: 250),
                          fadeInCurve: Curves.easeIn,
                          placeholder: (_, __) => _buildFallback(),
                          errorWidget: (_, __, ___) => _buildFallback(),
                        )
                      : _buildFallback(),
                ),
              ),
              if (canEdit)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: size * 0.34,
                    height: size * 0.34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFC2185B),
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      size: size * 0.18,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFallback() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: const Color(0xFF355872).withOpacity(0.16),
      child: Icon(
        Icons.business,
        size: size * 0.5,
        color: const Color(0xFF355872),
      ),
    );
  }
}
