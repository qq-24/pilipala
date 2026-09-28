import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/http/member.dart';
import 'package:pilipala/http/user.dart';
import 'package:pilipala/models/user/info.dart';
import 'package:pilipala/utils/storage.dart';

class PrivacySetting extends StatefulWidget {
  const PrivacySetting({super.key});

  @override
  State<PrivacySetting> createState() => _PrivacySettingState();
}

class _PrivacySettingState extends State<PrivacySetting> {
  bool userLogin = false;
  Box userInfoCache = GStorage.userInfo;
  UserInfoData? userInfo;

  @override
  void initState() {
    super.initState();
    userInfo = userInfoCache.get('userInfoCache');
    userLogin = userInfo != null;
  }

  @override
  Widget build(BuildContext context) {
    TextStyle titleStyle = Theme.of(context).textTheme.titleMedium!;
    TextStyle subTitleStyle = Theme.of(context)
        .textTheme
        .labelMedium!
        .copyWith(color: Theme.of(context).colorScheme.outline);
    return Scaffold(
      appBar: AppBar(title: const Text('隐私设置')),
      body: Column(
        children: [
          ListTile(
            onTap: () {
              if (!userLogin) {
                SmartDialog.showToast('登录后查看');
                return;
              }
              Get.toNamed('/blackListPage');
            },
            dense: false,
            title: Text('黑名单管理', style: titleStyle),
            subtitle: Text('已拉黑用户', style: subTitleStyle),
          ),
          ListTile(
            onTap: () {
              if (!userLogin) {
                SmartDialog.showToast('请先登录');
              }
              MemberHttp.cookieToKey();
            },
            dense: false,
            title: Text('刷新access_key', style: titleStyle),
          ),
          ListTile(
            onTap: () async {
              SmartDialog.showLoading(msg: '同步中…');
              final res = await MemberHttp.cookieSync();
              SmartDialog.dismiss();
              SmartDialog.showToast(
                  '登录态同步：${res['status'] == true ? '成功' : '失败 ${res['msg']}'}');
            },
            dense: false,
            title: Text('登录态云端同步', style: titleStyle),
            subtitle: Text('原版APK同款会话续签机制，每次启动自动执行',
                style: subTitleStyle),
          ),
          ListTile(
            onTap: () async {
              SmartDialog.showLoading(msg: '自检中…');
              late List<Map<String, String>> rows;
              try {
                rows = await UserHttp.loginSelfCheck();
              } catch (e) {
                rows = [
                  {'name': '异常', 'code': 'X', 'msg': '$e'}
                ];
              }
              SmartDialog.dismiss();
              if (context.mounted) {
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('登录态自检'),
                      content: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var r in rows)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 3),
                                child: Text(
                                  '${r['name']}: '
                                  '${r['code']!.isEmpty ? '' : 'code=${r['code']} '}'
                                  '${r['msg']}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium,
                                ),
                              ),
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
            dense: false,
            title: Text('登录态自检（诊断）', style: titleStyle),
            subtitle: Text(
              '逐项探测 nav/cookie/收藏/历史/动态 的B站原始返回码',
              style: subTitleStyle,
            ),
          ),
        ],
      ),
    );
  }
}
