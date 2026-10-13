import 'package:flutter/material.dart';
import '../../common/app_branding.dart';
import '../../common/app_theme.dart';
import '../../types/dlna_types.dart';
import '../../services/dlna_client.dart';

/// 投屏设备选择底栏弹窗，对齐 OHOS `PlayerCastSheet.ets`
class PlayerCastSheet extends StatefulWidget {
  final String mediaUrl;
  final String mediaTitle;
  final double startPosition;
  final double startDuration;
  final String connectedUsn;
  final DlnaDevice? seedDevice;
  final ValueChanged<DlnaDevice> onCasted;
  final DlnaClient? client;
  final bool autoStartScan;
  final int debounceMs;

  const PlayerCastSheet({
    super.key,
    required this.mediaUrl,
    this.mediaTitle = AppBranding.defaultCastTitle,
    this.startPosition = 0,
    this.startDuration = 0,
    this.connectedUsn = '',
    this.seedDevice,
    required this.onCasted,
    this.client,
    this.autoStartScan = true,
    this.debounceMs = 300,
  });

  static void show(
    BuildContext context, {
    required String mediaUrl,
    String mediaTitle = AppBranding.defaultCastTitle,
    double startPosition = 0,
    double startDuration = 0,
    String connectedUsn = '',
    DlnaDevice? seedDevice,
    required ValueChanged<DlnaDevice> onCasted,
    DlnaClient? client,
    bool autoStartScan = true,
    int debounceMs = 300,
    VoidCallback? onDismissed,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: AppTheme.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (context) => PlayerCastSheet(
        mediaUrl: mediaUrl,
        mediaTitle: mediaTitle,
        startPosition: startPosition,
        startDuration: startDuration,
        connectedUsn: connectedUsn,
        seedDevice: seedDevice,
        onCasted: onCasted,
        client: client,
        autoStartScan: autoStartScan,
        debounceMs: debounceMs,
      ),
    ).then((_) {
      onDismissed?.call();
    });
  }

  @override
  State<PlayerCastSheet> createState() => _PlayerCastSheetState();
}

class _PlayerCastSheetState extends State<PlayerCastSheet> {
  late final DlnaClient _client;
  List<DlnaDevice> _devices = [];
  DlnaScanState _scanState = DlnaScanState.idle;
  String _errorText = '';
  bool _casting = false;
  bool _dismissed = false;
  int _scanSequence = 0;
  DateTime _lastScanClickTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? DlnaClient();
    if (widget.seedDevice != null && widget.connectedUsn.isNotEmpty) {
      _devices = [widget.seedDevice!];
    }
    if (widget.autoStartScan) {
      _startScan();
    }
  }

  @override
  void dispose() {
    _dismissed = true;
    _client.cancelDiscover();
    super.dispose();
  }

  void _startScan({bool manual = false}) {
    if (manual && widget.debounceMs > 0) {
      final now = DateTime.now();
      if (now.difference(_lastScanClickTime).inMilliseconds < widget.debounceMs) {
        return;
      }
      _lastScanClickTime = now;
    }
    _scanSequence++;
    final currentSeq = _scanSequence;

    _client.cancelDiscover();
    setState(() {
      _scanState = DlnaScanState.scanning;
      _errorText = '';
      _devices = widget.seedDevice != null && widget.connectedUsn.isNotEmpty
          ? [widget.seedDevice!]
          : [];
    });

    _client.discover(onUpdate: (list) {
      if (mounted && currentSeq == _scanSequence) {
        _mergeDevices(list);
      }
    }).then((list) {
      if (mounted && currentSeq == _scanSequence) {
        _mergeDevices(list);
        setState(() => _scanState = DlnaScanState.done);
      }
    }).catchError((e) {
      if (mounted && currentSeq == _scanSequence) {
        setState(() {
          _errorText = '$e';
          _scanState = DlnaScanState.error;
        });
      }
    });
  }

  void _mergeDevices(List<DlnaDevice> list) {
    final map = <String, DlnaDevice>{};
    if (widget.seedDevice != null && widget.connectedUsn.isNotEmpty) {
      map[widget.seedDevice!.usn] = widget.seedDevice!;
    }
    for (final d in list) {
      if (d.controlURL.isNotEmpty) map[d.usn] = d;
    }
    setState(() => _devices = map.values.toList());
  }

  String _statusText() {
    if (_casting) return '正在投屏…';
    if (_scanState == DlnaScanState.scanning) return '正在搜索同一 Wi‑Fi 下的电视/盒子…';
    if (_scanState == DlnaScanState.error) {
      return _errorText.isNotEmpty ? _errorText : '搜索失败，请确认已连接 Wi‑Fi 后重试';
    }
    if (_devices.isEmpty) return '未发现可投屏设备，请确认电视已开启投屏且与手机同一局域网';
    return '发现 ${_devices.length} 台设备，点选即可投屏';
  }

  Future<void> _castTo(DlnaDevice device) async {
    if (widget.mediaUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当前没有可投屏的视频地址')));
      return;
    }
    if (_casting || widget.connectedUsn == device.usn) return;
    setState(() => _casting = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('正在投屏到 ${device.friendlyName}…')));

    try {
      await _client.cast(
        device,
        widget.mediaUrl,
        title: widget.mediaTitle,
        startSec: widget.startPosition,
        durationSec: widget.startDuration,
      );
      if (_dismissed) {
        _client.stop(device).catchError((_) {});
        return;
      }
      if (!mounted) return;
      widget.onCasted(device);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('投屏失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _casting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final landscape = media.size.height > 0 && media.size.height < 500;
    final maxHeight = media.size.height * 0.88;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.spaceLg,
            vertical: landscape ? AppTheme.spaceSm : AppTheme.spaceMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '投屏到电视',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _casting ? null : () => _startScan(manual: true),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(48, 32),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_scanState == DlnaScanState.scanning) ...[
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          _scanState == DlnaScanState.scanning ? '扫描中' : '刷新',
                          style: TextStyle(
                            color: _casting ? AppTheme.textMuted : AppTheme.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Text(
                _statusText(),
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              SizedBox(height: landscape ? 6 : 12),
              if (_scanState == DlnaScanState.scanning && _devices.isEmpty)
                Container(
                  height: landscape ? 70 : 90,
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('扫描中…', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    ],
                  ),
                )
              else if (_devices.isEmpty)
                Container(
                  height: landscape ? 70 : 90,
                  alignment: Alignment.center,
                  child: Text(
                    _scanState == DlnaScanState.error ? '点击右上角刷新重试' : '暂无设备',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _devices.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final isConnected = widget.connectedUsn == device.usn;
                      return Material(
                        color: isConnected ? AppTheme.accentSoft : AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          onTap: () => _castTo(device),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.tv_rounded, color: AppTheme.accent, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        device.friendlyName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        device.manufacturer.isNotEmpty
                                            ? '${device.manufacturer} · ${device.host}'
                                            : device.host,
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (isConnected)
                                  const Text('已连接', style: TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.bold))
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accent,
                                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                                    ),
                                    child: const Text('投屏', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
