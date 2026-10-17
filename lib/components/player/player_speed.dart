/// 倍速与横向拖动范围，对齐 OHOS `PlayerSpeed`
class PlayerSpeed {
  static const List<double> rates = [0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
  static const double defaultRate = 1.0;
  static const double fastRate = 2.0;

  static const int minSeekMs = 3 * 60 * 1000;
  static const int maxSeekMs = 12 * 60 * 1000;

  static String label(double rate) {
    if ((rate - rate.roundToDouble()).abs() < 0.01) {
      return '${rate.toStringAsFixed(1)}x';
    }
    return '${rate}x';
  }

  /// duration 为秒。横向拖动映射区间：3–12 分钟，且不超过片长的 35%。
  static double seekRangeMs(double durationSec) {
    final durationMs = durationSec * 1000;
    if (durationMs <= 0) return 0;
    final proportional = durationMs * 0.35;
    final capped = durationMs < maxSeekMs ? durationMs : maxSeekMs.toDouble();
    final lo = proportional < minSeekMs ? minSeekMs.toDouble() : proportional;
    return lo < capped ? lo : capped;
  }
}
