import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:pilipala/utils/feed_back.dart';
import 'package:pilipala/utils/image_save.dart';
import 'package:pilipala/utils/route_push.dart';
import '../../models/model_rec_video_item.dart';
import 'drag_handle.dart';
import 'stat/danmu.dart';
import 'stat/view.dart';
import '../../http/dynamics.dart';
import '../../http/user.dart';
import '../../http/video.dart';
import '../../utils/id_utils.dart';
import '../../utils/utils.dart';
import '../../models/home/rcmd/result.dart';
import '../../pages/rcmd/controller.dart';
import '../../utils/app_scheme.dart';
import '../../utils/diag_log.dart';
import '../../utils/recommendation_feedback.dart';
import '../../utils/recommendation_state.dart';
import '../constants.dart';
import 'badge.dart';
import 'network_img_layer.dart';

/// 动态卡片链接的解析结果：opus / read / dynamicDetail / scheme / none
class PictureJump {
  const PictureJump(this.route, {this.parameters = const {}, this.id = ''});
  final String route;
  final Map<String, String> parameters;
  final String id;
}

// 视频卡片 - 垂直布局
class VideoCardV extends StatelessWidget {
  final dynamic videoItem;
  final int crossAxisCount;
  final int? recommendationPosition;
  final Function? blockUserCb;

  const VideoCardV({
    Key? key,
    required this.videoItem,
    required this.crossAxisCount,
    this.recommendationPosition,
    this.blockUserCb,
  }) : super(key: key);

  static bool isStringNumeric(String str) {
    RegExp numericRegex = RegExp(r'^\d+$');
    return numericRegex.hasMatch(str);
  }

  void onPushDetail(heroTag) async {
    String goto = videoItem.goto;
    switch (goto) {
      case 'bangumi':
        if (videoItem.bangumiBadge == '电影') {
          SmartDialog.showToast('暂不支持电影观看');
          return;
        }
        int epId = videoItem.param;
        RoutePush.bangumiPush(
          null,
          epId,
          heroTag: heroTag,
        );
        break;
      case 'av':
        String bvid = videoItem.bvid ?? IdUtils.av2bv(videoItem.aid);
        final appItem = videoItem is RecVideoItemAppModel
            ? videoItem as RecVideoItemAppModel
            : null;
        if (appItem != null && recommendationPosition != null) {
          RecommendationFeedback.instance.add(
              appItem, 'tm.recommend.0.click', recommendationPosition!,
              click: true);
        }
        Get.toNamed('/video?bvid=$bvid&cid=${videoItem.cid}', arguments: {
          // 'videoItem': videoItem,
          'pic': videoItem.pic,
          'heroTag': heroTag,
          if (appItem?.trackId != null && recommendationPosition != null)
            'recommendationContext': {
              'bvid': bvid,
              'track_id': appItem!.trackId!,
              'from_spmid': 'tm.recommend.0.0'
            },
        });
        break;
      // 动态
      case 'picture':
        try {
          await pushPictureDynamic();
        } catch (err) {
          DiagLog.write('[PIC_JUMP-ERR] $err  card=${videoItem.uri}');
          SmartDialog.showToast(err.toString());
        }
        break;
      default:
        SmartDialog.showToast('${videoItem.goto}');
        Get.toNamed(
          '/webview',
          parameters: {
            'url': '${videoItem.uri ?? ''}',
            'type': 'url',
            'pageTitle': '${videoItem.title ?? ''}',
          },
        );
    }
  }

  /// 把卡片链接解析成跳转目标。uri 有 bilibili://opus/detail/x、bilibili://article/x、
  /// https://www.bilibili.com/opus/x、https://t.bilibili.com/x 等形态，而 param 是
  /// int，Get.toNamed 的 parameters 只接受 Map<String, String>。
  static PictureJump resolvePictureJump({
    required String uri,
    required String param,
    String title = '',
  }) {
    if (uri.startsWith('//')) {
      uri = 'https:$uri';
    }
    if (uri.isEmpty) {
      return isStringNumeric(param)
          ? PictureJump('opus',
              parameters: {'title': title, 'id': param, 'articleType': 'opus'})
          : const PictureJump('none');
    }
    final Uri parsed = Uri.parse(uri);
    final List<String> segments =
        parsed.pathSegments.where((String s) => s.isNotEmpty).toList();
    // bilibili:// 的类型在 host 上，http(s):// 的类型在首个路径段上
    final String kind = parsed.scheme == 'bilibili'
        ? parsed.host
        : (segments.isEmpty ? '' : segments.first);
    final List<int> numbers =
        Utils.matchNum(segments.isEmpty ? '' : segments.last);
    final String id = numbers.isEmpty ? '' : '${numbers.first}';
    if (id.isNotEmpty) {
      if (kind == 'opus') {
        return PictureJump('opus',
            parameters: {'title': title, 'id': id, 'articleType': 'opus'});
      }
      if (kind == 'article' || kind == 'read') {
        return PictureJump('read',
            parameters: {'title': title, 'id': id, 'articleType': 'read'});
      }
    }
    if (isStringNumeric(kind)) {
      // https://t.bilibili.com/<动态id>
      return PictureJump('dynamicDetail', id: kind);
    }
    return const PictureJump('scheme');
  }

