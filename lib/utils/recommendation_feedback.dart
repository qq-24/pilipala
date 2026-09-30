import 'dart:async';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../http/init.dart';
import '../models/home/rcmd/result.dart';
import 'diag_log.dart';
import 'recommendation_codec.dart';
import 'storage.dart';

class RecommendationFeedback {
  static final instance = RecommendationFeedback();
  final _pending = <Map<String, dynamic>>[];
  final _session = const Uuid().v4();
  Timer? _timer;
  bool _sending = false;
  int _sequence = 0;
  AndroidDeviceInfo? _device;

  void add(RecVideoItemAppModel item, String event, int position,
      {int? start, int? end, bool click = false}) {
    if (GStorage.localCache.get(LocalCacheKey.historyPause) == true ||
        item.trackId == null ||
        item.trackId!.isEmpty) return;
    final mid = GStorage.userInfo.get('userInfoCache')?.mid;
    if (mid == null || item.feedAccount != '$mid') return;
    final time = DateTime.now().millisecondsSinceEpoch;
    final fields = <String, String>{
      for (final entry in item.reportFields.entries)
        entry.key: '${entry.value}',
      'spmid': 'tm.recommend.0.0',
      'position': '$position',
      if (start != null) 'card_start_time': '$start',
      if (end != null) 'card_end_time': '$end',
      'client': 'pilipala',
    };
    if (_pending.length >= 100) _pending.removeAt(0);
    _pending.add({
      'name': event,
      'mid': '$mid',
      'time': time,
      'fields': fields,
      'sequence': ++_sequence,
      'click': click,
      'attempt': 0
    });
    _timer ??= Timer(const Duration(seconds: 3), () {
      _timer = null;
      flush();
    });
  }

  Future<void> flush() async {
    if (_sending || _pending.isEmpty) return;
    if (GStorage.localCache.get(LocalCacheKey.historyPause) == true) {
      _pending.clear();
      return;
    }
    final mid = '${GStorage.userInfo.get('userInfoCache')?.mid ?? ''}';
    final now = DateTime.now().millisecondsSinceEpoch;
    _pending.removeWhere(
        (e) => e['mid'] != mid || now - (e['time'] as int) > 120000);
    if (_pending.isEmpty) return;
    final batch = _pending.take(20).toList();
    _pending.removeRange(0, batch.length);
    _sending = true;
    final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8)));
    try {
      _device ??= await DeviceInfoPlugin().androidInfo;
      final buvid = await Request.getBuvid();
      if (buvid.isEmpty) return;
      final network = await Connectivity().checkConnectivity();
      final bytes = BytesBuilder(copy: false);
      for (final event in batch) {
        bytes.add(RecommendationCodec.event(
            name: event['name'],
            fields: event['fields'],
            mid: event['mid'],
            buvid: buvid,
            time: event['time'],
            sequence: event['sequence'],
            session: _session,
            click: event['click'],
            model: _device!.model,
            brand: _device!.brand,
            os: _device!.version.release,
            api: _device!.version.sdkInt,
            abi: _device!.supportedAbis.isEmpty
                ? ''
                : _device!.supportedAbis.first,
            network: network.contains(ConnectivityResult.wifi)
                ? 1
                : network.contains(ConnectivityResult.mobile)
                    ? 2
                    : 0));
      }
      // Dedicated client: the analytics host receives no login cookies or token.
      final payload = bytes.takeBytes();
      final response = await dio.post(
          'https://dataflow.biliapi.com/log/pbmobile/unrealtime?android',
          data: Stream.value(payload),
          options: Options(
              contentType: 'application/octet-stream',
              responseType: ResponseType.plain,
              headers: {'Neuron-Events': '${batch.length}', 'Content-Length': '${payload.length}'}));
      DiagLog.write(
          '[RCMD_REPORT] events=${batch.length} http=${response.statusCode}');
    } catch (_) {
      DiagLog.write('[RCMD_REPORT] events=${batch.length} send_failed');
      for (final event in batch) {
        if ((event['attempt'] as int) < 1 && _pending.length < 100) {
          event['attempt'] = (event['attempt'] as int) + 1;
          _pending.add(event);
        }
      }
    } finally {
      dio.close(force: true);
      _sending = false;
      if (_pending.isNotEmpty) {
        _timer ??= Timer(const Duration(seconds: 15), () {
          _timer = null;
          flush();
        });
      }
    }
  }
}
