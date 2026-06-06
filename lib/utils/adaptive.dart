import 'package:flutter/material.dart';

enum WindowSize { compact, medium, expanded }

WindowSize getWindowSize(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 900) return WindowSize.expanded;
  if (width >= 600) return WindowSize.medium;
  return WindowSize.compact;
}

/// 根据屏幕宽度计算网格列数
/// [baseCount] 手机竖屏时的默认列数（通常为2）
int responsiveCrossAxisCount(BuildContext context, {int baseCount = 2}) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 1200) return baseCount + 3;
  if (width >= 900) return baseCount + 2;
  if (width >= 600) return baseCount + 1;
  return baseCount;
}

/// 判断当前是否为平板横屏（宽屏）模式
bool isWideScreen(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= 600;
}

/// D类页面限宽 wrapper
class AdaptiveContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const AdaptiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 600,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
