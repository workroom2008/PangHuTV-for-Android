import '../models/download_models.dart';
import 'http_client.dart';

class DownloadApi {
  static Future<bool> fetchEnabled() async {
    try {
      final res = await HttpClient.instance.get('/download/enabled');
      if (res.code != 0 || res.data is! Map) return false;
      final map = Map<String, dynamic>.from(res.data as Map);
      return map['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<DownloadTaskItem>> listMyTasks({
    required String mid,
    int limit = 20,
  }) async {
    final res = await HttpClient.instance.get(
      '/download/tasks/mine',
      params: {
        'mid': mid,
        'limit': limit,
      },
    );
    if (res.code != 0 || res.data is! List) return [];
    return (res.data as List)
        .whereType<Map>()
        .map((e) => DownloadTaskItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<ApiResponse> submitTask({
    required String mid,
    required int episode,
  }) async {
    return HttpClient.instance.post(
      '/download/tasks',
      body: {
        'mid': mid,
        'episode': episode,
      },
    );
  }
}
