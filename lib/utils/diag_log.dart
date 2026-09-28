import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 诊断遥测日志：写入 App 外部私有目录，可通过
/// adb exec-out "cat /sdcard/Android/data/com.guozhigq.pilipala/files/diag.log"
/// 直接读取，无需用户任何操作。
class DiagLog {
  static File? _file;
  static bool _broken = false;

  static Future<void> write(String line) async {
    if (_broken) return;
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        _broken = true;
        return;
      }
      _file ??= File('${dir.path}/diag.log');
      _file!.writeAsStringSync('[${DateTime.now()}] $line\n',
          mode: FileMode.append, flush: true);
      // 防止无限膨胀：超过200KB截断重写
      if (_file!.lengthSync() > 200 * 1024) {
        _file!.writeAsStringSync('--- truncated ---\n');
      }
    } catch (_) {
      _broken = true;
    }
  }
}
