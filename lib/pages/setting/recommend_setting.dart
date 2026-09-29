import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/member.dart';
import 'package:pilipala/http/video.dart';
import 'package:pilipala/models/common/rcmd_type.dart';
import 'package:pilipala/models/user/info.dart';
import 'package:pilipala/pages/rcmd/controller.dart';
import 'package:pilipala/pages/setting/widgets/select_dialog.dart';
import 'package:pilipala/utils/recommend_filter.dart';
import 'package:pilipala/utils/storage.dart';

import 'widgets/switch_item.dart';

class RecommendSetting extends StatefulWidget {
  const RecommendSetting({super.key});

  @override
  State<RecommendSetting> createState() => _RecommendSettingState();
}

class _RecommendSettingState extends State<RecommendSetting> {
  Box setting = GStorage.setting;
  static Box localCache = GStorage.localCache;
  late dynamic defaultRcmdType;
  Box userInfoCache = GStorage.userInfo;
  UserInfoData? userInfo;
  bool userLogin = false;
  late dynamic accessKeyInfo;
  // late int filterUnfollowedRatio;
  late int minDurationForRcmd;
  late int minLikeRatioForRecommend;

  @override
  void initState() {
    super.initState();
    // 首页默认推荐类型
    defaultRcmdType =
        setting.get(SettingBoxKey.defaultRcmdType, defaultValue: 'web');
    userInfo = userInfoCache.get('userInfoCache');
    userLogin = userInfo != null;
    accessKeyInfo = localCache.get(LocalCacheKey.accessKey, defaultValue: null);
    // filterUnfollowedRatio = setting
    //     .get(SettingBoxKey.filterUnfollowedRatio, defaultValue: 0);
    minDurationForRcmd =
        setting.get(SettingBoxKey.minDurationForRcmd, defaultValue: 0);
    minLikeRatioForRecommend =
        setting.get(SettingBoxKey.minLikeRatioForRecommend, defaultValue: 0);
  }

