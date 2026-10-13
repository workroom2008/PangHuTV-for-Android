import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../common/app_branding.dart';
import '../common/app_theme.dart';
import '../utils/format_util.dart';
import 'app_icon.dart';

/// 「我的」页站点卡：Logo / 软件源 / 收藏|历史，对齐 OHOS `ProfileTab` 站点卡
class ProfileSiteCard extends StatelessWidget {
  final String siteName;
  final String logoUrl;
  final String sourceHost;
  final VoidCallback onOpenSource;
  final VoidCallback onOpenFavorite;
  final VoidCallback onOpenHistory;

  const ProfileSiteCard({
    super.key,
    required this.siteName,
    required this.logoUrl,
    required this.sourceHost,
    required this.onOpenSource,
    required this.onOpenFavorite,
    required this.onOpenHistory,
  });

  Widget _logo() {
    if (logoUrl.isEmpty) return const StartIconImage();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: CachedNetworkImage(
        imageUrl: logoUrl,
        httpHeaders: FormatUtil.imageHeaders(logoUrl),
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorWidget: (context, url, error) => const StartIconImage(),
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: const Color(0x0FFFFFFF), width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 15, color: AppTheme.accent),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spaceLg),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: const Color(0x14FFFFFF), width: 0.5),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onOpenSource,
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(color: const Color(0x1AFFFFFF), width: 0.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _logo(),
                ),
                const SizedBox(width: AppTheme.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        siteName.isNotEmpty ? siteName : AppBranding.displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                        decoration: BoxDecoration(
                          color: const Color(0x0DFFFFFF),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '服务端',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.accent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                sourceHost,
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0x0AFFFFFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.chevron_right_rounded, size: 14, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: Color(0x14FFFFFF), height: 1),
          ),
          Row(
            children: [
              _chip(icon: Icons.star_rounded, title: '我的收藏', onTap: onOpenFavorite),
              const SizedBox(width: AppTheme.spaceSm),
              _chip(icon: Icons.history_rounded, title: '观看历史', onTap: onOpenHistory),
            ],
          ),
        ],
      ),
    );
  }
}
