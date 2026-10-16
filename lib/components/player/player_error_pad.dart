import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common/app_theme.dart';

/// 播放失败覆盖层，对齐 OHOS `PlayerErrorPad`
class PlayerErrorPad extends StatelessWidget {
  final String errorText;
  final double topInset;
  final double leftInset;
  final double rightInset;
  final double bottomInset;
  final VoidCallback onRetry;
  final VoidCallback? onErrorDetail;
  final VoidCallback? onExternalPlay;

  const PlayerErrorPad({
    super.key,
    required this.errorText,
    this.topInset = 0,
    this.leftInset = 0,
    this.rightInset = 0,
    this.bottomInset = 0,
    required this.onRetry,
    this.onErrorDetail,
    this.onExternalPlay,
  });

  void _showDetailDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        title: const Text('播放异常详情', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: SingleChildScrollView(
          child: SelectableText(
            errorText.isNotEmpty ? errorText : '未知异常',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: errorText));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制报错信息')),
              );
            },
            child: const Text('复制', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了', style: TextStyle(color: AppTheme.textMuted)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xD9000000),
        alignment: Alignment.center,
        padding: EdgeInsets.only(
          left: leftInset > 0 ? leftInset + 16 : 24,
          right: rightInset > 0 ? rightInset + 16 : 24,
          top: topInset > 0 ? topInset + 12 : 20,
          bottom: bottomInset > 0 ? bottomInset + 12 : 20,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('播放异常', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                errorText.isNotEmpty ? errorText : '视频无法播放，请重试或切换其他播放源',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    onPressed: onRetry,
                    child: const Text('重新播放', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                  if (onExternalPlay != null)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      ),
                      onPressed: onExternalPlay,
                      child: const Text('其它播放器', style: TextStyle(fontSize: 13)),
                    ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    onPressed: () => _showDetailDialog(context),
                    child: const Text('查看详情', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
