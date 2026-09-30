import 'dart:async';

import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/constants.dart';
import 'package:pilipala/common/skeleton/video_card_v.dart';
import 'package:pilipala/common/widgets/http_error.dart';
import 'package:pilipala/common/widgets/video_card_v.dart';
import 'package:pilipala/utils/adaptive.dart';
import 'package:pilipala/utils/main_stream.dart';
import 'package:pilipala/common/widgets/recommendation_visibility.dart';
import 'package:pilipala/models/home/rcmd/result.dart';
import 'package:pilipala/pages/home/controller.dart';
import 'package:pilipala/pages/main/controller.dart';
import 'package:pilipala/utils/recommendation_state.dart';
import 'package:pilipala/utils/recommendation_feedback.dart';

import 'controller.dart';

class RcmdPage extends StatefulWidget {
  const RcmdPage({super.key});

  @override
  State<RcmdPage> createState() => _RcmdPageState();
}

class _RcmdPageState extends State<RcmdPage>
    with AutomaticKeepAliveClientMixin {
  final RcmdController _rcmdController = Get.put(RcmdController());
  late Future _futureBuilderFuture;

  // 补页轮数上限，防止推荐真的空了以后无限发请求
  static const int _maxFillRounds = 4;
  int _fillRounds = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _startLoad(_rcmdController.queryRcmdFeed('init'));
    _rcmdController.scrollController.addListener(_onScroll);
  }

  void _startLoad(Future future) {
    _fillRounds = 0;
    _futureBuilderFuture = future;
    _futureBuilderFuture.then((_) {
      if (mounted) _ensureFillViewport();
    });
  }

  /// 控制器每轮只补到"凑够 6 条"就停，平板上一屏都填不满；而下一页只由
  /// "滚到距底部 200px"触发，内容不溢出视口就永远滚不动，也就永远不加载。
  void _ensureFillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_rcmdController.scrollController.hasClients) return;
      final ScrollPosition position = _rcmdController.scrollController.position;
      if (position.maxScrollExtent >= 200 || _fillRounds >= _maxFillRounds) {
        _fillRounds = 0;
        return;
      }
      _fillRounds++;
      final int before = _rcmdController.videoList.length;
      await _rcmdController.onLoad();
      if (!mounted) return;
      // 一批里全是重复/无新内容，就别再发了
      if (_rcmdController.videoList.length == before) {
        _fillRounds = 0;
        return;
      }
      _ensureFillViewport();
    });
  }

  void _onScroll() {
    final scroll = _rcmdController.scrollController;
    if (scroll.position.pixels >= scroll.position.maxScrollExtent - 200) {
      EasyThrottle.throttle('recommendation-load',
          const Duration(milliseconds: 500), _rcmdController.onLoad);
    }
    handleScrollEvent(scroll);
  }

  bool _isActive() {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return false;
    if (Get.isRegistered<MainController>()) {
      final main = Get.find<MainController>();
      if (main.pagesIds[main.selectedIndex] != 0) return false;
    }
    if (Get.isRegistered<HomeController>()) {
      final home = Get.find<HomeController>();
      if (home.tabbarSort[home.tabController.index] != 'rcmd' ||
          home.tabController.indexIsChanging) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _rcmdController.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      clipBehavior: Clip.hardEdge,
      margin: const EdgeInsets.only(
          left: StyleString.safeSpace, right: StyleString.safeSpace),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(StyleString.imgRadius),
      ),
      child: RefreshIndicator(
        onRefresh: () async {
          await _rcmdController.onRefresh();
          await Future.delayed(const Duration(milliseconds: 300));
          _fillRounds = 0;
          _ensureFillViewport();
        },
        child: CustomScrollView(
          controller: _rcmdController.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding:
                  const EdgeInsets.fromLTRB(0, StyleString.safeSpace, 0, 0),
              sliver: FutureBuilder(
                future: _futureBuilderFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    Map? data = snapshot.data;
                    if (data != null && data['status']) {
                      return Obx(
                        () {
                          if (_rcmdController.isLoadingMore &&
                              _rcmdController.videoList.isEmpty) {
                            return contentGrid(_rcmdController, []);
                          } else {
                            // 显示视频列表
                            return contentGrid(
                                _rcmdController, _rcmdController.videoList);
                          }
                        },
                      );
                    } else {
                      return HttpError(
                        errMsg: data?['msg'] ?? '请求异常',
                        fn: () {
                          setState(() {
                            _rcmdController.isLoadingMore = true;
                            _startLoad(_rcmdController.queryRcmdFeed('init'));
                          });
                        },
                      );
                    }
                  } else {
                    return contentGrid(_rcmdController, []);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget contentGrid(ctr, videoList) {
    // double maxWidth = Get.size.width;
    // int baseWidth = 500;
    // int step = 300;
    // int crossAxisCount =
    //     maxWidth > baseWidth ? 2 + ((maxWidth - baseWidth) / step).ceil() : 2;
    // if (maxWidth < 300) {
    //   crossAxisCount = 1;
    // }
    int crossAxisCount =
        responsiveCrossAxisCount(context, baseCount: ctr.crossAxisCount.value);
    double mainAxisExtent = (Get.size.width /
            crossAxisCount /
            StyleString.aspectRatio) +
        (crossAxisCount == 1 ? 68 : MediaQuery.textScalerOf(context).scale(86));
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        // 行间距
        mainAxisSpacing: StyleString.safeSpace,
        // 列间距
        crossAxisSpacing: StyleString.safeSpace,
        // 列数
        crossAxisCount: crossAxisCount,
        mainAxisExtent: mainAxisExtent,
      ),
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          if (videoList.isEmpty) return const VideoCardVSkeleton();
          final item = videoList[index];
          final mode = ctr.defaultRcmdType;
          final scope = ctr.exposureScope as String;
          return videoList!.isNotEmpty
              ? RecommendationVisibility(
                  key: ValueKey(
                      'rcmd:${recommendationId(item) ?? item.hashCode}:${item is RecVideoItemAppModel ? item.trackId : ''}'),
                  isActive: _isActive,
                  onStart: (start) {
                    ctr.exposed(item, scope: scope);
                    if (item is RecVideoItemAppModel && mode == 'app') {
                      RecommendationFeedback.instance
                          .add(item, 'tm.recommend.feed-card.0.show', index);
                    }
                  },
                  onEnd: (start, end) {
                    if (item is RecVideoItemAppModel && mode == 'app') {
                      RecommendationFeedback.instance.add(
                          item, 'tm.recommend.feed-card.duration.show', index,
                          start: start, end: end);
                    }
                  },
                  child: VideoCardV(
                      videoItem: item,
                      crossAxisCount: crossAxisCount,
                      recommendationPosition: index,
                      blockUserCb: (mid) => ctr.blockUserCb(mid)),
                )
              : const VideoCardVSkeleton();
        },
        childCount: videoList!.isNotEmpty ? videoList!.length : 10,
      ),
    );
  }
}
