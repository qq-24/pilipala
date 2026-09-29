import 'package:flutter/cupertino.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/member.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/models/home/rcmd/result.dart';
import 'package:pilipala/models/model_rec_video_item.dart';
import 'package:pilipala/utils/storage.dart';

class RcmdController extends GetxController {
  final ScrollController scrollController = ScrollController();
  int _currentPage = 0;
  // RxList<RecVideoItemAppModel> appVideoList = <RecVideoItemAppModel>[].obs;
  // RxList<RecVideoItemModel> webVideoList = <RecVideoItemModel>[].obs;
  bool isLoadingMore = true;
  OverlayEntry? popupDialog;
  Box setting = GStorage.setting;
  RxInt crossAxisCount = 2.obs;
  late bool enableSaveLastData;
  late String defaultRcmdType = 'web';
  late RxList<dynamic> videoList;
  // 本次会话已展示过的视频id（去重用，避免同一批反复出现）
  final Set<String> _seenIds = {};
  // 云端同步节流：超过7天未同步才跑一次
  static const int _cookieSyncInterval = 7 * 24 * 3600 * 1000;

  @override
  void onInit() {
    super.onInit();
    crossAxisCount.value =
        setting.get(SettingBoxKey.customRows, defaultValue: 2);
    enableSaveLastData =
        setting.get(SettingBoxKey.enableSaveLastData, defaultValue: false);
    defaultRcmdType =
        setting.get(SettingBoxKey.defaultRcmdType, defaultValue: 'web');
    if (defaultRcmdType == 'web') {
      videoList = <RecVideoItemModel>[].obs;
    } else {
      videoList = <RecVideoItemAppModel>[].obs;
    }
    // app端推荐：进入时自动检查并静默续期 access_key，防止token过期退化为游客内容
    if (defaultRcmdType == 'app') {
      _ensureFreshAccessKey();
    }
  }

  /// token缺失/归属与当前账号不符/剩余有效期不足5天 → 静默换发新token
  /// 登录态云端同步节流到7天一次：启动期只读缓存看时间戳，不发网
  Future<void> _ensureFreshAccessKey() async {
    try {
      final userInfo = GStorage.userInfo.get('userInfoCache');
      if (userInfo == null) return; // 未登录不续期
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int lastSync = int.tryParse(
              '${GStorage.localCache.get(LocalCacheKey.cookieSyncTs, defaultValue: 0)}') ??
          0;
      if (now - lastSync > _cookieSyncInterval) {
        // 原版APK同款登录态云端同步：静默续签会话cookie（失败则回退cookieToKey流程）
        final sync = await MemberHttp.cookieSync();
        if (sync['status'] == true) {
          await GStorage.localCache.put(LocalCacheKey.cookieSyncTs, now);
        }
      }
      final dynamic ak =
          GStorage.localCache.get(LocalCacheKey.accessKey, defaultValue: null);
      final int ts = int.tryParse('${ak?['ts'] ?? 0}') ?? 0;
      final int expiresIn =
          int.tryParse('${ak?['expires_in'] ?? 0}') ?? (30 * 24 * 3600);
      final bool needRenew = ak == null ||
          '${ak['value'] ?? ''}'.isEmpty ||
          '${ak['mid']}' != '${userInfo.mid}' ||
          // 旧版本存储没有签发时间，视为需要续期一次
          ts == 0 ||
          DateTime.now().millisecondsSinceEpoch - ts >
              (expiresIn - 5 * 24 * 3600) * 1000;
      if (needRenew) {
        await MemberHttp.cookieToKey(silent: true);
      }
    } catch (_) {
      // 静默失败不影响使用，下次启动重试
    }
  }

  /// 视频去重id：bvid优先，缺失则用aid兜底
  static String _itemId(dynamic e) {
    try {
      final bvid = e.bvid;
      if (bvid is String && bvid.isNotEmpty) return 'bv$bvid';
      final aid = e.aid;
      if (aid != null) return 'av$aid';
    } catch (_) {}
    return 'h${e.hashCode}';
  }

