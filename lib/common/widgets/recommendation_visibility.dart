import 'dart:async';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Emit only for a card actually visible in the active, foreground page.
class RecommendationVisibility extends StatefulWidget {
  final Widget child;
  final bool Function() isActive;
  final void Function(int start) onStart;
  final void Function(int start, int end) onEnd;
  final int Function()? clock;
  const RecommendationVisibility(
      {super.key,
      required this.child,
      required this.isActive,
      required this.onStart,
      required this.onEnd,
      this.clock});
  @override
  State<RecommendationVisibility> createState() =>
      _RecommendationVisibilityState();
}

class _RecommendationVisibilityState extends State<RecommendationVisibility> {
  double _fraction = 0;
  int? _start;
  bool _reported = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _check());
  }

  void _check() {
    if (!mounted) return;
    final now = widget.clock?.call() ?? DateTime.now().millisecondsSinceEpoch;
    if (_fraction < 0.5 ||
        !widget.isActive() ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _end(now);
      return;
    }
    _start ??= now;
    if (!_reported && now - _start! >= 1000) {
      _reported = true;
      widget.onStart(_start!);
    }
  }

  void _end(int now) {
    if (_reported && _start != null) widget.onEnd(_start!, now);
    _start = null;
    _reported = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _end(widget.clock?.call() ?? DateTime.now().millisecondsSinceEpoch);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VisibilityDetector(
      key: ValueKey('visibility:${widget.key}'),
      onVisibilityChanged: (info) {
        _fraction = info.visibleFraction;
        _check();
      },
      child: widget.child);
}
