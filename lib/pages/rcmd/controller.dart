import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/member.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/utils/diag_log.dart';
import 'package:pilipala/utils/recommendation_state.dart';
import 'package:pilipala/utils/storage.dart';

typedef RecommendationFetcher = Future<Map<String, dynamic>> Function(
    String mode, int idx, bool pull, int flush, CancelToken token);

class RcmdController extends GetxController {
  final RecommendationFetcher? fetchOverride;
  RcmdController({this.fetchOverride});
  final scrollController = ScrollController();
  final Box setting = GStorage.setting;
  final crossAxisCount = 2.obs;
  final RxList<dynamic> videoList = <dynamic>[].obs;
  OverlayEntry? popupDialog;
  bool isLoadingMore = false;
  bool _busy = false;
  bool enableSaveLastData = false;
  String defaultRcmdType = 'web';
  int _webFresh = 0, _generation = 0;
  final _cursor = AppFeedCursor();
  CancelToken? _cancel;
  Future<Map<String, dynamic>>? _pending;
  Future<void>? _keyReady;
  RecommendationSeen _seen = RecommendationSeen();
  String _scope = '';
  String get exposureScope => _scope;
  Timer? _seenWrite;

  String get _currentScope =>
      '${defaultRcmdType == 'notLogin' ? 'guest' : GStorage.userInfo.get('userInfoCache')?.mid ?? 'guest'}:$defaultRcmdType';

  @override
  void onInit() {
    super.onInit();
    crossAxisCount.value =
        setting.get(SettingBoxKey.customRows, defaultValue: 2);
    defaultRcmdType =
        setting.get(SettingBoxKey.defaultRcmdType, defaultValue: 'web');
    _loadScope();
    _keyReady = _prepareKey();
  }