  // 获取推荐
  Future queryRcmdFeed(type) async {
    if (isLoadingMore == false) {
      return;
    }
    if (type == 'onRefresh') {
      _currentPage = 0;
    }
    Map<String, dynamic> res = {'status': false, 'data': [], 'msg': '未知错误'};
    List<dynamic> fresh = [];
    // 最多拉两页：下拉刷新撞上服务器回同一批时，自动再往后取一页，不转圈白刷
    for (int attempt = 0; attempt < 2; attempt++) {
      switch (defaultRcmdType) {
        case 'app':
        case 'notLogin':
          res = await VideoHttp.rcmdVideoListApp(
            loginStatus: defaultRcmdType != 'notLogin',
            freshIdx: _currentPage,
          );
          break;
        default: //'web'
          res = await VideoHttp.rcmdVideoList(
            freshIdx: _currentPage,
            ps: 20,
          );
      }
      if (!res['status']) break;
      fresh = (res['data'] as List)
          .where((e) => !_seenIds.contains(_itemId(e)))
          .toList();
      // 非刷新直接用；刷新撞车（全是见过的）且当前列表非空时翻一页重试一次
      if (type != 'onRefresh' || fresh.isNotEmpty || videoList.isEmpty) break;
      _currentPage += 1;
    }
    if (res['status']) {
      for (final e in fresh) {
        _seenIds.add(_itemId(e));
      }
      if (type == 'init') {
        if (videoList.isNotEmpty) {
          videoList.addAll(fresh);
        } else {
          videoList.value = fresh;
        }
      } else if (type == 'onRefresh') {
        if (enableSaveLastData) {
          videoList.insertAll(0, fresh);
        } else {
          videoList.value = fresh;
        }
      } else if (type == 'onLoad') {
        videoList.addAll(fresh);
      }
      _currentPage += 1;
      // 若videoList数量太小，可能会影响翻页，此时再次请求
      // 为避免请求到的数据太少时还在反复请求，要求本次返回数据大于1条才触发
      if (fresh.length > 1 && videoList.length < 10) {
        await queryRcmdFeed('onLoad');
      }
    } else if (type == 'onRefresh' || type == 'init') {
      // 小票/登录失效给一句看得见的提示（上拉加载失败不打扰刷列表）
      final String msg = '${res['msg'] ?? '请求失败'}';
      SmartDialog.showToast(defaultRcmdType == 'app'
          ? 'app端推荐失败：$msg，可尝试刷新access_key或切回web端'
          : '推荐加载失败：$msg');
    }
    isLoadingMore = false;
    return res;
  }

  // 切换推荐类型（设置页调用）：清列表热切换，立即生效，无需重启
  Future<void> switchRcmdType(String type) async {
    defaultRcmdType = type;
    _currentPage = 0;
    _seenIds.clear();
    videoList.clear();
    isLoadingMore = true;
    if (type == 'app') {
      // 小票缺失/不对版时等一次续期（25秒上限，不卡死）；已有有效小票直接用
      try {
        await _ensureFreshAccessKey()
            .timeout(const Duration(seconds: 25), onTimeout: () {});
      } catch (_) {}
    }
    await queryRcmdFeed('onRefresh');
  }

  // 下拉刷新
  Future onRefresh() async {
    isLoadingMore = true;
    await queryRcmdFeed('onRefresh');
  }

  // 上拉加载
  Future onLoad() async {
    await queryRcmdFeed('onLoad');
  }

  // 返回顶部
  void animateToTop() async {
    if (scrollController.offset >=
        MediaQuery.of(Get.context!).size.height * 5) {
      scrollController.jumpTo(0);
    } else {
      await scrollController.animateTo(0,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    }
  }

  void blockUserCb(mid) {
    videoList.removeWhere((e) => e.owner.mid == mid);
    videoList.refresh();
    SmartDialog.showToast('已移除相关视频');
  }
}
