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
  void _ensureFreshAccessKey() async {
    try {
      final userInfo = GStorage.userInfo.get('userInfoCache');
      if (userInfo == null) return; // 未登录不续期
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

  // 获取推荐
  Future queryRcmdFeed(type) async {
    if (isLoadingMore == false) {
      return;
    }
    if (type == 'onRefresh') {
      _currentPage = 0;
    }
    late final Map<String, dynamic> res;
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
    if (res['status']) {
      if (type == 'init') {
        if (videoList.isNotEmpty) {
          videoList.addAll(res['data']);
        } else {
          videoList.value = res['data'];
        }
      } else if (type == 'onRefresh') {
        if (enableSaveLastData) {
          videoList.insertAll(0, res['data']);
        } else {
          videoList.value = res['data'];
        }
      } else if (type == 'onLoad') {
        videoList.addAll(res['data']);
      }
      _currentPage += 1;
      // 若videoList数量太小，可能会影响翻页，此时再次请求
      // 为避免请求到的数据太少时还在反复请求，要求本次返回数据大于1条才触发
      if (res['data'].length > 1 && videoList.length < 10) {
        queryRcmdFeed('onLoad');
      }
    }
    isLoadingMore = false;
    return res;
  }

  // 下拉刷新
  Future onRefresh() async {
    isLoadingMore = true;
    queryRcmdFeed('onRefresh');
  }

  // 上拉加载
  Future onLoad() async {
    queryRcmdFeed('onLoad');
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
