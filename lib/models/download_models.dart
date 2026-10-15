class DownloadTaskItem {
  final int id;
  final String mid;
  final int episode;
  final String status;
  final double progress;
  final String errMsg;

  const DownloadTaskItem({
    required this.id,
    required this.mid,
    required this.episode,
    required this.status,
    required this.progress,
    required this.errMsg,
  });

  factory DownloadTaskItem.fromJson(Map<String, dynamic> json) {
    return DownloadTaskItem(
      id: json['ID'] is int
          ? json['ID'] as int
          : int.tryParse('${json['ID'] ?? json['id'] ?? 0}') ?? 0,
      mid: '${json['mid'] ?? json['Mid'] ?? ''}'.trim(),
      episode: json['episode'] is int
          ? json['episode'] as int
          : int.tryParse('${json['episode'] ?? 0}') ?? 0,
      status: '${json['status'] ?? ''}'.trim(),
      progress: json['progress'] is num
          ? (json['progress'] as num).toDouble()
          : double.tryParse('${json['progress'] ?? 0}') ?? 0,
      errMsg: '${json['errMsg'] ?? ''}'.trim(),
    );
  }
}

const downloadStatusLabels = <String, String>{
  'queued': '排队中',
  'downloading': '正在下载',
  'organizing': '整理中',
  'done': '已完成',
  'failed': '失败',
  'canceled': '已取消',
};

const downloadActiveStatuses = {'queued', 'downloading', 'organizing'};

String downloadStatusText(DownloadTaskItem task) {
  final key = task.status;
  final label = downloadStatusLabels[key] ?? key;
  if (key == 'downloading' || key == 'organizing') {
    final pct = task.progress.round().clamp(0, 100);
    return '$label $pct%';
  }
  if (key == 'failed' && task.errMsg.isNotEmpty) {
    return '$label：${task.errMsg}';
  }
  return label;
}

/// 与 Web `normalizeNumericFilmId` 一致：仅纯数字 mid 可提交下载。
bool isDownloadableFilmId(String raw) {
  final s = raw.trim();
  return RegExp(r'^[1-9]\d*$').hasMatch(s);
}
