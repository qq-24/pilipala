import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilipala/models/home/rcmd/result.dart';
import 'package:pilipala/http/recommendation_request.dart';
import 'package:pilipala/utils/recommendation_state.dart';
import 'package:pilipala/utils/recommendation_codec.dart';

RecVideoItemAppModel item(int id, {String goto = 'av'}) =>
    RecVideoItemAppModel.fromJson({
      'goto': goto,
      'card_goto': goto,
      'param': '$id',
      'args': {'up_id': '42', 'up_name': 'test'},
      if (goto == 'av') 'player_args': {'aid': id, 'cid': 123, 'duration': 90},
      'idx': '1790790509',
      'track_id': 'trace',
      'three_point': {
        'dislike_reasons': [
          {'id': 13, 'name': '推荐过'}
        ]
      },
    });

void main() {
  test('deduplicate inside batch and against already visible content', () {
    final list =
        uniqueRecommendations([item(1), item(1), item(2), item(3)], {'av:3'});
    expect(list.map(recommendationId), ['av:1', 'av:2']);
  });
  test('non-video identities never collide through the -1 sentinel', () {
    expect(recommendationId(item(123, goto: 'picture')), 'picture:123');
    expect(recommendationId(item(456, goto: 'picture')), 'picture:456');
    expect(recommendationId(item(123, goto: 'bangumi')), 'bangumi:123');
  });
  test('model retains server cursor, tracking and explicit feedback reasons',
      () {
    final value = item(123);
    expect(value.idx, 1790790509);
    expect(value.trackId, 'trace');
    expect(value.owner!.mid, 42);
    expect(value.dislikeReasons.single['id'], 13);
  });
  test('raw diagnostic IDs are extracted independently of client filtering',
      () {
    final meta = appFeedMeta({
      'data': {
        'items': [
          {
            'goto': 'av',
            'idx': 100,
            'player_args': {'aid': 123}
          },
          {
            'goto': 'av',
            'idx': 99,
            'args': {'aid': '123'}
          },
          {'goto': 'av', 'idx': 98, 'param': '456'},
        ]
      }
    });
    expect(meta['rawIds'], [123, 123, 456]);
    expect((meta['rawIds'] as List).toSet().length, 2);
    expect(meta['headIdx'], 100);
    expect(meta['tailIdx'], 98);
  });
  test('seen history survives save/load and enforces time and capacity bounds',
      () {
    const now = 2000000000000;
    final seen = RecommendationSeen();
    seen.mark('av:1', now);
    final restored = RecommendationSeen(Map<String, int>.from(seen.entries));
    expect(restored.contains('av:1', now + 1), isTrue);
    expect(
        restored.contains('av:1', now + RecommendationSeen.ttl.inMilliseconds),
        isFalse);
    final large = RecommendationSeen(
        {for (var i = 0; i < 5100; i++) 'av:$i': now - 5100 + i});
    large.prune(now);
    expect(large.entries.length, 5000);
    expect(large.entries.containsKey('av:0'), isFalse);
  });
  test(
      'refresh uses existing head with independent action; load never turns into pull',
      () {
    final cursor = AppFeedCursor()
      ..accept(1790790509, 1790790502, refresh: true);
    cursor.accept(1790790508, 1790790501, refresh: false);
    expect(cursor.head, 1790790509);
    final refresh =
        appFeedParams(idx: cursor.head, pull: true, flush: 6, key: 'test');
    final load =
        appFeedParams(idx: cursor.head, pull: false, flush: 8, key: 'test');
    expect(refresh['idx'], '1790790509');
    expect(refresh['flush'], '6');
    expect(load['pull'], 'false');
    expect(load['flush'], '8');
    cursor.reset();
    expect(cursor.head, 0);
  });
  for (final click in [false, true]) {
    test(
        'RDIO ${click ? 'click' : 'exposure'} matches independent Protobuf golden',
        () {
      final actual = RecommendationCodec.event(
          name:
              click ? 'tm.recommend.0.click' : 'tm.recommend.feed-card.0.show',
          fields: {'track_id': 'trace'},
          mid: '123',
          buvid: 'test-device',
          time: 1700000000000,
          sequence: 1,
          session: 'test-session',
          click: click,
          network: 1);
      final expected = File(
              'test/fixtures/recommendation_${click ? 'click' : 'exposure'}.bin')
          .readAsBytesSync();
      expect(actual, orderedEquals(expected));
    });
  }
}
