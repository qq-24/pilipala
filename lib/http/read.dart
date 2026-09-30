import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:pilipala/models/read/opus.dart';
import 'package:pilipala/models/read/read.dart';
import 'package:pilipala/utils/wbi_sign.dart';
import 'index.dart';

class ReadHttp {
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

  // 解析专栏 opus格式
  static Future parseArticleOpus({required String id}) async {
    try {
      return await _parseArticleOpus(id);
    } catch (err) {
      return {'status': false, 'data': [], 'msg': '抓取失败: $err'};
    }
  }

  static Future _parseArticleOpus(String id) async {
    var res = await Request().get('https://www.bilibili.com/opus/$id', extra: {
      'ua': 'pc',
    });
    final String html = res.data is String ? res.data as String : '';
    String? headContent = parse(html).head?.outerHtml;
    var document = parse(headContent);
    var linkTags = document.getElementsByTagName('link');
    bool isCv = false;
    String cvId = '';
    for (var linkTag in linkTags) {
      var attributes = linkTag.attributes;
      if (attributes.containsKey('rel') &&
          attributes['rel'] == 'canonical' &&
          attributes.containsKey('data-vue-meta') &&
          attributes['data-vue-meta'] == 'true') {
        final String cvHref = linkTag.attributes['href']!;
        RegExp regex = RegExp(r'cv(\d+)');
        RegExpMatch? match = regex.firstMatch(cvHref);
        if (match != null) {
          cvId = match.group(1)!;
        } else {
          print('No match found.');
        }
        isCv = true;
        break;
      }
    }
    final List<String> scriptContents =
        extractScriptContents(parse(html).body?.outerHtml ?? '');
    // 被风控挡下来时拿到的是验证码壳页，正文里根本没有承载数据的 script 标签，
    // 旧代码在这里 [0] 取值会抛 RangeError，页面就只剩一个标题
    if (scriptContents.isEmpty) {
      return {
        'status': false,
        'data': [],
        'msg': (html.contains('验证码') || html.contains('_riskdata_'))
            ? '被B站风控拦了（返回验证码页），稍后再试或查看原网页'
            : '页面结构变了，没找到正文数据',
      };
    }
    final String scriptContent = scriptContents.first;
    int startIndex = scriptContent.indexOf('{');
    int endIndex = scriptContent.lastIndexOf('};');
    if (startIndex < 0 || endIndex <= startIndex) {
      return {'status': false, 'data': [], 'msg': '没找到正文数据块'};
    }
    Map<String, dynamic> jsonData;
    try {
      jsonData = json
          .decode(scriptContent.substring(startIndex, endIndex + 1))
          as Map<String, dynamic>;
    } catch (err) {
      return {'status': false, 'data': [], 'msg': '正文数据解析失败: $err'};
    }
    if (jsonData['detail'] == null) {
      return {'status': false, 'data': [], 'msg': '这条内容没有详情数据'};
    }
    return {
      'status': true,
      'data': OpusDataModel.fromJson(jsonData),
      'isCv': isCv,
      'cvId': cvId,
    };
  }

  // 解析专栏 cv格式
  static Future parseArticleCv({required String id}) async {
    var res = await Request().get(
      'https://www.bilibili.com/read/cv$id',
      extra: {'ua': 'pc'},
      options: Options(
        headers: {
          'cookie': 'opus-goback=1',
        },
      ),
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
      'data': ReadDataModel.fromJson(jsonData),
    };
  }

  //
  static Future getViewInfo({required String id}) async {
    Map params = await WbiSign().makSign({
      'id': id,
      'mobi_app': 'pc',
      'from': 'web',
      'gaia_source': 'main_web',
      'web_location': 333.976,
    });
    var res = await Request().get(
      Api.getViewInfo,
      data: {
        'id': id,
        'mobi_app': 'pc',
        'from': 'web',
        'gaia_source': 'main_web',
        'web_location': 333.976,
        'w_rid': params['w_rid'],
        'wts': params['wts'],
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
        'data': [],
        'msg': res.data['message'],
      };
    }
  }
}
