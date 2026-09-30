import 'dart:convert';
import 'dart:developer';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response, FormData;
import 'recommendation_request.dart';
import '../utils/recommendation_state.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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

  static String? _deviceModel;
  static Future<Map<String, dynamic>> rcmdVideoListApp(
      {bool loginStatus = true,
      int idx = 0,
      bool pull = true,
      int flush = 0,
      CancelToken? cancelToken}) async {
    final key = loginStatus
        ? '${localCache.get(LocalCacheKey.accessKey, defaultValue: {})['value'] ?? ''}'
        : '';
    final account = loginStatus ? '${userInfoCache.get('userInfoCache')?.mid ?? ''}' : null;
    if (loginStatus && key.isEmpty)
      return {
        'status': false,
        'data': [],
        'msg': '缺少 App token，请刷新 access_key'
      };
    try {
      _deviceModel ??= (await DeviceInfoPlugin().androidInfo).model;
    } catch (_) {
      _deviceModel ??= 'android';
    }
    final context = Get.context;
    final pad =
        context != null && MediaQuery.sizeOf(context).shortestSide >= 600;
    final params = appFeedParams(
        idx: idx,
        pull: pull,
        flush: flush,
        key: key,
        device: pad ? 'pad' : 'phone',
        model: _deviceModel!);
    try {
      final network = await Connectivity().checkConnectivity();
      params['network'] = network.contains(ConnectivityResult.wifi) ? 'wifi' : network.contains(ConnectivityResult.mobile) ? 'mobile' : '';
    } catch (_) { params['network'] = ''; }
    params['appkey'] = Constants.appKey;
    params['ts'] = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    params['sign'] = Utils.appSign(
        Map<String, dynamic>.from(params), Constants.appKey, Constants.appSec);
    Dio? guest;
    try {
      final buvid = await Request.getBuvid();
      final headers = <String, dynamic>{if (buvid.isNotEmpty) 'buvid': buvid};
      final Response res;
      if (loginStatus) {
        res = await Request().get(Api.recommendListApp,
            data: params,
            options: Options(headers: headers),
            cancelToken: cancelToken);
      } else {
        // A true guest must not inherit the singleton client's login cookies.
        guest = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 12)));
        res = await guest.get(Api.recommendListApp,
            queryParameters: params,
            options: Options(headers: headers),
            cancelToken: cancelToken);
      }
      final body = res.data;
      if (body is! Map || body['code'] != 0)
        return {
          'status': false,
          'data': [],
          'msg': body is Map ? body['message'] ?? '请求失败' : '接口返回异常'
        };
      final meta = appFeedMeta(body);
      final black =
          setting.get(SettingBoxKey.blackMidsList, defaultValue: [-1]) as List;
      final dynamics =
          setting.get(SettingBoxKey.enableRcmdDynamic, defaultValue: true);
      final list = <RecVideoItemAppModel>[];
      int parseErrors = 0;
      for (final value in (body['data']?['items'] ?? [])) {
        if (value is! Map) continue;
        final item = Map<String, dynamic>.from(value);
        final goto = item['goto'] ?? item['card_goto'];
        final cardGoto = '${item['card_goto'] ?? ''}';
        if (!['av', 'bangumi', 'picture'].contains(goto) ||
            cardGoto.startsWith('ad_') ||
            item['ad_info'] != null ||
            (!dynamics && goto == 'picture') ||
            black.contains(
                feedInt(item['args']?['up_id'] ?? item['args']?['up_mid'])))
          continue;
        try {
          final model = RecVideoItemAppModel.fromJson(item);
          model.feedAccount = account;
          if (!RecommendFilter.filter(model)) list.add(model);
        } catch (_) {
          parseErrors++;
        }
      }
      DiagLog.write(
          '[RCMD] app idx=$idx pull=$pull flush=$flush raw=${meta['rawCount']} filtered=${list.length} parseErrors=$parseErrors pegasus=${meta['pegasusCode']}');
      return {
        'status': true,
        'data': list,
        ...meta,
        'parseErrors': parseErrors
      };
    } catch (e) {
      return {
        'status': false,
        'data': [],
        'cancelled': cancelToken?.isCancelled == true,
        'msg': '推荐请求失败'
      };
    } finally {
      guest?.close(force: true);
    }
  }

  /// Independent token identity verification; recommendation overlap is not an auth test.
  static Future<Map<String, dynamic>> diagnoseAppRcmd() async {
    final key =
        '${localCache.get(LocalCacheKey.accessKey, defaultValue: {})['value'] ?? ''}';
    final user = userInfoCache.get('userInfoCache');
    if (key.isEmpty) return {'status': false, 'msg': '未获取到 access_key'};
    final bare = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12)));
    try {
      final params = <String, dynamic>{
        'access_token': key,
        'appkey': Constants.appKey,
        'ts': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}'
      };
      params['sign'] = Utils.appSign(Map<String, dynamic>.from(params),
          Constants.appKey, Constants.appSec);
      final identity = await bare.get(
          'https://passport.bilibili.com/api/v2/oauth2/info',
          queryParameters: params);
      final body = identity.data;
      final serverMid = body is Map && body['data'] is Map ? feedInt(body['data']['mid']) : null;
      final valid = body is Map && body['code'] == 0 && serverMid != null && serverMid > 0 &&
          '${body['data']?['mid']}' == '${user?.mid}';
      final feed = await rcmdVideoListApp();
      final items = feed['data'] as List;
      final ids = feed['rawIds'] as List? ?? [];
      return {
        'status': true,
        'tokenValid': valid,
        'feedStatus': feed['status'], 'rawCount': feed['rawCount'], 'filteredCount': items.length,
        'msg': '服务器验证 token：${valid ? '有效，且属于当前账号' : '未确认有效，请检查登录'}\n'
            '推荐请求：${feed['status'] == true ? '成功' : '失败'}\n'
            '原始 ${feed['rawCount'] ?? 0} 条，视频 ${ids.length} 个，唯一视频 ${ids.toSet().length} 个；过滤后 ${items.length} 条\n'
            '推荐内部状态：${feed['pegasusCode'] ?? '未返回异常状态'}\n'
            '以上验证账号、接口和重复情况，不证明与官方推荐质量等效。',
        'liveTitles': items.take(6).map((e) => '${e.title}').toList()
      };
    } catch (_) {
      return {'status': false, 'msg': '账号验证请求失败，无法判定'};
    } finally {
      bare.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> feedDislike(
      RecVideoItemAppModel item, int reasonId) async {
    if (item.feedAccount != '${userInfoCache.get('userInfoCache')?.mid ?? ''}')
      return {'status': false, 'msg': '账号已变化，请刷新推荐后重试'};
    final key =
        '${localCache.get(LocalCacheKey.accessKey, defaultValue: {})['value'] ?? ''}';
    if (key.isEmpty) return {'status': false, 'msg': '需要有效的 App token'};
    final params = <String, dynamic>{
      'id': '${item.param ?? item.aid ?? ''}',
      'goto': item.reportFields['goto'],
      'reason_id': '$reasonId',
      'access_key': key,
      'appkey': Constants.appKey,
      'build': '9130500',
      'mobi_app': 'android',
      'track_id': item.trackId ?? '',
      'spmid': 'tm.recommend.0.0',
      if (item.reportFields['report_data'] != null)
        'report_data': item.reportFields['report_data'],
      'ts': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}'
    };
    params['sign'] = Utils.appSign(
        Map<String, dynamic>.from(params), Constants.appKey, Constants.appSec);
    try {
      final res = await Request()
          .get('https://app.bilibili.com/x/feed/dislike', data: params);
      final ok = res.data is Map && res.data['code'] == 0;
      DiagLog.write(
          '[RCMD_FEEDBACK] dislike aid=${item.aid} code=${res.data is Map ? res.data['code'] : 'non-json'}');
      return {'status': ok, 'msg': ok ? '已反馈，将减少相似内容推荐' : '反馈未成功，请稍后重试'};
    } catch (_) {
      return {'status': false, 'msg': '反馈请求失败'};
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
  static Future heartBeat(
      {bvid,
      cid,
      progress,
      realtime,
      Map<String, String>? recommendationContext}) async {
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
        if (recommendationContext != null) ...{
          'from_spmid': recommendationContext['from_spmid'],
          'spmid': '333.788.0.0',
          'trackid': recommendationContext['track_id'],
        },
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
