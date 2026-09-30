import 'package:flutter/material.dart';
import 'package:pilipala/models/read/opus.dart';

class TextHelper {
  // B站偶尔下发非 6 位十六进制色值，直接 substring(1,7) 会 RangeError 把整页带崩
  static Color? parseColor(String? raw) {
    if (raw == null) return null;
    final String hex = raw.replaceFirst('#', '').replaceFirst('0x', '');
    if (hex.length != 6) return null;
    final int? value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value + 0xFF000000);
  }

  static Alignment getAlignment(int? align) {
    switch (align) {
      case 1:
        return Alignment.center;
      case 0:
        return Alignment.centerLeft;
      case 2:
        return Alignment.centerRight;
      default:
        return Alignment.centerLeft;
    }
  }

  static TextSpan buildTextSpan(
      ModuleParagraphTextNode node, int? align, BuildContext context) {
    // 获取node的所有key
    if (node.nodeType != null) {
      return TextSpan(
        text: node.word?.words ?? '',
        style: TextStyle(
          fontSize:
              node.word?.fontSize != null ? node.word!.fontSize! * 0.95 : 14,
          fontWeight: node.word?.style?.bold != null
              ? FontWeight.bold
              : FontWeight.normal,
          height: align == 1 ? 2 : 1.5,
          color: parseColor(node.word?.color) ??
              Theme.of(context).colorScheme.onBackground,
        ),
      );
    } else {
      switch (node.type) {
        case 'TEXT_NODE_TYPE_WORD':
          return TextSpan(
            text: node.word?.words ?? '',
            style: TextStyle(
              fontSize: node.word?.fontSize != null
                  ? node.word!.fontSize! * 0.95
                  : 14,
              fontWeight: node.word?.style?.bold != null
                  ? FontWeight.bold
                  : FontWeight.normal,
              height: align == 1 ? 2 : 1.5,
              color: parseColor(node.word?.color) ??
                  Theme.of(context).colorScheme.onBackground,
            ),
          );
        default:
          return const TextSpan(text: '');
      }
    }
  }
}