  void _loadScope() {
    _saveSeen();
    _seenWrite?.cancel();
    _scope = _currentScope;
    _seen = RecommendationSeen(
        GStorage.localCache.get('recommendationSeenV2:$_scope'));
    _seen.prune(DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _prepareKey() async {
    if (defaultRcmdType != 'app') return;
    final user = GStorage.userInfo.get('userInfoCache');
    if (user == null) return;
    final key = GStorage.localCache.get(LocalCacheKey.accessKey);
    final ts = feedInt(key?['ts']) ?? 0;
    final expires = feedInt(key?['expires_in']) ?? 30 * 86400;
    final valid = key is Map &&
        '${key['value'] ?? ''}'.isNotEmpty &&
        '${key['mid']}' == '${user.mid}' &&
        ts > 0 &&
        DateTime.now().millisecondsSinceEpoch - ts <
            (expires - 5 * 86400) * 1000;
    if (valid) return;
    try {
      await MemberHttp.cookieToKey(silent: true)
          .timeout(const Duration(seconds: 25));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> queryRcmdFeed(String type) {
    final refresh = type == 'onRefresh';
    if (_busy && !refresh)
      return _pending ??
          Future.value({'status': true, 'data': videoList.toList()});
    if (_scope != _currentScope) {
      _loadScope();
      _cursor.reset();
      videoList.clear();
    }
    _cancel?.cancel('recommendation superseded');
    final token = _cancel = CancelToken();
    final generation = ++_generation;
    _busy = true;
    isLoadingMore = true;
    enableSaveLastData =
        setting.get(SettingBoxKey.enableSaveLastData, defaultValue: false);
    videoList.refresh();
    return _pending = _run(type, generation, token, _scope);
  }

  Future<Map<String, dynamic>> _run(
      String type, int generation, CancelToken token, String scope) async {
    final refresh = type == 'onRefresh';
    final app = defaultRcmdType != 'web';
    final mode = defaultRcmdType;
    var result = <String, dynamic>{
      'status': false,
      'data': [],
      'msg': '推荐请求失败'
    };
    final additions = <dynamic>[];
    final excluded =
        videoList.map(recommendationId).whereType<String>().toSet();
    final now = DateTime.now().millisecondsSinceEpoch;
    _seen.prune(now);
    excluded.addAll(_seen.entries.keys);
    bool current() =>
        generation == _generation &&
        scope == _currentScope &&
        !token.isCancelled;
    try {
      await _keyReady;
      if (!current()) return {'status': false, 'cancelled': true};
      // Bounded filling, rather than recursively making unbounded page requests.
      for (var attempt = 0; attempt < 3; attempt++) {
        final pull = attempt == 0 && (refresh || type == 'init');
        final flush = pull ? (refresh ? 6 : 0) : 8;
        final requestIdx = _cursor.head;
        final response = fetchOverride != null
            ? await fetchOverride!(mode, requestIdx, pull, flush, token)
            : app
                ? await VideoHttp.rcmdVideoListApp(
                    loginStatus: mode == 'app',
                    idx: requestIdx,
                    pull: pull,
                    flush: flush,
                    cancelToken: token)
                : await VideoHttp.rcmdVideoList(freshIdx: _webFresh++, ps: 20);
        if (!current()) return {'status': false, 'cancelled': true};
        result = Map<String, dynamic>.from(response);
        if (result['status'] != true) break;
        if (app)
          _cursor.accept(feedInt(result['headIdx']), feedInt(result['tailIdx']),
              refresh: pull || _cursor.head == 0);
        final batch =
            uniqueRecommendations<dynamic>(result['data'] as List, excluded);
        additions.addAll(batch);
        excluded.addAll(batch.map(recommendationId).whereType<String>());
        DiagLog.write(
            '[RCMD_DEDUP] mode=$mode action=$type attempt=$attempt returned=${(result['data'] as List).length} new=${batch.length}');
        if (additions.length >= 6) break;
      }
      if (!current()) return {'status': false, 'cancelled': true};
      if (additions.isNotEmpty) {
        if (refresh && !enableSaveLastData)
          videoList.assignAll(additions);
        else if (refresh)
          videoList.insertAll(0, additions);
        else
          videoList.addAll(additions);
        // Retained content is bounded; it is not duplicated by refresh.
        if (videoList.length > 300)
          videoList.removeRange(300, videoList.length);
        return {'status': true, 'data': videoList.toList()};
      }
      if (result['status'] == true) {
        if (refresh) SmartDialog.showToast('暂时没有新的推荐，已保留当前内容');
        return {'status': true, 'data': videoList.toList()};
      }
      if (refresh || type == 'init')
        SmartDialog.showToast('推荐加载失败：${result['msg']}');
      return result;
    } catch (_) {
      return {'status': false, 'data': [], 'msg': '推荐加载失败'};
    } finally {
      if (generation == _generation) {
        _busy = false;
        isLoadingMore = false;
        _pending = null;
        videoList.refresh();
      }
    }
  }

  void exposed(dynamic item, {String? scope}) {
    if (_scope != _currentScope || (scope != null && scope != _scope)) return;
    final id = recommendationId(item);
    if (id == null) return;
    _seen.mark(id, DateTime.now().millisecondsSinceEpoch);
    _seenWrite ??= Timer(const Duration(milliseconds: 500), () {
      _seenWrite = null;
      _saveSeen();
    });
  }

  void _saveSeen() {
    if (_scope.isEmpty) return;
    GStorage.localCache
        .put('recommendationSeenV2:$_scope',
            Map<String, int>.from(_seen.entries))
        .catchError((_) {});
  }

  Future<void> switchRcmdType(String type) async {
    _cancel?.cancel('recommendation type changed');
    ++_generation;
    _busy = false;
    _pending = null;
    defaultRcmdType = type;
    _cursor.reset();
    _webFresh = 0;
    _loadScope();
    videoList.clear();
    _keyReady = _prepareKey();
    await queryRcmdFeed('onRefresh');
  }

  Future onRefresh() => queryRcmdFeed('onRefresh');
  Future onLoad() => queryRcmdFeed('onLoad');
  void removeFeedbackItem(dynamic item) {
    exposed(item);
    final id = recommendationId(item);
    videoList.removeWhere((e) => recommendationId(e) == id);
  }

  void animateToTop() {
    if (!scrollController.hasClients) return;
    scrollController.animateTo(0,
        duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
  }

  void blockUserCb(mid) {
    videoList.removeWhere((e) => e.owner?.mid == mid);
    SmartDialog.showToast('已移除相关视频');
  }

  @override
  void onClose() {
    _cancel?.cancel('recommendation closed');
    ++_generation;
    _seenWrite?.cancel();
    _saveSeen();
    scrollController.dispose();
    super.onClose();
  }
}
