import 'package:flutter_test/flutter_test.dart';
import 'package:pilipala/common/widgets/video_card_v.dart';

PictureJump resolve(String uri, {String param = ''}) =>
    VideoCardV.resolvePictureJump(uri: uri, param: param, title: 't');

void main() {
  test('bilibili://opus/detail 走 opus 页', () {
    final jump = resolve('bilibili://opus/detail/1234567890');
    expect(jump.route, 'opus');
    expect(jump.parameters['id'], '1234567890');
    expect(jump.parameters['articleType'], 'opus');
  });

  test('https 版 opus 链接同样识别（旧代码会漏掉并落回 read）', () {
    final jump = resolve('https://www.bilibili.com/opus/1234567890');
    expect(jump.route, 'opus');
    expect(jump.parameters['id'], '1234567890');
  });

  test('专栏两种写法都落到 read 并剥掉 cv 前缀', () {
    expect(
      resolve('bilibili://article/27063554').parameters['id'],
      '27063554',
    );
    final jump = resolve('https://www.bilibili.com/read/cv27063554');
    expect(jump.route, 'read');
    expect(jump.parameters['id'], '27063554');
  });

  test('t.bilibili.com 纯数字动态 id 交给详情接口', () {
    final jump = resolve('https://t.bilibili.com/8123456789');
    expect(jump.route, 'dynamicDetail');
    expect(jump.id, '8123456789');
  });

  test('其余 bilibili:// 与短链交给统一分发器', () {
    expect(resolve('bilibili://following/detail/123').route, 'scheme');
    expect(resolve('bilibili://video/BV1xx411c7mD').route, 'scheme');
    expect(resolve('https://b23.tv/aB3xYz').route, 'scheme');
  });

  test('无 uri 时用 param 兜底，param 也拿不到才提示', () {
    final jump = resolve('', param: '987654321');
    expect(jump.route, 'opus');
    expect(jump.parameters['id'], '987654321');
    expect(resolve('').route, 'none');
  });

  test('协议相对链接不会被解析成空类型', () {
    final jump = resolve('//www.bilibili.com/opus/55667788');
    expect(jump.route, 'opus');
    expect(jump.parameters['id'], '55667788');
  });

  test('opus 链接缺 id 时退回分发器而不是带空参数进页', () {
    expect(resolve('bilibili://opus/detail/').route, 'scheme');
  });

  // 回归：崩溃原因是把 int 的 param 直接塞进 Get.toNamed 的 parameters
  test('跳转参数只可能是 String', () {
    for (final uri in [
      'bilibili://opus/detail/1',
      'https://www.bilibili.com/opus/1',
      'bilibili://article/2',
      'https://www.bilibili.com/read/cv3',
      '',
    ]) {
      final jump = resolve(uri, param: '4');
      expect(jump.parameters.values.every((Object? v) => v is String), isTrue,
          reason: 'uri=$uri 产生了非 String 参数');
    }
  });
}
