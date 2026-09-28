import 'dart:convert';
import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/utils/id_utils.dart';
import 'package:pilipala/models/video/tags.dart';
import '../common/constants.dart';
import '../models/common/reply_type.dart';
import '../models/home/rcmd/result.dart';
import '../models/model_hot_video_item.dart';
import '../models/model_rec_video_item.dart';
import '../models/user/fav_folder.dart';
import '../models/video/ai.dart';
import '../models/video/play/url.dart';
import '../models/video/subTitile/result.dart';
import '../models/video_detail_res.dart';
import '../utils/diag_log.dart';
import '../utils/recommend_filter.dart';
import '../utils/storage.dart';
import '../utils/subtitle.dart';
import '../utils/utils.dart';
import '../utils/wbi_sign.dart';
import 'api.dart';
import 'init.dart';

/// res.data['code'] == 0 请求正常返回结果
/// res.data['data'] 为结果
/// 返回{'status': bool, 'data': List}
/// view层根据 status 判断渲染逻辑
class VideoHttp {
  static Box localCache = GStorage.localCache;
  static Box setting = GStorage.setting;
  static bool enableRcmdDynamic =
      setting.get(SettingBoxKey.enableRcmdDynamic, defaultValue: true);
  static Box userInfoCache = GStorage.userInfo;

  // 首页推荐视频
  static Future rcmdVideoList({required int ps, required int freshIdx}) async {
    try {
      var res = await Request().get(
        Api.recommendListWeb,
        data: {
          'version': 1,
          'feed_version': 'V3',
          'homepage_ver': 1,
          'ps': ps,
          'fresh_idx': freshIdx,
          'brush': freshIdx,
          'fresh_type': 4
        },
      );
      if (res.data['code'] == 0) {
        List<RecVideoItemModel> list = [];
        List<int> blackMidsList =
            setting.get(SettingBoxKey.blackMidsList, defaultValue: [-1]);
        for (var i in res.data['data']['item']) {
          //过滤掉live与ad，以及拉黑用户
          if (i['goto'] == 'av' &&
              (i['owner'] != null &&
                  !blackMidsList.contains(i['owner']['mid']))) {
            RecVideoItemModel videoItem = RecVideoItemModel.fromJson(i);
            if (!RecommendFilter.filter(videoItem)) {
              list.add(videoItem);
            }
          }
        }
        return {'status': true, 'data': list};
      } else {
        return {'status': false, 'data': [], 'msg': res.data['message']};
      }
    } catch (err) {
      return {'status': false, 'data': [], 'msg': err.toString()};
    }
  }

  // 添加额外的loginState变量模拟未登录状态
  static Future rcmdVideoListApp(
      {bool loginStatus = true, required int freshIdx}) async {
    var res = await Request().get(
      Api.recommendListApp,
      data: {
        'idx': freshIdx,
        'flush': '5',
        'column': '4',
        'device': 'pad',
        'device_type': 0,
        'device_name': 'vivo',
        'pull': freshIdx == 0 ? 'true' : 'false',
        'appkey': Constants.appKey,
        'access_key': loginStatus
            ? (localCache
                    .get(LocalCacheKey.accessKey, defaultValue: {})['value'] ??
                '')
            : ''
      },
    );
    if (res.data['code'] == 0) {
      List<RecVideoItemAppModel> list = [];
      List<int> blackMidsList =
          setting.get(SettingBoxKey.blackMidsList, defaultValue: [-1]);
      for (var i in res.data['data']['items']) {
        // 屏蔽推广和拉黑用户
        if (i['card_goto'] != 'ad_av' &&
            i['card_goto'] != 'ad_web_s' &&
            i['card_goto'] != 'ad_web' &&
            (!enableRcmdDynamic ? i['card_goto'] != 'picture' : true) &&
            (i['args'] != null &&
                !blackMidsList.contains(i['args']['up_mid']))) {
          RecVideoItemAppModel videoItem = RecVideoItemAppModel.fromJson(i);
          if (!RecommendFilter.filter(videoItem)) {
            list.add(videoItem);
          }
        }
      }
      return {'status': true, 'data': list};
    } else {
      return {'status': false, 'data': [], 'msg': res.data['message']};
    }
  }