  Future<void> pushPictureDynamic() async {
    final String uri = '${videoItem.uri ?? ''}';
    final PictureJump jump = resolvePictureJump(
      uri: uri,
      param: '${videoItem.param ?? ''}',
      title: '${videoItem.title ?? ''}',
    );
    DiagLog.write('[PIC_JUMP] ${jump.route} id=${jump.id} uri=$uri');
    switch (jump.route) {
      case 'opus':
        Get.toNamed('/opus', parameters: jump.parameters);
        break;
      case 'read':
        Get.toNamed('/read', parameters: jump.parameters);
        break;
      case 'dynamicDetail':
        final res = await DynamicsHttp.dynamicDetail(id: jump.id);
        if (res['status'] == true) {
          Get.toNamed('/dynamicDetail', arguments: {
            'item': res['data'],
            'floor': 1,
            'action': 'detail',
          });
        } else {
          SmartDialog.showToast('${res['msg']}');
        }
        break;
      case 'none':
        SmartDialog.showToast('动态链接为空');
        break;
      default:
        PiliSchame.routePush(Uri.parse(uri));
    }
  }

  @override
  Widget build(BuildContext context) {
    String heroTag = Utils.makeHeroTag(videoItem.id);
    return InkWell(
      onTap: () async => onPushDetail(heroTag),
      onLongPress: () => imageSaveDialog(
        context,
        videoItem,
        SmartDialog.dismiss,
      ),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: StyleString.aspectRatio,
            child: LayoutBuilder(builder: (context, boxConstraints) {
              double maxWidth = boxConstraints.maxWidth;
              double maxHeight = boxConstraints.maxHeight;
              return Stack(
                children: [
                  Hero(
                    tag: heroTag,
                    child: NetworkImgLayer(
                      src: videoItem.pic,
                      width: maxWidth,
                      height: maxHeight,
                    ),
                  ),
                  if (videoItem.duration > 0)
                    if (crossAxisCount == 1) ...[
                      PBadge(
                        bottom: 10,
                        right: 10,
                        text: Utils.timeFormat(videoItem.duration),
                      )
                    ] else ...[
                      PBadge(
                        bottom: 6,
                        right: 7,
                        size: 'small',
                        type: 'gray',
                        text: Utils.timeFormat(videoItem.duration),
                      )
                    ],
                ],
              );
            }),
          ),
          VideoContent(
            videoItem: videoItem,
            crossAxisCount: crossAxisCount,
            blockUserCb: blockUserCb,
          )
        ],
      ),
    );
  }
}

class VideoContent extends StatelessWidget {
  final dynamic videoItem;
  final int crossAxisCount;
  final Function? blockUserCb;

  const VideoContent({
    Key? key,
    required this.videoItem,
    required this.crossAxisCount,
    this.blockUserCb,
  }) : super(key: key);

  Widget _buildBadge(String text, String type, [double fs = 12]) {
    return PBadge(
      text: text,
      stack: 'normal',
      size: 'small',
      type: type,
      fs: fs,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: crossAxisCount == 1
          ? const EdgeInsets.fromLTRB(9, 9, 9, 4)
          : const EdgeInsets.fromLTRB(5, 8, 5, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            videoItem.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (crossAxisCount > 1) ...[
            const SizedBox(height: 2),
            VideoStat(videoItem: videoItem, crossAxisCount: crossAxisCount),
          ],
          if (crossAxisCount == 1) const SizedBox(height: 4),
          Row(
            children: [
              if (videoItem.goto == 'bangumi')
                _buildBadge(videoItem.bangumiBadge, 'line', 9),
              if (videoItem.rcmdReason != null)
                _buildBadge(videoItem.rcmdReason, 'color'),
              if (videoItem.goto == 'picture') _buildBadge('动态', 'line', 9),
              if (videoItem.isFollowed == 1) _buildBadge('已关注', 'color'),
              Expanded(
                flex: crossAxisCount == 1 ? 0 : 1,
                child: Text(
                  videoItem.owner.name,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              if (crossAxisCount == 1) ...[
                const SizedBox(width: 10),
                VideoStat(
                  videoItem: videoItem,
                  crossAxisCount: crossAxisCount,
                ),
                const Spacer(),
              ],
              if (videoItem.goto == 'av')
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      feedBack();
                      showModalBottomSheet(
                        context: context,
                        useRootNavigator: true,
                        isScrollControlled: true,
                        builder: (context) {
                          return MorePanel(
                            videoItem: videoItem,
                            blockUserCb: blockUserCb,
                          );
                        },
                      );
                    },
                    icon: Icon(
                      Icons.more_vert_outlined,
                      color: Theme.of(context).colorScheme.outline,
                      size: 14,
                    ),
                  ),
                )
            ],
          ),
        ],
      ),
    );
  }
}

