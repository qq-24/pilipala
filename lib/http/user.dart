import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:pilipala/models/video/later.dart';
import '../models/model_hot_video_item.dart';
import '../models/user/fav_detail.dart';
import '../models/user/fav_folder.dart';
import '../models/user/history.dart';
import '../models/user/info.dart';
import '../models/user/stat.dart';
import '../models/user/sub_detail.dart';
import '../models/user/sub_folder.dart';
import 'api.dart';
import 'constants.dart';
import 'init.dart';

class UserHttp {
  static Future<dynamic> userStat({required int mid}) async {
    var res = await Request().get(Api.userStat, data: {'vmid': mid});
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false};
    }
  }

  static Future<dynamic> userInfo() async {
    var res = await Request().get(Api.userInfo);
    if (res.data['code'] == 0) {
      UserInfoData data = UserInfoData.fromJson(res.data['data']);
      return {'status': true, 'data': data};
    } else {
      return {'status': false, 'msg': res.data['message']};
    }
  }

  // 登录态自检：逐一探测受登录影响的接口，回报B站原始错误码
  static Future<List<Map<String, String>>> loginSelfCheck() async {
    final results = <Map<String, String>>[];
    Future<void> probe(String name, String url,
        [Map<String, dynamic>? data]) async {
      try {
        var res = await Request().get(url, data: data);
        final body = res.data;
        if (body is Map) {
          results.add({
            'name': name,
            'code': '${body['code']}',
            'msg': '${body['message'] ?? ''}',
          });
        } else {
          results.add({'name': name, 'code': 'E', 'msg': '非JSON响应'});
        }
      } catch (e) {
        results.add({'name': name, 'code': 'X', 'msg': '$e'});
      }
    }

    // 1. 登录探活
    dynamic mid;
    bool isLogin = false;
    try {
      var res = await Request().get(Api.userInfo);
      if (res.data is Map) {
        isLogin = res.data['data']?['isLogin'] == true;
        mid = res.data['data']?['mid'];
        results.add({
          'name': 'nav 登录探活',
          'code': '${res.data['code']}',
          'msg': 'isLogin=$isLogin mid=${mid ?? '-'}',
        });
      } else {
        results.add({'name': 'nav 登录探活', 'code': 'E', 'msg': '非JSON响应'});
      }
    } catch (e) {
      results.add({'name': 'nav 登录探活', 'code': 'X', 'msg': '$e'});
    }

    // 2. cookie 存储状态（只报存在性，不打印值）
    try {
      final cookies = await Request.cookieManager.cookieJar
          .loadForRequest(Uri.parse(HttpString.apiBaseUrl));
      bool has(String n) => cookies.any((c) => c.name == n);
      results.add({
        'name': 'Cookie 存储',
        'code': '',
        'msg': 'SESSDATA:${has('SESSDATA') ? '有' : '无'} '
            'bili_jct:${has('bili_jct') ? '有' : '无'} '
            'buvid3:${has('buvid3') ? '有' : '无'}',
      });
    } catch (e) {
      results.add({'name': 'Cookie 存储', 'code': 'X', 'msg': '$e'});
    }

    // 3-5. 受登录影响的数据接口（用原始端点，回报原始code）
    if (mid != null) {
      await probe('收藏夹列表', Api.userFavFolder,
          {'pn': 1, 'ps': 3, 'up_mid': mid});
      await probe
          ('观看历史', '/x/v2/history', {'mid': mid, 'pn': 1, 'ps': 3});
      await probe('动态门户', Api.followUp);
    }
    return results;
  }

  static Future<dynamic> userStatOwner() async {
    var res = await Request().get(Api.userStatOwner);
    if (res.data['code'] == 0) {
      UserStat data = UserStat.fromJson(res.data['data']);
      return {'status': true, 'data': data};
    } else {
      return {'status': false, 'data': [], 'msg': res.data['message']};
    }
  }

  // 收藏夹
  static Future<dynamic> userfavFolder({
    required int pn,
    required int ps,
    required int mid,
  }) async {
    var res = await Request().get(Api.userFavFolder, data: {
      'pn': pn,
      'ps': ps,
      'up_mid': mid,
    });
    if (res.data['code'] == 0) {
      late FavFolderData data;
      if (res.data['data'] != null) {
        data = FavFolderData.fromJson(res.data['data']);
        return {'status': true, 'data': data};
      } else {
        return {'status': false, 'msg': '收藏夹为空'};
      }
    } else {
      return {
        'status': false,
        'data': [],
        'msg': res.data['message'],
        'code': res.data['code'],
      };
    }
  }

  static Future<dynamic> userFavFolderDetail(
      {required int mediaId,
      required int pn,
      required int ps,
      String keyword = '',
      String order = 'mtime',
      int type = 0}) async {
    var res = await Request().get(Api.userFavFolderDetail, data: {
      'media_id': mediaId,
      'pn': pn,
      'ps': ps,
      'keyword': keyword,
      'order': order,
      'type': type,
      'tid': 0,
      'platform': 'web'
    });
    if (res.data['code'] == 0) {
      FavDetailData data = FavDetailData.fromJson(res.data['data']);
      return {'status': true, 'data': data};
    } else {
      return {'status': false, 'data': [], 'msg': res.data['message']};
    }
  }

  // 稍后再看
  static Future<dynamic> seeYouLater() async {
    var res = await Request().get(Api.seeYouLater);
    if (res.data['code'] == 0) {
      if (res.data['data']['count'] == 0) {
        return {
          'status': true,
          'data': {'list': [], 'count': 0}
        };
      }
      List<HotVideoItemModel> list = [];
      for (var i in res.data['data']['list']) {
        list.add(HotVideoItemModel.fromJson(i));
      }
      return {
        'status': true,
        'data': {'list': list, 'count': res.data['data']['count']}
      };
    } else {
      return {
        'status': false,
        'data': [],
        'msg': res.data['message'],
        'code': res.data['code'],
      };
    }
  }

  // 观看历史
  static Future historyList(int? max, int? viewAt) async {
    var res = await Request().get(Api.historyList, data: {
      'type': 'all',
      'ps': 20,
      'max': max ?? 0,
      'view_at': viewAt ?? 0,
    });
    if (res.data['code'] == 0) {
      return {'status': true, 'data': HistoryData.fromJson(res.data['data'])};
    } else {
      return {
        'status': false,
        'data': [],
        'msg': res.data['message'],
        'code': res.data['code'],
      };
    }
  }

  // 暂停观看历史
  static Future pauseHistory(bool switchStatus) async {
    // 暂停switchStatus传true 否则false
    var res = await Request().post(
      Api.pauseHistory,
      data: {
        'switch': switchStatus,
        'jsonp': 'jsonp',
        'csrf': await Request.getCsrf(),
      },
    );
    return res;
  }

  // 观看历史暂停状态
  static Future historyStatus() async {
    var res = await Request().get(Api.historyStatus);
    return res;
  }

  // 清空历史记录
  static Future clearHistory() async {
    var res = await Request().post(
      Api.clearHistory,
      data: {
        'jsonp': 'jsonp',
        'csrf': await Request.getCsrf(),
      },
    );
    return res;
  }

  // 稍后再看
  static Future toViewLater({String? bvid, dynamic aid}) async {
    var data = {'csrf': await Request.getCsrf()};
    if (bvid != null) {
      data['bvid'] = bvid;
    } else if (aid != null) {
      data['aid'] = aid;
    }
    var res = await Request().post(
      Api.toViewLater,
      data: data,
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'msg': 'yeah！稍后再看'};
    } else {
      return {'status': false, 'msg': res.data['message']};
    }
  }

  // 移除已观看
  static Future toViewDel({int? aid}) async {
    final Map<String, dynamic> params = {
      'jsonp': 'jsonp',
      'csrf': await Request.getCsrf(),
    };

    params[aid != null ? 'aid' : 'viewed'] = aid ?? true;
    var res = await Request().post(
      Api.toViewDel,
      data: params,
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'msg': 'yeah！成功移除'};
    } else {
      return {'status': false, 'msg': res.data['message']};
    }
  }

  // 清空稍后再看
  static Future toViewClear() async {
    var res = await Request().post(
      Api.toViewClear,
      data: {
        'jsonp': 'jsonp',
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'msg': '操作完成'};
    } else {
      return {'status': false, 'msg': res.data['message']};
    }
  }

  // 删除历史记录
  static Future delHistory(kid) async {
    var res = await Request().post(
      Api.delHistory,
      data: {
        'kid': kid,
        'jsonp': 'jsonp',
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'msg': '已删除'};
    } else {
      return {'status': false, 'msg': res.data['message']};
    }
  }

  static Future hasFollow(int mid) async {
    var res = await Request().get(
      Api.hasFollow,
      data: {
        'fid': mid,
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false, 'msg': res.data['message']};
    }
  }

  // 搜索历史记录
  static Future searchHistory(
      {required int pn, required String keyword}) async {
    var res = await Request().get(
      Api.searchHistory,
      data: {
        'pn': pn,
        'keyword': keyword,
        'business': 'all',
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'data': HistoryData.fromJson(res.data['data'])};
    } else {
      return {'status': false, 'msg': res.data['message']};
    }
  }

  // 我的订阅
  static Future userSubFolder({
    required int mid,
    required int pn,
    required int ps,
  }) async {
    var res = await Request().get(Api.userSubFolder, data: {
      'up_mid': mid,
      'ps': ps,
      'pn': pn,
      'platform': 'web',
    });
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': SubFolderModelData.fromJson(res.data['data'])
      };
    } else {
      return {
        'status': false,
        'data': [],
        'msg': res.data['message'],
        'code': res.data['code'],
      };
    }
  }

  static Future userSeasonList({
    required int seasonId,
    required int pn,
    required int ps,
  }) async {
    var res = await Request().get(Api.userSeasonList, data: {
      'season_id': seasonId,
      'ps': ps,
      'pn': pn,
    });
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': SubDetailModelData.fromJson(res.data['data'])
      };
    } else {
      return {'status': false, 'msg': res.data['message']};
    }
  }

  static Future userResourceList({
    required int seasonId,
    required int pn,
    required int ps,
  }) async {
    var res = await Request().get(Api.userResourceList, data: {
      'media_id': seasonId,
      'ps': ps,
      'pn': pn,
      'keyword': '',
      'order': 'mtime',
      'type': 0,
      'tid': 0,
      'platform': 'web',
    });
    if (res.data['code'] == 0) {
      try {
        return {
          'status': true,
          'data': SubDetailModelData.fromJson(res.data['data'])
        };
      } catch (err) {
        return {'status': false, 'msg': err};
      }
    } else {
      return {'status': false, 'msg': res.data['message']};
    }
  }

  // 取消订阅
  static Future cancelSub({required int seasonId}) async {
    var res = await Request().post(
      Api.cancelSub,
      data: {
        'platform': 'web',
        'season_id': seasonId,
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true};
    } else {
      return {'status': false, 'msg': res.data['message']};
    }
  }

  // 删除文件夹
  static Future delFavFolder({required int mediaIds}) async {
    var res = await Request().post(
      Api.delFavFolder,
      data: {
        'media_ids': mediaIds,
        'platform': 'web',
        'csrf': await Request.getCsrf(),
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true};
    } else {
      return {'status': false, 'msg': res.data['message']};
    }
  }

  static List<String> extractScriptContents(String htmlContent) {
    RegExp scriptRegExp = RegExp(r'<script>([\s\S]*?)<\/script>');
    Iterable<Match> matches = scriptRegExp.allMatches(htmlContent);
    List<String> scriptContents = [];
    for (Match match in matches) {
      String scriptContent = match.group(1)!;
      scriptContents.add(scriptContent);
    }
    return scriptContents;
  }

  // 稍后再看列表
  static Future getMediaList({
    required int type,
    required int bizId,
    required int ps,
    int? oid,
  }) async {
    var res = await Request().get(
      Api.mediaList,
      data: {
        'mobi_app': 'web',
        'type': type,
        'biz_id': bizId,
        'oid': oid ?? '',
        'otype': 2,
        'ps': ps,
        'direction': false,
        'desc': true,
        'sort_field': 1,
        'tid': 0,
        'with_current': false,
      },
    );
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': res.data['data']['media_list'] != null
            ? res.data['data']['media_list']
                .map<MediaVideoItemModel>(
                    (e) => MediaVideoItemModel.fromJson(e))
                .toList()
            : []
      };
    } else {
      return {'status': false, 'msg': res.data['message']};
    }
  }

  // 解析收藏夹视频
  static Future parseFavVideo({
    required int mediaId,
    required int oid,
    required String bvid,
  }) async {
    var res = await Request().get(
      'https://www.bilibili.com/list/ml$mediaId',
      data: {
        'oid': mediaId,
        'bvid': bvid,
      },
    );
    String scriptContent =
        extractScriptContents(parse(res.data).body!.outerHtml)[0];
    int startIndex = scriptContent.indexOf('{');
    int endIndex = scriptContent.lastIndexOf('};');
    String jsonContent = scriptContent.substring(startIndex, endIndex + 1);
    // 解析JSON字符串为Map
    Map<String, dynamic> jsonData = json.decode(jsonContent);
    return {
      'status': true,
      'data': jsonData['resourceList']
          .map<MediaVideoItemModel>((e) => MediaVideoItemModel.fromJson(e))
          .toList()
    };
  }

  static Future getAccountInfo() async {
    var res = await Request().get(
      Api.accountInfo,
      data: {'web_location': 333.33},
    );
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': res.data['data'],
      };
    } else {
      return {
        'status': false,
        'data': {},
        'mag': res.data['message'],
      };
    }
  }

  static Future updateAccountInfo({
    required String uname,
    required String sign,
    required String sex,
    required String birthday,
  }) async {
    var res = await Request().post(
      Api.updateAccountInfo,
      data: {
        'uname': uname,
        'usersign': sign,
        'sex': sex,
        'birthday': birthday,
        'csrf': await Request.getCsrf(),
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'msg': '更新成功',
      };
    } else {
      return {
        'status': false,
        'msg': res.data['message'],
      };
    }
  }

  // 解析up投稿
  static Future parseUpArchiveVideo({
    required int mid,
    required int oid,
    required String bvid,
    String sortField = 'pubtime',
  }) async {
    var res = await Request().get(
      'https://www.bilibili.com/list/$mid',
      data: {
        'oid': oid,
        'bvid': bvid,
        'sort_field': sortField,
      },
    );
    String scriptContent =
        extractScriptContents(parse(res.data).body!.outerHtml)[0];
    int startIndex = scriptContent.indexOf('{');
    int endIndex = scriptContent.lastIndexOf('};');
    String jsonContent = scriptContent.substring(startIndex, endIndex + 1);
    // 解析JSON字符串为Map
    Map<String, dynamic> jsonData = json.decode(jsonContent);
    return {
      'status': true,
      'data': jsonData['resourceList']
          .map<MediaVideoItemModel>((e) => MediaVideoItemModel.fromJson(e))
          .toList()
    };
  }
}
