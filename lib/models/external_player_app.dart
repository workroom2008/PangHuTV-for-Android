/// 可打开网络视频流的第三方应用（Android 包名 + 显示名）
class ExternalPlayerApp {
  final String packageName;
  final String label;

  const ExternalPlayerApp({
    required this.packageName,
    required this.label,
  });

  bool get isSystemDefault => packageName.isEmpty;

  factory ExternalPlayerApp.fromMap(Map<dynamic, dynamic> map) {
    return ExternalPlayerApp(
      packageName: '${map['package'] ?? ''}',
      label: '${map['label'] ?? ''}',
    );
  }
}
