import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 生成 DASH MPD 文件并返回文件路径
Future<String> generateDashMpd({
  required String videoUrl,
  required String audioUrl,
  required int durationMs,
  String? videoMimeType,
  String? videoCodecs,
  int? videoBandwidth,
  int? videoWidth,
  int? videoHeight,
  String? videoFrameRate,
  Map? videoSegmentBase,
  String? audioMimeType,
  String? audioCodecs,
  int? audioBandwidth,
  Map? audioSegmentBase,
}) async {
  print('[MPD] generating: video=${videoUrl.substring(0, videoUrl.length < 60 ? videoUrl.length : 60)} audio=${audioUrl.substring(0, audioUrl.length < 60 ? audioUrl.length : 60)}');
  try {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/pilipala_dash.mpd');

  // segmentBase 格式从 B站 API：{"initialization": "0-xxx", "indexRange": "xxx-yyy"}
  final videoInit = videoSegmentBase?['initialization'] ?? '0-0';
  final videoIndex = videoSegmentBase?['indexRange'] ?? '0-0';
  final audioInit = audioSegmentBase?['initialization'] ?? '0-0';
  final audioIndex = audioSegmentBase?['indexRange'] ?? '0-0';

  final durationSec = durationMs / 1000;
  final hours = (durationSec ~/ 3600).toString().padLeft(2, '0');
  final mins = ((durationSec % 3600) ~/ 60).toString().padLeft(2, '0');
  final secs = (durationSec % 60).toStringAsFixed(3);
  final isoDuration = 'PT${hours}H${mins}M${secs}S';

  final mpd = '''<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static"
     mediaPresentationDuration="$isoDuration"
     minBufferTime="PT2S"
     profiles="urn:mpeg:dash:profile:isoff-on-demand:2011">
  <Period>
    <AdaptationSet mimeType="${videoMimeType ?? 'video/mp4'}" contentType="video">
      <Representation id="video" bandwidth="${videoBandwidth ?? 0}"
                      codecs="${videoCodecs ?? 'avc1.640032'}"
                      width="${videoWidth ?? 1920}" height="${videoHeight ?? 1080}"
                      frameRate="${videoFrameRate ?? '30'}">
        <BaseURL>$videoUrl</BaseURL>
        <SegmentBase indexRange="$videoIndex">
          <Initialization range="$videoInit"/>
        </SegmentBase>
      </Representation>
    </AdaptationSet>
    <AdaptationSet mimeType="${audioMimeType ?? 'audio/mp4'}" contentType="audio">
      <Representation id="audio" bandwidth="${audioBandwidth ?? 128000}"
                      codecs="${audioCodecs ?? 'mp4a.40.2'}">
        <BaseURL>$audioUrl</BaseURL>
        <SegmentBase indexRange="$audioIndex">
          <Initialization range="$audioInit"/>
        </SegmentBase>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''';

  await file.writeAsString(mpd);
  print('[MPD] written to: ${file.path}');
  return file.path;
  } catch (e) {
    print('[MPD] ERROR: $e');
    rethrow;
  }
}
