// 操作栏
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:pilipala/http/dynamics.dart';
import 'package:pilipala/models/dynamics/result.dart';
import 'package:pilipala/pages/dynamics/index.dart';
import 'package:pilipala/utils/feed_back.dart';
import 'package:status_bar_control/status_bar_control.dart';
import '../forward/index.dart';

class ActionPanel extends StatefulWidget {
  const ActionPanel({
    super.key,
    required this.item,
    this.onComment,
  });

  final DynamicItemModel item;

  /// 详情页里"评论"不该再压一层详情页，传了这个回调就改成滚动到评论区
  final VoidCallback? onComment;

  @override
  State<ActionPanel> createState() => _ActionPanelState();
}

class _ActionPanelState extends State<ActionPanel>
    with TickerProviderStateMixin {
  final DynamicsController _dynamicsController = Get.put(DynamicsController());
  ModuleStatModel? stat;
  bool isProcessing = false;
  double defaultHeight = 260;
  RxDouble height = 0.0.obs;
  RxBool isExpand = false.obs;
  late double statusHeight;

  void Function()? handleState(Future Function() action) {
    return isProcessing
        ? null
        : () async {
            isProcessing = true;
            await action();
            isProcessing = false;
          };
  }

  @override
  void initState() {
    super.initState();
    stat = widget.item.modules?.moduleStat;
    onInit();
  }

  onInit() async {
    statusHeight = await StatusBarControl.getHeight;
  }

  // 动态点赞
  Future onLikeDynamic() async {
    feedBack();
    var item = widget.item;
    String? dynamicId = item.idStr;
    // 1 已点赞 2 不喜欢 0 未操作
    Like? like = item.modules?.moduleStat?.like;
    if (dynamicId == null || like == null || like.status == null) {
      SmartDialog.showToast('这条动态暂时不能点赞');
      return;
    }
    // count 有时是"点赞"这种文案而不是数字
    int count = int.tryParse(like.count ?? '') ?? 0;
    bool status = like.status!;
    int up = status ? 2 : 1;
    var res = await DynamicsHttp.likeDynamic(dynamicId: dynamicId, up: up);
    if (res['status']) {
      SmartDialog.showToast(!status ? '点赞成功' : '取消赞');
      if (up == 1) {
        like.count = (count + 1).toString();
        like.status = true;
      } else {
        like.count = count == 1 ? '点赞' : (count - 1).toString();
        like.status = false;
      }
      setState(() {});
    } else {
      SmartDialog.showToast(res['msg']);
    }
  }

  // 动态转发
  void forwardHandler() async {
    final userInfo = _dynamicsController.userInfo;
    if (userInfo?.mid == null) {
      SmartDialog.showToast('请先登录');
      return;
    }
    int mid = userInfo!.mid!;
    showModalBottomSheet(
      context: context,
      enableDrag: true,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return DynamicForwardPage(
          item: widget.item,
          mid: mid,
          cb: () => setState(() {
            final int count = int.tryParse(stat?.forward?.count ?? '') ?? 0;
            stat?.forward?.count = (count + 1).toString();
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var color = Theme.of(context).colorScheme.outline;
    var primary = Theme.of(context).colorScheme.primary;
    height.value = defaultHeight;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Expanded(
          flex: 1,
          child: TextButton.icon(
            onPressed: forwardHandler,
            icon: const Icon(
              FontAwesomeIcons.shareFromSquare,
              size: 16,
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 0),
              foregroundColor: Theme.of(context).colorScheme.outline,
            ),
            label: Text(stat?.forward?.count ?? '转发'),
          ),
        ),
        Expanded(
          flex: 1,
          child: TextButton.icon(
            onPressed: () => widget.onComment != null
                ? widget.onComment!()
                : _dynamicsController.pushDetail(widget.item, 1,
                    action: 'comment'),
            icon: const Icon(
              FontAwesomeIcons.comment,
              size: 16,
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 0),
              foregroundColor: Theme.of(context).colorScheme.outline,
            ),
            label: Text(stat?.comment?.count ?? '评论'),
          ),
        ),
        Expanded(
          flex: 1,
          child: TextButton.icon(
            onPressed: handleState(onLikeDynamic),
            icon: Icon(
              stat?.like?.status == true
                  ? FontAwesomeIcons.solidThumbsUp
                  : FontAwesomeIcons.thumbsUp,
              size: 16,
              color: stat?.like?.status == true ? primary : color,
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 0),
              foregroundColor: Theme.of(context).colorScheme.outline,
            ),
            label: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: Text(
                stat?.like?.count ?? '点赞',
                key: ValueKey<String>(stat?.like?.count ?? '点赞'),
                style: TextStyle(
                  color: stat?.like?.status == true ? primary : color,
                ),
              ),
            ),
          ),
        )
      ],
    );
  }
}
