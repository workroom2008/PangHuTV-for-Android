import 'package:flutter/material.dart';
import '../common/app_theme.dart';
import '../utils/server_config_manager.dart';

/// 历史软件源居中弹层，对齐 OHOS `ServerConfigPage` 历史 Dialog
Future<void> showServerHistoryDialog({
  required BuildContext context,
  required List<String> Function() historyOf,
  required String currentUrl,
  required ValueChanged<String> onSelect,
  required Future<void> Function() onReload,
  required VoidCallback onToastCleared,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xB8000000),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final history = historyOf();
          return Dialog(
            backgroundColor: AppTheme.bgElevated,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              side: const BorderSide(color: AppTheme.border, width: 0.5),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 400,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(
                    ctx,
                    history.isNotEmpty,
                    () => _confirmClear(context, setDialogState, onReload, onToastCleared),
                  ),
                  if (history.isEmpty)
                    const SizedBox(
                      height: 120,
                      child: Center(
                        child: Text('暂无历史记录', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        itemCount: history.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = history[index];
                          return _tile(
                            item,
                            item == currentUrl,
                            () {
                              onSelect(item);
                              Navigator.pop(ctx);
                            },
                            () {
                              ServerConfigManager.instance.removeServerHistory(item).then((_) async {
                                await onReload();
                                setDialogState(() {});
                              });
                            },
                          );
                        },
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Text(
                      '点击任意地址即可直接选择填入',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _header(BuildContext ctx, bool canClear, VoidCallback onClear) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
    child: Row(
      children: [
        const Icon(Icons.history_rounded, size: 16, color: AppTheme.accent),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            '历史服务端',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
        ),
        if (canClear)
          GestureDetector(
            onTap: onClear,
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.dangerSoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: const Row(
                children: [
                  Icon(Icons.delete_outline_rounded, size: 12, color: AppTheme.danger),
                  SizedBox(width: 3),
                  Text('清空', style: TextStyle(fontSize: 12, color: AppTheme.danger)),
                ],
              ),
            ),
          ),
        GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: const SizedBox(
            width: 28,
            height: 28,
            child: Icon(Icons.close_rounded, size: 14, color: AppTheme.textMuted),
          ),
        ),
      ],
    ),
  );
}

Widget _tile(String item, bool isCurrent, VoidCallback onSelect, VoidCallback onDelete) {
  return Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
    decoration: BoxDecoration(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
    ),
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onSelect,
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 15, color: isCurrent ? AppTheme.accent : AppTheme.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isCurrent ? AppTheme.accent : AppTheme.textPrimary,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (isCurrent)
                  Container(
                    margin: const EdgeInsets.only(left: 6, right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentSoft,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: const Text('当前', style: TextStyle(fontSize: 10, color: AppTheme.accent)),
                  ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: onDelete,
          child: const SizedBox(
            width: 32,
            height: 36,
            child: Icon(Icons.delete_outline_rounded, size: 13, color: AppTheme.textMuted),
          ),
        ),
      ],
    ),
  );
}

void _confirmClear(
  BuildContext context,
  StateSetter setDialogState,
  Future<void> Function() onReload,
  VoidCallback onToastCleared,
) {
  showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        title: const Text('清空历史地址', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: const Text(
          '确定要清空全部历史服务端地址吗？',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ServerConfigManager.instance.clearServerHistory().then((_) async {
                await onReload();
                setDialogState(() {});
                onToastCleared();
              });
            },
            child: const Text('清空', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      );
    },
  );
}
