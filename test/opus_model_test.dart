import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilipala/models/read/opus.dart';

/// fixture 是从 api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail 抓下来的
/// 真实返回（未手写、未美化），字段类型就是 B 站实际下发的样子。
Map<String, dynamic> fixture() => json.decode(
      File('test/fixtures/opus_detail_sample.json').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  test('真实 basic.uid 是 String，旧声明 int? 会在 fromJson 直接抛', () {
    final raw = fixture()['detail']['basic']['uid'];
    expect(raw, isA<String>(), reason: 'B站若改回 int，这条证据就过期了');
    // 旧代码就是这一句：int? uid = json['uid']
    expect(() {
      final dynamic drifted = raw;
      final int? typed = drifted;
      return typed;
    }, throwsA(isA<TypeError>()));
  });

  test('解析真实 opus 详情不再抛异常，且各模块取到值', () {
    late OpusDataModel data;
    expect(() => data = OpusDataModel.fromJson(fixture()), returnsNormally);

    expect(data.detail!.basic!.uid, 3493257977792627);
    expect(data.detail!.basic!.title, contains('Liyuu'));
    expect(data.detail!.modules!.length, 3);

    final content = data.detail!.modules!
        .map((m) => m.moduleContent)
        .firstWhere((c) => c != null)!;
    expect(content.paragraphs!.length, 2);
    final pics = content.paragraphs![1].pic!.pics!;
    expect(pics.single.width, 1500);
    expect(pics.single.height, 2180);
    expect(pics.single.size, closeTo(4926.64, 0.01));
    expect(pics.single.aspectRatio, closeTo(1500 / 2180, 0.0001));
    expect(pics.single.scale, closeTo(1500 / 2180, 0.0001));
    expect(pics.single.url, isNotEmpty);

    final stat = data.detail!.modules!.last.moduleStat!;
    expect(stat.like!.count, 366);
    expect(stat.comment!.count, 44);
    expect(stat.forward!.count, 29);
  });

  test('字段类型再漂移也只会降级成 null，不会掀掉整页', () {
    final drifted = <String, dynamic>{
      'detail': <String, dynamic>{
        'basic': <String, dynamic>{
          'uid': 123, // 反过来变 int
          'title': 456, // 变 int
          'comment_type': '11', // 变 String
        },
        'modules': <dynamic>[
          <String, dynamic>{
            'module_stat': <String, dynamic>{
              'like': <String, dynamic>{'count': '9', 'forbidden': 0},
            },
            'module_content': <String, dynamic>{
              'paragraphs': <dynamic>[
                <String, dynamic>{
                  'para_type': '2',
                  'align': null,
                  'pic': <String, dynamic>{
                    'pics': <dynamic>[
                      <String, dynamic>{'width': '0', 'height': 0, 'size': null},
                    ],
                  },
                },
              ],
            },
          },
        ],
      },
    };

    late OpusDataModel data;
    expect(() => data = OpusDataModel.fromJson(drifted), returnsNormally);
    expect(data.detail!.basic!.uid, 123);
    expect(data.detail!.basic!.title, '456');
    expect(data.detail!.basic!.commentType, 11);
    final module = data.detail!.modules!.single;
    expect(module.moduleStat!.like!.count, 9);
    expect(module.moduleStat!.like!.forbidden, false);
    final pic = module.moduleContent!.paragraphs!.single.pic!.pics!.single;
    // 宽或高为 0 时不做除法，避免 NaN 尺寸把布局炸掉
    expect(pic.aspectRatio, 0);
    expect(pic.scale, 0);
  });

  test('modules 缺失或不是列表时不炸', () {
    expect(() => OpusDataModel.fromJson({'detail': {'basic': null}}),
        returnsNormally);
    expect(
        () => OpusDataModel.fromJson({
              'detail': {'modules': 'not-a-list'}
            }),
        returnsNormally);
  });
}
