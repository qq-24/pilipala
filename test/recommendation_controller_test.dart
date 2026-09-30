import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/pages/rcmd/controller.dart';
import 'package:pilipala/utils/storage.dart';
import 'recommendation_test.dart' show item;

Map<String, dynamic> response(int start) => {
      'status': true,
      'data': List.generate(6, (n) => item(start + n)),
      'headIdx': 1790790509 + start,
      'tailIdx': 1790790504 + start
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('pilipala-recommend-test-');
    Hive.init(dir.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('cache');
    GStorage.userInfo = await Hive.openBox('user');
    await GStorage.setting.put('defaultRcmdType', 'app');
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test('repeated load triggers share one in-flight request', () async {
    final gate = Completer<Map<String, dynamic>>();
    var calls = 0;
    final ctr = RcmdController(fetchOverride: (_, idx, pull, flush, token) {
      calls++;
      return gate.future;
    })
      ..onInit();
    final a = ctr.onLoad();
    final b = ctr.onLoad();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(identical(a, b), isTrue);
    gate.complete(response(100));
    await a;
    expect(ctr.videoList.length, 6);
    ctr.onClose();
  });
  test('superseded response cannot overwrite newer refresh', () async {
    final old = Completer<Map<String, dynamic>>();
    var calls = 0;
    final ctr = RcmdController(fetchOverride: (_, idx, pull, flush, token) {
      calls++;
      return calls == 1 ? old.future : Future.value(response(200));
    })
      ..onInit();
    final first = ctr.queryRcmdFeed('init');
    await Future<void>.delayed(Duration.zero);
    await ctr.onRefresh();
    old.complete(response(100));
    await first;
    expect(ctr.videoList.map((e) => e.aid), [200, 201, 202, 203, 204, 205]);
    ctr.onClose();
  });
  test('refresh state carries returned cursor and correct events', () async {
    final calls = <List<dynamic>>[];
    var batch = 0;
    final ctr = RcmdController(fetchOverride: (mode, idx, pull, flush, token) {
      calls.add([idx, pull, flush]);
      return Future.value(response(300 + 100 * batch++));
    })
      ..onInit();
    await ctr.queryRcmdFeed('init');
    await ctr.onRefresh();
    await ctr.onLoad();
    expect(calls[0], [0, true, 0]);
    expect(calls[1], [1790790809, true, 6]);
    expect(calls[2], [1790790909, false, 8]);
    ctr.onClose();
  });
}