class VideoStat extends StatelessWidget {
  final dynamic videoItem;
  final int crossAxisCount;

  const VideoStat({
    Key? key,
    required this.videoItem,
    required this.crossAxisCount,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (videoItem.stat.view != null) StatView(view: videoItem.stat.view),
        const SizedBox(width: 8),
        if (videoItem.stat.danmu != null)
          StatDanMu(danmu: videoItem.stat.danmu),
        if (videoItem is RecVideoItemModel) ...<Widget>[
          crossAxisCount > 1 ? const Spacer() : const SizedBox(width: 8),
          RichText(
            maxLines: 1,
            text: TextSpan(
                style: TextStyle(
                  fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                  color: Theme.of(context).colorScheme.outline,
                ),
                text: Utils.formatTimestampToRelativeTime(videoItem.pubdate)),
          ),
          const SizedBox(width: 4),
        ]
      ],
    );
  }
}

class MorePanel extends StatelessWidget {
  final dynamic videoItem;
  final Function? blockUserCb;
  const MorePanel({
    super.key,
    required this.videoItem,
    this.blockUserCb,
  });

  Future<dynamic> menuActionHandler(String type) async {
    switch (type) {
      case 'block':
        Get.back();
        blockUser();
        break;
      case 'watchLater':
        var res = await UserHttp.toViewLater(bvid: videoItem.bvid as String);
        SmartDialog.showToast(res['msg']);
        Get.back();
        break;
      default:
    }
  }

  Future<void> showDislike(BuildContext context) async {
    final item = videoItem as RecVideoItemAppModel;
    Navigator.of(context).pop();
    final root = Get.context;
    if (root == null) return;
    final reason = await showModalBottomSheet<int>(
        context: root,
        builder: (context) => SafeArea(
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ListTile(title: Text('不感兴趣')),
              for (final entry in item.dislikeReasons)
                if ((feedInt(entry['id']) ?? 0) > 0)
                  ListTile(
                      title: Text('${entry['name'] ?? '这个内容'}'),
                      onTap: () =>
                          Navigator.of(context).pop(feedInt(entry['id']))),
            ]))));
    if (reason == null) return;
    SmartDialog.showLoading(msg: '提交反馈…');
    try {
      final result = await VideoHttp.feedDislike(item, reason);
      if (result['status'] == true && Get.isRegistered<RcmdController>()) {
        Get.find<RcmdController>().removeFeedbackItem(item);
      }
      SmartDialog.showToast(result['msg']);
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  void blockUser() async {
    SmartDialog.show(
      useSystem: true,
      animationType: SmartAnimationType.centerFade_otherSlide,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('提示'),
          content: Text('确定拉黑:${videoItem.owner.name}(${videoItem.owner.mid})?'
              '\n\n注：被拉黑的Up可以在隐私设置-黑名单管理中解除'),
          actions: [
            TextButton(
              onPressed: () => SmartDialog.dismiss(),
              child: Text(
                '点错了',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () async {
                var res = await VideoHttp.relationMod(
                  mid: videoItem.owner.mid,
                  act: 5,
                  reSrc: 11,
                );
                SmartDialog.dismiss();
                if (res['status']) {
                  blockUserCb?.call(videoItem.owner.mid);
                }
                SmartDialog.showToast(res['msg']);
              },
              child: const Text('确认'),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          if (videoItem is RecVideoItemAppModel &&
              (videoItem as RecVideoItemAppModel).dislikeReasons.isNotEmpty)
            ListTile(
                onTap: () => showDislike(context),
                minLeadingWidth: 0,
                leading: const Icon(Icons.not_interested, size: 19),
                title: Text('不感兴趣',
                    style: Theme.of(context).textTheme.titleSmall)),
          ListTile(
            onTap: () async => await menuActionHandler('block'),
            minLeadingWidth: 0,
            leading: const Icon(Icons.block, size: 19),
            title: Text(
              '拉黑up主 「${videoItem.owner.name}」',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ListTile(
            onTap: () async => await menuActionHandler('watchLater'),
            minLeadingWidth: 0,
            leading: const Icon(Icons.watch_later_outlined, size: 19),
            title:
                Text('添加至稍后再看', style: Theme.of(context).textTheme.titleSmall),
          ),
          ListTile(
            onTap: () =>
                imageSaveDialog(context, videoItem, SmartDialog.dismiss),
            minLeadingWidth: 0,
            leading: const Icon(Icons.photo_outlined, size: 19),
            title:
                Text('查看视频封面', style: Theme.of(context).textTheme.titleSmall),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