  @override
  Widget build(BuildContext context) {
    TextStyle titleStyle = Theme.of(context).textTheme.titleMedium!;
    TextStyle subTitleStyle = Theme.of(context)
        .textTheme
        .labelMedium!
        .copyWith(color: Theme.of(context).colorScheme.outline);
    return Scaffold(
      appBar: AppBar(title: const Text('推荐设置')),
      body: ListView(
        children: [
          ListTile(
            dense: false,
            title: Text('首页推荐类型', style: titleStyle),
            subtitle: Text(
              '当前使用「$defaultRcmdType端」推荐¹',
              style: subTitleStyle,
            ),
            onTap: () async {
              String? result = await showDialog(
                context: context,
                builder: (context) {
                  return SelectDialog<String>(
                    title: '推荐类型',
                    value: defaultRcmdType,
                    values: RcmdType.values.map((e) {
                      return {'title': e.labels, 'value': e.values};
                    }).toList(),
                  );
                },
              );
              if (result == null || result == defaultRcmdType) return;
              if (!context.mounted) return;
              if (result == 'app') {
                if (!userLogin) {
                  SmartDialog.showToast('请先登录');
                  return;
                }
                // 切到app端每次都确认：小票缺失/换过号时提示风控风险，已有有效小票只做告知
                final bool needKey = accessKeyInfo == null ||
                    (userInfo != null &&
                        '${accessKeyInfo['mid']}' != '${userInfo!.mid}');
                final bool? go = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('切换到app端推荐'),
                      content: Text(needKey
                          ? '使用app端推荐需获取access_key，有小概率触发风控导致账号退出（在官方版本app重新登录即可解除），是否继续？'
                          : '当前access_key有效，切换后立即生效，推荐将变为app端个性化内容，是否继续？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('确定'),
                        ),
                      ],
                    );
                  },
                );
                if (go != true) return;
                if (needKey) {
                  await MemberHttp.cookieToKey();
                  accessKeyInfo =
                      localCache.get(LocalCacheKey.accessKey, defaultValue: null);
                }
              }
              defaultRcmdType = result;
              setting.put(SettingBoxKey.defaultRcmdType, result);
              // 首页控制器还在就热切换立即生效，否则下次启动生效
              if (Get.isRegistered<RcmdController>()) {
                SmartDialog.showLoading(msg: '切换中…');
                try {
                  await Get.find<RcmdController>()
                      .switchRcmdType(result)
                      .timeout(const Duration(seconds: 30));
                  SmartDialog.showToast('已切换为「$result端」推荐');
                } catch (_) {
                  SmartDialog.showToast('切换超时，已保存，下次启动生效');
                } finally {
                  SmartDialog.dismiss();
                }
              } else {
                SmartDialog.showToast('下次启动时生效');
              }
              setState(() {});
            },
          ),
          const SetSwitchItem(
            title: '推荐动态',
            subTitle: '是否在推荐内容中展示动态(仅app端)',
            setKey: SettingBoxKey.enableRcmdDynamic,
            defaultVal: true,
          ),
          const SetSwitchItem(
            title: '首页推荐刷新',
            subTitle: '下拉刷新时保留上次内容',
            setKey: SettingBoxKey.enableSaveLastData,
            defaultVal: false,
          ),
          ListTile(
            dense: false,
            title: Text('诊断app端推荐', style: titleStyle),
            subtitle: Text(
              '对比明文/签名/游客三种请求，定位推荐失效根因。建议先在「隐私设置」刷新access_key后马上诊断',
              style: subTitleStyle,
            ),
            onTap: () async {
              SmartDialog.showLoading(msg: '诊断中…');
              late final res;
              try {
                res = await VideoHttp.diagnoseAppRcmd();
              } catch (e) {
                res = {'status': false, 'msg': '诊断异常：$e'};
              }
              SmartDialog.dismiss();
              String head;
              List<String> liveTitles = [];
              List<String> guestTitles = [];
              if (!res['status']) {
                head = res['msg'];
              } else {
                final double ov = res['overlap'];
                final bool guestOk = res['guestOk'];
                final bool midMatch = userInfo != null &&
                    accessKeyInfo != null &&
                    '${accessKeyInfo['mid']}' == '${userInfo!.mid}';
                final String verdict;
                if (!guestOk) {
                  verdict =
                      '真游客基准仍失败（${res['guestErr']}），无法自动对比。'
                      '请直接目测下方「当前推荐」标题是否与你兴趣相关。';
                } else if (ov >= 0.9) {
                  verdict =
                      '当前推荐与真游客结果几乎一致（${(ov * 100).toStringAsFixed(0)}%重合）'
                      '→ 登录态未生效，看到的是分发给所有人的通用内容';
                } else if (ov >= 0.5) {
                  verdict =
                      '重合率偏高（${(ov * 100).toStringAsFixed(0)}%）'
                      '→ 部分生效或热度内容占比大，建议结合标题判断';
                } else {
                  verdict =
                      '与真游客结果差异显著（重合仅${(ov * 100).toStringAsFixed(0)}%）'
                      '→ app端推荐携带的登录态正在生效，内容是你的个性化流';
                }
                head = 'token归属与当前账号一致：'
                    '${midMatch ? '是' : '否（换过号，建议刷新token后重测）'}\n'
                    '签名请求重合率：${res['signedCode'] == 0 ? '${(res['signedOverlap'] * 100).toStringAsFixed(0)}%' : '失败(code=${res['signedCode']})'}\n\n'
                    '$verdict';
                liveTitles = res['liveTitles'].cast<String>();
                guestTitles = res['guestTitles'].cast<String>();
              }
              if (context.mounted) {
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('诊断结果'),
                      content: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(head,
                                style:
                                    Theme.of(context).textTheme.labelLarge),
                            if (liveTitles.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text('■ 当前app端推荐（登录态）：',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall),
                              ...liveTitles.map((e) => Text('  $e',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall)),
                            ],
                            if (guestTitles.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text('■ 真游客（无任何登录信息）：',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall),
                              ...guestTitles.map((e) => Text('  $e',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall)),
                            ],
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('关闭'),
                        ),
                      ],
                    );
                  },
                );
              }
            },
          ),
          // 分割线
          const Divider(height: 1),
          ListTile(
            dense: false,
            title: Text('点赞率过滤', style: titleStyle),
            subtitle: Text(
              '过滤掉点赞数/播放量「小于$minLikeRatioForRecommend%」的推荐视频(仅web端)',
              style: subTitleStyle,
            ),
            onTap: () async {
              int? result = await showDialog(
                context: context,
                builder: (context) {
                  return SelectDialog<int>(
                      title: '选择点赞率（0即不过滤）',
                      value: minLikeRatioForRecommend,
                      values: [0, 1, 2, 3, 4].map((e) {
                        return {'title': '$e %', 'value': e};
                      }).toList());
                },
              );
              if (result != null) {
                minLikeRatioForRecommend = result;
                setting.put(SettingBoxKey.minLikeRatioForRecommend, result);
                RecommendFilter.update();
                setState(() {});
              }
            },
          ),
          ListTile(
            dense: false,
            title: Text('视频时长过滤', style: titleStyle),
            subtitle: Text(
              '过滤掉时长「小于$minDurationForRcmd秒」的推荐视频',
              style: subTitleStyle,
            ),
            onTap: () async {
              int? result = await showDialog(
                context: context,
                builder: (context) {
                  return SelectDialog<int>(
                      title: '选择时长（0即不过滤）',
                      value: minDurationForRcmd,
                      values: [0, 30, 60, 90, 120].map((e) {
                        return {'title': '$e 秒', 'value': e};
                      }).toList());
                },
              );
              if (result != null) {
                minDurationForRcmd = result;
                setting.put(SettingBoxKey.minDurationForRcmd, result);
                RecommendFilter.update();
                setState(() {});
              }
            },
          ),
          SetSwitchItem(
            title: '已关注Up豁免推荐过滤',
            subTitle: '推荐中已关注用户发布的内容不会被过滤',
            setKey: SettingBoxKey.exemptFilterForFollowed,
            defaultVal: true,
            callFn: (_) => {RecommendFilter.update},
          ),
          // ListTile(
          //   dense: false,
          //   title: Text('按比例过滤未关注Up', style: titleStyle),
          //   subtitle: Text(
          //     '滤除推荐中占比「$filterUnfollowedRatio%」的未关注用户发布的内容',
          //     style: subTitleStyle,
          //   ),
          //   onTap: () async {
          //     int? result = await showDialog(
          //       context: context,
          //       builder: (context) {
          //         return SelectDialog<int>(
          //             title: '选择滤除比例（0即不过滤）',
          //             value: filterUnfollowedRatio,
          //             values: [0, 16, 32, 48, 64].map((e) {
          //               return {'title': '$e %', 'value': e};
          //             }).toList());
          //       },
          //     );
          //     if (result != null) {
          //       filterUnfollowedRatio = result;
          //       setting.put(
          //           SettingBoxKey.filterUnfollowedRatio, result);
          //       RecommendFilter.update();
          //       setState(() {});
          //     }
          //   },
          // ),
          SetSwitchItem(
            title: '过滤器也应用于相关视频',
            subTitle: '视频详情页的相关视频也进行过滤²',
            setKey: SettingBoxKey.applyFilterToRelatedVideos,
            defaultVal: true,
            callFn: (_) => {RecommendFilter.update},
          ),
          ListTile(
            dense: true,
            subtitle: Text(
              '¹ 若默认web端推荐不太符合预期，可尝试切换至app端。\n'
              '¹ 选择“模拟未登录(notLogin)”，将以空的key请求推荐接口，但播放页仍会携带用户信息，保证账号能正常记录进度、点赞投币等。\n\n'
              '² 由于接口未提供关注信息，无法豁免相关视频中的已关注Up。\n\n'
              '* 其它（如热门视频、手动搜索、链接跳转等）均不受过滤器影响。\n'
              '* 设定较严苛的条件可导致推荐项数锐减或多次请求，请酌情选择。\n'
              '* 后续可能会增加更多过滤条件，敬请期待。',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color:
                      Theme.of(context).colorScheme.outline.withOpacity(0.7)),
            ),
          )
        ],
      ),
    );
  }
}
