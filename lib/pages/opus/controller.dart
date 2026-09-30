import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/http/dynamics.dart';
import 'package:pilipala/http/read.dart';
import 'package:pilipala/models/read/opus.dart';
import 'package:pilipala/plugin/pl_gallery/hero_dialog_route.dart';
import 'package:pilipala/plugin/pl_gallery/interactiveviewer_gallery.dart';
import 'package:pilipala/utils/diag_log.dart';

class OpusController extends GetxController {
  late String url;
  RxString title = ''.obs;
  late String id;
  late String articleType;
  Rx<OpusDataModel> opusData = OpusDataModel().obs;
  final ScrollController scrollController = ScrollController();
  late StreamController<bool> appbarStream = StreamController<bool>.broadcast();

  @override
  void onInit() {
    super.onInit();
    title.value = Get.parameters['title'] ?? '';
    id = Get.parameters['id']!;
    articleType = Get.parameters['articleType']!;
    if (articleType == 'opus') {
      url = 'https://www.bilibili.com/opus/$id';
    }
    scrollController.addListener(_scrollListener);
  }

  Future fetchOpusData() async {
    // 先走 JSON 接口。抓 PC 网页那条路一旦被风控挡，返回的是验证码壳页，
    // 壳页 body 里没有承载数据的 <script>，旧代码在此处抛异常并把整页变成空白。
    final int? opusId = int.tryParse(id);
    if (opusId != null) {
      try {
        final res = await DynamicsHttp.opusDetail(opusId: opusId);
        if (res['status'] == true && res['data'] is Map) {
          final Map<String, dynamic> data =
              Map<String, dynamic>.from(res['data'] as Map);
          final Map<String, dynamic>? item =
              data['item'] is Map ? Map<String, dynamic>.from(data['item'] as Map) : null;
          final List? modules = item?['modules'] is List ? item!['modules'] as List : null;
          if (modules != null && modules.isNotEmpty) {
            final OpusDataModel model =
                OpusDataModel.fromJson({'id': id, 'detail': item});
            opusData.value = model;
            final String? fetched = model.detail?.basic?.title;
            if (fetched != null && fetched.isNotEmpty) {
              title.value = fetched;
            }
            DiagLog.write('[OPUS] api ok id=$id modules=${modules.length}');
            return {'status': true, 'data': model, 'msg': ''};
          }
          DiagLog.write(
              '[OPUS] api no modules, fallback html id=$id keys=${data.keys.toList()}');
        } else {
          DiagLog.write('[OPUS] api failed id=$id msg=${res['msg']}');
        }
      } catch (err) {
        DiagLog.write('[OPUS] api error id=$id $err');
      }
    }
    var res = await ReadHttp.parseArticleOpus(id: id);
    if (res['status']) {
      List<String> keys = res.keys.toList();
      if (keys.contains('isCv') && res['isCv']) {
        Get.offNamed('/read', parameters: {
          'id': '${res['cvId'] ?? ''}',
          'title': title.value,
          'articleType': 'cv',
        });
      } else {
        title.value = res['data'].detail?.basic?.title ?? title.value;
        opusData.value = res['data'];
      }
    } else {
      DiagLog.write('[OPUS] html failed id=$id msg=${res['msg']}');
    }
    return res;
  }

  void _scrollListener() {
    final double offset = scrollController.position.pixels;
    if (offset > 100) {
      appbarStream.add(true);
    } else {
      appbarStream.add(false);
    }
  }

  void onPreviewImg(picList, initIndex, context) {
    Navigator.of(context).push(
      HeroDialogRoute<void>(
        builder: (BuildContext context) => InteractiveviewerGallery(
          sources: picList,
          initIndex: initIndex,
          onPageChanged: (int pageIndex) {},
        ),
      ),
    );
  }

  // 跳转webview
  void onJumpWebview() {
    Get.toNamed('/webview', parameters: {
      'url': url,
      'type': 'webview',
      'pageTitle': title.value,
    });
  }

  @override
  void onClose() {
    scrollController.removeListener(_scrollListener);
    appbarStream.close();
    super.onClose();
  }
}
