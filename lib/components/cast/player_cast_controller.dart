import 'package:flutter/material.dart';
import '../../common/app_branding.dart';
import '../../types/dlna_types.dart';
import '../../services/cast_session.dart';
import 'player_cast_sheet.dart';

abstract class PlayerCastHost {
  double get currentPosition;
  double get totalDuration;
  bool get isPlaying;
  bool get isOpening;
  bool get isBuffering;
  String get videoUrl;
  String get title;
  bool get hasNext;
  double get volume;
  bool get isFull;

  void parkLocal();
  void pauseLocal();
  void resumeLocal(double targetSec, bool wasPlaying);
  void remountCompleted(double positionSec, double durationSec);
  void exitFullForCast();
  void onCastEnded();
  void syncUi();
  void syncProgress(double currentSec, double durationSec);
  void showToast(String message);
  void setPipAutoStart(bool enable);
  void stopPip();
}

/// 投屏协调器，协调本地播放器与 CastSession
/// 对齐 OHOS `PlayerCastController.ets`
class PlayerCastController {
  final CastSession session = CastSession();
  DlnaDevice? device;
  String deviceName = '';
  String connectedUsn = '';
  double startSec = 0;
  bool wasPlaying = false;
  bool pausedForPicker = false;
  bool keepCastForNext = false;
  bool endingCast = false;

  PlayerCastHost? _host;
  bool _absorbingSource = false;
  int _lastCastVolPct = -1;
  bool _castVolBusy = false;
  bool _relTimeToasted = false;

  void attachHost(PlayerCastHost host) {
    _host = host;
    session.onState = () => _onCastState();
    session.onCompleted = () => _handleCastCompleted();
    session.onFailed = (pos) => _handleCastFailed(pos);
    session.onDisconnected = (pos) => _handleCastDisconnected(pos);
  }

  bool get isCasting => connectedUsn.isNotEmpty || deviceName.isNotEmpty || session.active;

  void openCastDialog(BuildContext context, {bool autoStartScan = true}) {
    final host = _host;
    if (host == null || host.videoUrl.trim().isEmpty) return;
    // 只走 openCastSheet：它会快照 wasPlaying 并 pause。这里先 pause 会把
    // isPlaying 打成 false，sheet 再快照会把 wasPlaying 覆盖错。
    openCastSheet(
      context,
      mediaUrl: host.videoUrl,
      mediaTitle: host.title,
      currentPosition: host.currentPosition,
      totalDuration: host.totalDuration,
      autoStartScan: autoStartScan,
    );
  }

  void resumeAfterPickerCancel() {
    final host = _host;
    if (host == null || !pausedForPicker || isCasting) {
      pausedForPicker = false;
      return;
    }
    pausedForPicker = false;
    host.resumeLocal(startSec, true);
    host.syncUi();
  }

  void bindCastDevice(DlnaDevice dev) {
    final host = _host;
    if (host == null) return;
    pausedForPicker = false;
    host.setPipAutoStart(false);
    host.stopPip();
    device = dev;
    deviceName = dev.friendlyName;
    connectedUsn = dev.usn;
    _relTimeToasted = false;

    session.attach(dev);
    final start = startSec > 0 ? startSec : host.currentPosition;
    session.beginLaunch(start, host.totalDuration);
    _lastCastVolPct = -1;
    pushCastVolume();
    host.exitFullForCast();
    // 对齐 OHOS parkPlayerForCast()：释放并销毁本地底层播放器，移交解码给电视
    host.parkLocal();
    host.syncUi();
  }

  /// 投屏中切集/换源处理，对标 OHOS handleSourceChange()
  /// @returns true if source change is consumed (recast / absorb); skip remount.
  bool handleSourceChange() {
    if (isCasting) {
      keepCastForNext = false;
      _absorbingSource = true;
      recastCurrentUrl();
      Future.delayed(Duration.zero, () {
        _absorbingSource = false;
      });
      return true;
    }
    if (_absorbingSource) {
      return true;
    }
    return false;
  }

  void recastCurrentUrl() {
    final host = _host;
    final dev = session.device ?? device;
    if (host == null || dev == null) {
      _failRecast();
      return;
    }
    session
        .replaceUri(
          host.videoUrl,
          host.title.isNotEmpty ? host.title : AppBranding.defaultCastTitle,
          0,
        )
        .then((_) {
      // recast ok
    }).catchError((_) {
      _failRecast();
    });
  }

  void recastUrl(String newUrl, String title) {
    if (!isCasting) return;
    session.replaceUri(newUrl, title, 0).catchError((_) {
      _failRecast();
    });
  }

  void _failRecast() {
    session.clearLocal();
    _clearCastLocal();
    _host?.showToast('续投失败，已在手机播放');
    _host?.resumeLocal(0, true);
    _host?.syncUi();
  }