  // 诊断app端推荐登录态 v3（证据版）
  // live = 与首页完全一致的请求（key+全局cookie）；guest = 独立裸Dio真游客（无cookie无key）
  // 串行请求、各自独立idx，避免并发同idx触发风控；并展示双方标题供目核
  static Future diagnoseAppRcmd() async {
    final int base =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 % 99990000;

    Map<String, dynamic> parseBody(dynamic body) {
      if (body is! Map) {
        final String s = body?.toString() ?? 'null';
        return {
          'code': -99,
          'msg': '非JSON: ${s.substring(0, s.length < 60 ? s.length : 60)}',
          'aids': <int>{},
          'titles': <String>[],
        };
      }
      final int code = int.tryParse('${body['code']}') ?? -1;
      if (code != 0) {
        return {
          'code': code,
          'msg': body['message'],
          'aids': <int>{},
          'titles': <String>[]
        };
      }
      final Set<int> aids = {};
      final List<String> titles = [];
      for (var i in (body['data']?['items'] ?? [])) {
        final int aid = int.tryParse('${i['args']?['idy']}') ?? -1;
        if (aid > 0) {
          aids.add(aid);
        }
        final String t = '${i['title'] ?? ''}';
        if (t.isNotEmpty) {
          titles.add(t.length > 28 ? '${t.substring(0, 28)}…' : t);
        }
      }
      return {'code': 0, 'msg': 'OK', 'aids': aids, 'titles': titles};
    }

    Map<String, dynamic> errResult(Object e) => {
          'code': -98,
          'msg': '请求异常: $e',
          'aids': <int>{},
          'titles': <String>[]
        };

    Future<Map<String, dynamic>> fetchViaApp(Map<String, dynamic> params) async {
      try {
        var res = await Request().get(Api.recommendListApp, data: params);
        return parseBody(res.data);
      } catch (e) {
        return errResult(e);
      }
    }

    Future<Map<String, dynamic>> fetchTrueGuest(int idx) async {
      Dio? bare;
      try {
        bare = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
          headers: const {
            'user-agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ));
        var res = await bare.getUri(
            Uri.https('app.bilibili.com', '/x/v2/feed/index', {
          'idx': '$idx',
          'flush': '5',
          'column': '4',
          'device': 'pad',
          'device_type': '0',
          'device_name': 'vivo',
          'pull': 'true',
          'appkey': Constants.appKey,
          'access_key': '',
        }));
        return parseBody(res.data);
      } catch (e) {
        return errResult(e);
      } finally {
        bare?.close(force: true);
      }
    }

    try {
      final String key =
          localCache.get(LocalCacheKey.accessKey, defaultValue: {})['value'] ??
              '';
      if (key.isEmpty) {
        return {
          'status': false,
          'msg': '未获取到access_key，请先在「隐私设置」点“刷新access_key”后再诊断'
        };
      }
      const Map<String, dynamic> common = {
        'flush': '5',
        'column': '4',
        'device': 'pad',
        'device_type': '0',
        'device_name': 'vivo',
        'pull': 'true',
        'appkey': Constants.appKey,
      };
      // 串行 + 各自独立idx，避免并发同idx被风控
      final live = await fetchViaApp({
        ...common,
        'idx': '${base + 1}',
        'access_key': key,
      });
      final signedParams = <String, dynamic>{
        ...common,
        'idx': '${base + 2}',
        'access_key': key,
        'ts': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      };
      signedParams['sign'] =
          Utils.appSign(signedParams, Constants.appKey, Constants.appSec);
      final signed = await fetchViaApp(signedParams);
      var guest = await fetchTrueGuest(base + 3);
      if (guest['code'] != 0) {
        await Future.delayed(const Duration(milliseconds: 800));
        guest = await fetchTrueGuest(base + 4); // 换idx重试一次
      }
      if (live['code'] != 0) {
        return {
          'status': false,
          'msg': '当前推荐请求失败（code=${live['code']} ${live['msg']}），请稍后重试'
        };
      }
      double overlap(Map<String, dynamic> a, Map<String, dynamic> b) {
        final Set<int> x = a['aids'];
        final Set<int> y = b['aids'];
        return x.isEmpty ? 0 : x.intersection(y).length / x.length;
      }

      return {
        'status': true,
        'guestOk': guest['code'] == 0 && (guest['aids'] as Set).isNotEmpty,
        'guestErr': '${guest['code']} ${guest['msg']}',
        'overlap': overlap(live, guest),
        'signedOverlap': overlap(signed, guest),
        'signedCode': signed['code'],
        'liveCount': (live['aids'] as Set).length,
        'liveTitles': (live['titles'] as List).take(6).toList(),
        'guestTitles': (guest['titles'] as List).take(6).toList(),
      };
    } catch (err) {
      log('diagnoseAppRcmd exception: $err');
      return {'status': false, 'msg': '诊断异常：$err'};
    }
  }

  // 最热视频
  static Future hotVideoList({required int pn, required int ps}) async {
    try {
      var res = await Request().get(
        Api.hotList,
        data: {'pn': pn, 'ps': ps},
      );
      if (res.data['code'] == 0) {
        List<HotVideoItemModel> list = [];
        List<int> blackMidsList =
            setting.get(SettingBoxKey.blackMidsList, defaultValue: [-1]);
        for (var i in res.data['data']['list']) {
          if (!blackMidsList.contains(i['owner']['mid'])) {
            list.add(HotVideoItemModel.fromJson(i));
          }
        }
        return {'status': true, 'data': list};
      } else {
        return {'status': false, 'data': [], 'msg': res.data['message']};
      }
    } catch (err) {
      return {'status': false, 'data': [], 'msg': err};
    }
  }

  // 视频流
  static Future videoUrl(
      {int? avid, String? bvid, required int cid, int? qn}) async {
    Map<String, dynamic> data = {
      'cid': cid,
      'qn': qn ?? 80,
      // 获取所有格式的视频
      'fnval': 4048,
    };
    if (avid != null) {
      data['avid'] = avid;
    }
    if (bvid != null) {
      data['bvid'] = bvid;
    }

    // 免登录查看1080p
    if (userInfoCache.get('userInfoCache') == null &&
        setting.get(SettingBoxKey.p1080, defaultValue: true)) {
      data['try_look'] = 1;
    }

    Map params = await WbiSign().makSign({
      ...data,
      'fourk': 1,
      'voice_balance': 1,
      'gaia_source': 'pre-load',
      'web_location': 1550101,
    });

    try {
      var res = await Request().get(Api.videoUrl, data: params);
      if (res.data['code'] == 0) {
        return {
          'status': true,
          'data': PlayUrlModel.fromJson(res.data['data'])
        };
      } else {
        return {
          'status': false,
          'data': [],
          'code': res.data['code'],
          'msg': res.data['message'],
        };
      }
    } catch (err) {
      return {'status': false, 'data': [], 'msg': err};
    }
  }

  // 视频信息 标题、简介
  static Future videoIntro({required String bvid}) async {
    var res = await Request().get(Api.videoIntro, data: {'bvid': bvid});
    if (res.data['code'] == 0) {
      VideoDetailResponse result = VideoDetailResponse.fromJson(res.data);
      return {'status': true, 'data': result.data!};
    } else {
      return {
        'status': false,
        'data': null,
        'code': res.data['code'],
        'msg': res.data['message'],
      };
    }
  }

  // 相关视频
  static Future relatedVideoList({required String bvid}) async {
    var res = await Request().get(Api.relatedList, data: {'bvid': bvid});
    if (res.data['code'] == 0) {
      List<HotVideoItemModel> list = [];
      for (var i in res.data['data']) {
        HotVideoItemModel videoItem = HotVideoItemModel.fromJson(i);
        if (!RecommendFilter.filter(videoItem, relatedVideos: true)) {
          list.add(videoItem);
        }
      }
      return {'status': true, 'data': list};
    } else {
      return {'status': false, 'data': []};
    }
  }

  // 获取点赞状态
  static Future hasLikeVideo({required String bvid}) async {
    var res = await Request().get(Api.hasLikeVideo, data: {'bvid': bvid});
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false, 'data': []};
    }
  }

  // 获取投币状态
  static Future hasCoinVideo({required String bvid}) async {
    var res = await Request().get(Api.hasCoinVideo, data: {'bvid': bvid});
    print('res: $res');
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false, 'data': []};
    }
  }

  // 投币
  static Future coinVideo({required String bvid, required int multiply}) async {
    var res = await Request().post(
      Api.coinVideo,
      data: {
        'bvid': bvid,
        'multiply': multiply,
        'select_like': 0,
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false, 'data': [], 'msg': res.data['message']};
    }
  }

  // 获取收藏状态
  static Future hasFavVideo({required int aid}) async {
    var res = await Request().get(Api.hasFavVideo, data: {'aid': aid});
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false, 'data': []};
    }
  }

  // 一键三连
  static Future oneThree({required String bvid}) async {
    var res = await Request().post(
      Api.oneThree,
      data: {
        'bvid': bvid,
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false, 'data': [], 'msg': res.data['message']};
    }
  }

  // 点赞实验实验室：对同一支视频逐一测试请求形态变体（每变体 点赞→取消 复原），
  // 结果写 diag.log，用于确定 B站 like 端点当前接受哪种请求形态
  static Future likeLab() async {
    try {
      final rcmd = await rcmdVideoListApp(loginStatus: true, freshIdx: 0);
      if (!rcmd['status'] || (rcmd['data'] as List).isEmpty) {
        DiagLog.write('[LIKELAB] no-video');
        return;
      }
      final RecVideoItemAppModel item = (rcmd['data'] as List).first;
      final String bvid = '${item.bvid ?? ''}';
      if (bvid.isEmpty) {
        DiagLog.write('[LIKELAB] no-bvid');
        return;
      }
      final String csrf = await Request.getCsrf();
      const String webUA =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

      Future<void> variant(String name, Future<dynamic> Function() fn) async {
        try {
          final res = await fn();
          final body = res is Response ? res.data : res;
          if (body is Map) {
            DiagLog.write(
                '[LIKELAB] $name code=${body['code']} msg=${body['message']}');
          } else {
            DiagLog.write('[LIKELAB] $name non-JSON(${res.runtimeType})');
          }
        } catch (e) {
          DiagLog.write('[LIKELAB] $name exception=$e');
        }
      }

      // A 当前形态：form、默认UA
      Future<dynamic> a(int like) => Request().post(Api.likeVideo,
          data: {'bvid': bvid, 'like': like, 'csrf': csrf});
      await variant('A-form-noUA-like', () => a(1));
      await variant('A-form-noUA-unlike', () => a(2));

      // B 仅加浏览器UA
      Future<dynamic> b(int like) => Request().post(
          Api.likeVideo,
          data: {'bvid': bvid, 'like': like, 'csrf': csrf},
          options: Options(headers: {'user-agent': webUA}));
      await variant('B-form-webUA-like', () => b(1));
      await variant('B-form-webUA-unlike', () => b(2));

      // C 对齐现行web：wbi签名query + JSON body + 浏览器UA + 视频页referer
      final Map<String, dynamic> signed = await WbiSign().makSign({
        'platform': 'web',
        'web_location': '333.1387',
        'csrf': csrf,
      });
      Future<dynamic> c(int like) => Request().post(
          Api.likeVideo,
          queryParameters: {
            'platform': 'web',
            'web_location': '333.1387',
            'csrf': csrf,
            'w_rid': signed['w_rid'],
            'wts': signed['wts'],
          },
          data: {'bvid': bvid, 'like': like},
          options: Options(
              contentType: Headers.jsonContentType,
              headers: {
                'user-agent': webUA,
                'referer': 'https://www.bilibili.com/video/$bvid/',
              }));
      await variant('C-wbi-json-like', () => c(1));
      await variant('C-wbi-json-unlike', () => c(2));

      // ===== 第二轮（round2）：补 Origin 等缺失要素 =====
      const String origin = 'https://www.bilibili.com';
      final Map<String, String> webHdrs = {
        'user-agent': webUA,
        'origin': origin,
        'referer': 'https://www.bilibili.com/video/$bvid/',
      };

      // D form + webUA + Origin + referer
      Future<dynamic> d(int like) => Request().post(Api.likeVideo,
          data: {'bvid': bvid, 'like': like, 'csrf': csrf},
          options: Options(headers: webHdrs));
      await variant('D2-form-origin-like', () => d(1));
      await variant('D2-form-origin-unlike', () => d(2));

      // G 全参数进query并整体wbi签名，无body（签名必须用实际like值现算）
      Future<Map<String, dynamic>> gq(int like) => WbiSign().makSign({
            'bvid': bvid,
            'like': like,
            'platform': 'web',
            'web_location': '333.1387',
            'csrf': csrf,
          });
      Future<dynamic> g(int like) async => Request().post(Api.likeVideo,
          queryParameters: await gq(like),
          options: Options(headers: webHdrs));

      await variant('D2-fullquery-wbi-like', () => g(1));
      await variant('D2-fullquery-wbi-unlike', () => g(2));

      // H 同C形状但补Origin（C失败可能因缺Origin被判参数错）
      Future<dynamic> h(int like) => Request().post(
          Api.likeVideo,
          queryParameters: {
            'platform': 'web',
            'web_location': '333.1387',
            'csrf': csrf,
            'w_rid': signed['w_rid'],
            'wts': signed['wts'],
          },
          data: {'bvid': bvid, 'like': like},
          options: Options(
              contentType: Headers.jsonContentType, headers: webHdrs));
      await variant('D2-wbi-json-origin-like', () => h(1));
      await variant('D2-wbi-json-origin-unlike', () => h(2));

      // J 双保险：签名query带全部参数 + form body 再带一份
      Future<dynamic> j(int like) async => Request().post(Api.likeVideo,
          queryParameters: await gq(like),
          data: {'bvid': bvid, 'like': like, 'csrf': csrf},
          options: Options(headers: webHdrs));

      await variant('D2-query-and-form-like', () => j(1));
      await variant('D2-query-and-form-unlike', () => j(2));

      // K 软拒绝验证：点赞→回读→取消→回读，确认-403下操作是否实际生效
      await variant('D3-g-like', () => g(1));
      final bool afterLike = await hasLiked(bvid);
      DiagLog.write('[LIKELAB] D3-has-like-after=$afterLike');
      await variant('D3-g-unlike', () => g(2));
      final bool afterUnlike = await hasLiked(bvid);
      DiagLog.write('[LIKELAB] D3-has-like-afterUnlike=$afterUnlike');
    } catch (e) {
      DiagLog.write('[LIKELAB] fatal $e');
    }
  }

  // 回读点赞状态（只读接口）
  static Future<bool> hasLiked(String bvid) async {
    try {
      var res = await Request().get(
        '/x/web-interface/archive/has/like',
        data: {'bvid': bvid},
      );
      final body = res.data;
      if (body is Map && body['code'] == 0) {
        return body['data'] == true;
      }
    } catch (e) {
      log('hasLiked error: $e');
    }
    return false;
  }

  // （取消）点赞
  static Future likeVideo({required String bvid, required bool type}) async {
    var res = await Request().post(
      Api.likeVideo,
      data: {
        'bvid': bvid,
        'like': type ? 1 : 2,
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else if (res.data['code'] == -403) {
      // B站风控“软拒绝”：-403时操作可能已实际生效，以只读接口回读为准
      final bool actuallyLiked = await hasLiked(bvid);
      if (actuallyLiked == type) {
        DiagLog.write('[LIKE-FB] -403 soft-deny, actual state=$actuallyLiked');
        return {'status': true, 'data': actuallyLiked};
      }
      return {'status': false, 'data': [], 'msg': res.data['message']};
    } else {
      return {'status': false, 'data': [], 'msg': res.data['message']};
    }
  }

  // （取消）收藏
  static Future favVideo(
      {required int aid, String? addIds, String? delIds}) async {
    var res = await Request().post(
      Api.favVideo,
      data: {
        'rid': aid,
        'type': 2,
        'add_media_ids': addIds ?? '',
        'del_media_ids': delIds ?? '',
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false, 'data': [], 'msg': res.data['message']};
    }
  }

  // 查看视频被收藏在哪个文件夹
  static Future videoInFolder({required int mid, required int rid}) async {
    var res = await Request()
        .get(Api.videoInFolder, data: {'up_mid': mid, 'rid': rid});
    if (res.data['code'] == 0) {
      FavFolderData data = FavFolderData.fromJson(res.data['data']);
      return {'status': true, 'data': data};
    } else {
      return {'status': false, 'data': []};
    }
  }

  // 发表评论 replyAdd

  // type	num	评论区类型代码	必要	类型代码见表
  // oid	num	目标评论区id	必要
  // root	num	根评论rpid	非必要	二级评论以上使用
  // parent	num	父评论rpid	非必要	二级评论同根评论id 大于二级评论为要回复的评论id
  // message	str	发送评论内容	必要	最大1000字符
  // plat	num	发送平台标识	非必要	1：web端 2：安卓客户端  3：ios客户端  4：wp客户端
  static Future replyAdd({
    required ReplyType type,
    required int oid,
    required String message,
    int? root,
    int? parent,
    List<Map<dynamic, dynamic>>? pictures,
  }) async {
    if (message == '') {
      return {'status': false, 'data': [], 'msg': '请输入评论内容'};
    }
    var params = <String, dynamic>{
      'plat': 1,
      'oid': oid,
      'type': type.index,
      'root': root == null || root == 0 ? '' : root,
      'parent': parent == null || parent == 0 ? '' : parent,
      'message': message,
      'at_name_to_mid': {},
      if (pictures != null) 'pictures': jsonEncode(pictures),
      'gaia_source': 'main_web',
      'csrf': await Request.getCsrf(),
    };
    Map sign = await WbiSign().makSign(params);
    params.remove('wts');
    params.remove('w_rid');
    FormData formData = FormData.fromMap({...params});
    var res = await Request().post(
      Api.replyAdd,
      queryParameters: {
        'w_rid': sign['w_rid'],
        'wts': sign['wts'],
      },
      data: formData,
    );
    if (res.data['code'] == 0) {
      log(res.toString());
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false, 'data': [], 'msg': res.data['message']};
    }
  }

  // 查询是否关注up
  static Future hasFollow({required int mid}) async {
    var res = await Request().get(Api.hasFollow, data: {'fid': mid});
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false, 'data': []};
    }
  }

  // 操作用户关系
  static Future relationMod(
      {required int mid, required int act, required int reSrc}) async {
    var res = await Request().post(
      Api.relationMod,
      data: {
        'fid': mid,
        'act': act,
        're_src': reSrc,
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      if (act == 5) {
        List<int> blackMidsList =
            setting.get(SettingBoxKey.blackMidsList, defaultValue: [-1]);
        blackMidsList.add(mid);
        setting.put(SettingBoxKey.blackMidsList, blackMidsList);
      }
      return {'status': true, 'data': res.data['data'], 'msg': '成功'};
    } else {
      return {'status': false, 'data': [], 'msg': res.data['message']};
    }
  }

  // 视频播放进度
  static Future heartBeat({bvid, cid, progress, realtime}) async {
    await Request().post(
      Api.heartBeat,
      data: {
        // 'aid': aid,
        'bvid': bvid,
        'cid': cid,
        // 'epid': '',
        // 'sid': '',
        // 'mid': '',
        'played_time': progress,
        // 'realtime': realtime,
        // 'type': '',
        // 'sub_type': '',
        'csrf': await Request.getCsrf(),
      },
    );
  }

  // 添加追番
  static Future bangumiAdd({int? seasonId}) async {
    var res = await Request().post(
      Api.bangumiAdd,
      data: {
        'season_id': seasonId,
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'msg': res.data['result']['toast']};
    } else {
      return {'status': false, 'msg': res.data['result']['toast']};
    }
  }

  // 取消追番
  static Future bangumiDel({int? seasonId}) async {
    var res = await Request().post(
      Api.bangumiDel,
      data: {
        'season_id': seasonId,
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'msg': res.data['result']['toast']};
    } else {
      return {'status': false, 'msg': res.data['result']['toast']};
    }
  }

  // 查看视频同时在看人数
  static Future onlineTotal({int? aid, String? bvid, int? cid}) async {
    var res = await Request().get(Api.onlineTotal, data: {
      'aid': aid,
      'bvid': bvid,
      'cid': cid,
    });
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false, 'data': null, 'msg': res.data['message']};
    }
  }

  static Future aiConclusion({
    String? bvid,
    int? cid,
    int? upMid,
  }) async {
    Map params = await WbiSign().makSign({
      'bvid': bvid,
      'cid': cid,
      'up_mid': upMid,
    });
    var res = await Request().get(Api.aiConclusion, data: params);
    if (res.data['code'] == 0 && res.data['data']['code'] == 0) {
      return {
        'status': true,
        'data': AiConclusionModel.fromJson(res.data['data']),
      };
    } else {
      return {'status': false, 'data': []};
    }
  }

  static Future getSubtitle({int? cid, String? bvid, String? aid}) async {
    var res = await Request().get(Api.getSubtitleConfig, data: {
      'cid': cid,
      if (bvid != null) 'bvid': bvid,
      if (aid != null) 'aid': aid,
    });
    try {
      if (res.data['code'] == 0) {
        return {
          'status': true,
          'data': SubTitlteModel.fromJson(res.data['data']),
        };
      } else {
        return {'status': false, 'data': [], 'msg': res.data['msg']};
      }
    } catch (err) {
      return {'status': false, 'data': [], 'msg': res.data['msg']};
    }
  }

  // 视频排行
  static Future getRankVideoList(int rid) async {
    try {
      var rankApi = "${Api.getRankApi}?rid=$rid&type=all";
      var res = await Request().get(rankApi);
      if (res.data['code'] == 0) {
        List<HotVideoItemModel> list = [];
        List<int> blackMidsList =
            setting.get(SettingBoxKey.blackMidsList, defaultValue: [-1]);
        for (var i in res.data['data']['list']) {
          if (!blackMidsList.contains(i['owner']['mid'])) {
            list.add(HotVideoItemModel.fromJson(i));
          }
        }
        return {'status': true, 'data': list};
      } else {
        return {'status': false, 'data': [], 'msg': res.data['message']};
      }
    } catch (err) {
      return {'status': false, 'data': [], 'msg': err};
    }
  }

  // 获取字幕内容
  static Future<Map<String, dynamic>> getSubtitleContent(url) async {
    var res = await Request().get('https:$url');
    final String content =
        await SubTitleUtils.convertToWebVTT(res.data['body']);
    final List body = res.data['body'];
    return {'content': content, 'body': body};
  }

  static Future<Map<String, dynamic>> getSubscribeStatus(
      {required dynamic bvid}) async {
    var res = await Request().get(
      Api.videoRelation,
      data: {
        'aid': IdUtils.bv2av(bvid),
        'bvid': bvid,
      },
    );
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': res.data['data'],
      };
    } else {
      return {
        'status': false,
        'msg': res.data['message'],
      };
    }
  }

  static Future seasonFav({
    required bool isFav,
    required dynamic seasonId,
  }) async {
    var res = await Request().post(
      isFav ? Api.cancelSub : Api.confirmSub,
      data: {
        'platform': 'web',
        'season_id': seasonId,
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      return {
        'status': true,
      };
    } else {
      return {
        'status': false,
        'msg': res.data['message'],
      };
    }
  }

  // 获取视频标签
  static Future getVideoTag({required String bvid}) async {
    var res = await Request().get(Api.videoTag, data: {'bvid': bvid});
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': res.data['data'].map<VideoTagItem>((e) {
          return VideoTagItem.fromJson(e);
        }).toList()
      };
    } else {
      return {'status': false, 'data': [], 'msg': res.data['message']};
    }
  }
}
