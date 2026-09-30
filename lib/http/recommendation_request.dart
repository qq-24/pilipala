import '../utils/recommendation_state.dart';

Map<String, dynamic> appFeedParams(
        {required int idx,
        required bool pull,
        required int flush,
        required String key,
        String device = 'phone',
        String model = 'android',
        int column = 2}) =>
    {
      'idx': '$idx',
      'pull': '$pull',
      'flush': '$flush',
      'column': '$column',
      'device': device,
      'device_type': '0',
      'device_name': model,
      'build': '9130500',
      'mobi_app': 'android',
      'platform': 'android',
      'c_locale': 'zh_CN',
      's_locale': 'zh_CN',
      'network': 'wifi',
      'login_event': key.isEmpty ? '1' : '0',
      'recsys_mode': '0',
      'access_key': key,
    };

Map<String, dynamic> appFeedMeta(dynamic body) {
  final data = body is Map ? body['data'] : null;
  final raw =
      body is Map && body['data'] is Map && body['data']['items'] is List
          ? body['data']['items'] as List
          : const [];
  final cursors = raw
      .whereType<Map>()
      .map((e) => feedInt(e['idx']))
      .whereType<int>()
      .toList();
  final ids = raw
      .whereType<Map>()
      .map((e) => feedInt(e['player_args']?['aid'] ??
          e['args']?['aid'] ??
          (e['goto'] == 'av' ? e['param'] : null)))
      .whereType<int>()
      .where((e) => e > 0)
      .toList();
  return {
    'rawCount': raw.length,
    'rawIds': ids,
    'headIdx': cursors.isEmpty ? null : cursors.first,
    'tailIdx': cursors.isEmpty ? null : cursors.last,
    'pegasusCode': data is Map && data['config'] is Map
        ? data['config']['pegasus_code']
        : null
  };
}