  void endCastByUser() {
    if (endingCast || !isCasting) return;
    endingCast = true;
    final pos = session.positionSec > 0 ? session.positionSec : (_host?.currentPosition ?? 0);
    final play = wasPlaying;
    session.stopRemote().then((_) {
      _clearCastLocal();
      _host?.resumeLocal(pos, play);
      _host?.showToast('已停止投屏');
      endingCast = false;
    });
  }

  void stopSession() {
    session.stopRemote();
    _clearCastLocal();
  }

  void _clearCastLocal() {
    device = null;
    deviceName = '';
    connectedUsn = '';
    _lastCastVolPct = -1;
    _castVolBusy = false;
    _relTimeToasted = false;
    keepCastForNext = false;
    if (session.active) {
      session.clearLocal();
    }
    _host?.syncUi();
  }

  void _handleCastCompleted() {
    final host = _host;
    if (host == null) return;
    if (host.hasNext) {
      keepCastForNext = true;
      host.onCastEnded();
      return;
    }
    _finishCastCompleted();
  }

  void _finishCastCompleted() {
    final host = _host;
    final pos = session.positionSec;
    final dur = session.durationSec;
    session.clearLocal();
    _clearCastLocal();
    if (host == null) return;
    host.remountCompleted(pos > 0 ? pos : dur, dur);
  }

  void _handleCastFailed(double pos) {
    if (endingCast) return;
    endingCast = true;
    final resumeAt = pos > 0 ? pos : (startSec > 0 ? startSec : (_host?.currentPosition ?? 0));
    final play = wasPlaying;
    _clearCastLocal();
    _host?.resumeLocal(resumeAt, play);
    _host?.showToast('投屏失败，已回到手机');
    endingCast = false;
  }

  void _handleCastDisconnected(double pos) {
    if (endingCast) return;
    endingCast = true;
    final resumeAt = pos > 0 ? pos : (_host?.currentPosition ?? 0);
    final play = wasPlaying;
    _clearCastLocal();
    _host?.resumeLocal(resumeAt, play);
    _host?.showToast('电视已停止投屏');
    endingCast = false;
  }

  void _onCastState() {
    final host = _host;
    if (host == null) return;
    host.syncProgress(session.positionSec, session.durationSec);
    host.syncUi();
    if (session.needRelTimeToast && !_relTimeToasted) {
      session.needRelTimeToast = false;
      _relTimeToasted = true;
      host.showToast('设备不支持进度同步');
    }
  }

  void pushCastVolume([double? volumeOverride]) {
    if (!isCasting) return;
    final dev = session.device ?? device;
    if (dev == null || dev.renderingControlURL.isEmpty) return;
    final v = volumeOverride ?? _host?.volume ?? 0.8;
    final pct = (v * 100).round().clamp(0, 100);
    if (pct == _lastCastVolPct || _castVolBusy) return;
    _lastCastVolPct = pct;
    _castVolBusy = true;
    session.setVolume(pct).then((_) {
      _castVolBusy = false;
      final latestV = _host?.volume ?? 0.8;
      final latestPct = (latestV * 100).round().clamp(0, 100);
      if (latestPct != _lastCastVolPct) {
        pushCastVolume();
      }
    }).catchError((_) {
      _castVolBusy = false;
    });
  }

  void openCastSheet(
    BuildContext context, {
    String? mediaUrl,
    String? mediaTitle,
    double? currentPosition,
    double? totalDuration,
    bool autoStartScan = true,
  }) {
    final host = _host;
    final url = (mediaUrl != null && mediaUrl.isNotEmpty) ? mediaUrl : (host?.videoUrl ?? '');
    if (url.trim().isEmpty) return;
    startSec = currentPosition ?? host?.currentPosition ?? 0;
    final playing = host?.isPlaying ?? false;
    final opening = host?.isOpening ?? false;
    final buffering = host?.isBuffering ?? false;
    // 打开中/缓冲中也要切到暂停态：弹窗出现应显示暂停，而不是卡在「既不加载也不暂停」。
    wasPlaying = playing || opening;
    if (playing || opening || buffering) {
      pausedForPicker = true;
      host?.pauseLocal();
    }
    PlayerCastSheet.show(
      context,
      mediaUrl: url,
      mediaTitle: (mediaTitle != null && mediaTitle.isNotEmpty)
          ? mediaTitle
          : (host?.title ?? AppBranding.defaultCastTitle),
      startPosition: startSec,
      startDuration: totalDuration ?? host?.totalDuration ?? 0,
      connectedUsn: connectedUsn,
      seedDevice: device,
      autoStartScan: autoStartScan,
      onCasted: (dev) => bindCastDevice(dev),
      onDismissed: () => resumeAfterPickerCancel(),
    );
  }

  void dispose() {
    session.dispose();
  }
}
