import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pilipala/common/widgets/network_img_layer.dart';
import 'package:pilipala/models/read/opus.dart';

import 'controller.dart';
import 'text_helper.dart';

class OpusPage extends StatefulWidget {
  const OpusPage({super.key});

  @override
  State<OpusPage> createState() => _OpusPageState();
}

class _OpusPageState extends State<OpusPage> {
  final OpusController controller = Get.put(OpusController());
  late Future _futureBuilderFuture;

  @override
  void initState() {
    super.initState();
    _futureBuilderFuture = controller.fetchOpusData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: CustomScrollView(
        controller: controller.scrollController,
        slivers: [
          SliverList(
            delegate: SliverChildListDelegate(
              [
                _buildTitle(),
                _buildFutureContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: StreamBuilder(
        stream: controller.appbarStream.stream.distinct(),
        initialData: false,
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          return AnimatedOpacity(
            opacity: snapshot.data ? 1 : 0,
            curve: Curves.easeOut,
            duration: const Duration(milliseconds: 500),
            child: Obx(
              () => Text(
                controller.title.value,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          );
        },
      ),
      actions: [
        PopupMenuButton(
          icon: const Icon(Icons.more_vert_outlined),
          itemBuilder: (BuildContext context) => <PopupMenuEntry>[
            PopupMenuItem(
              onTap: controller.onJumpWebview,
              child: const Text('查看原网页'),
            )
          ],
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Obx(
        () => Text(
          controller.title.value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildFutureContent() {
    return FutureBuilder(
      future: _futureBuilderFuture,
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return _buildError('${snapshot.error}');
          }
          if (snapshot.data == null) {
            return _buildError('没有取到内容');
          }
          if (snapshot.data['status']) {
            return _buildContent(controller.opusData.value);
          } else {
            return _buildError(snapshot.data['msg'] ??
                snapshot.data['message'] ??
                '加载失败');
          }
        } else {
          return _buildLoading();
        }
      },
    );
  }

  Widget _buildContent(OpusDataModel opusData) {
    final List<OpusModuleDataModel>? modules = opusData.detail?.modules;
    if (opusData.detail == null || modules == null || modules.isEmpty) {
      return _buildError('这条内容没有可显示的正文');
    }
    ModuleContent? moduleContent;
    // 获取所有的图片链接
    final List<String> picList = [];
    final int moduleIndex =
        modules.indexWhere((module) => module.moduleContent != null);
    if (moduleIndex != -1) {
      moduleContent = modules[moduleIndex].moduleContent;
      for (var paragraph in moduleContent?.paragraphs ?? <ModuleParagraph>[]) {
        if (paragraph.paraType == 2) {
          for (var pic in paragraph.pic?.pics ?? <Pic>[]) {
            final String? url = pic.url;
            if (url != null && url.isNotEmpty) picList.add(url);
          }
        }
      }
    } else {
      print('No moduleContent found');
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(context).padding.bottom + 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 30),
            child: _buildStatsWidget(opusData),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _buildAuthorWidget(opusData),
          ),
          ...(moduleContent?.paragraphs ?? <ModuleParagraph>[]).map(
            (ModuleParagraph paragraph) {
              return Column(
                children: [
                  if (paragraph.paraType == 1) ...[
                    Container(
                      alignment: TextHelper.getAlignment(paragraph.align),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: SelectableText.rich(
                        TextSpan(
                          children: paragraph.text?.nodes?.map((node) {
                                return TextHelper.buildTextSpan(
                                    node, paragraph.align, context);
                              }).toList() ??
                              [],
                        ),
                      ),
                    )
                  ] else if (paragraph.paraType == 2) ...[
                    ...paragraph.pic?.pics?.map(
                          (Pic pic) {
                            // scale/aspectRatio 缺失时不能直接相除，NaN 会让整页布局崩掉
                            final double boxWidth = Get.size.width - 32;
                            final double scale =
                                (pic.scale ?? 0) > 0 ? pic.scale! : 1.0;
                            final double ratio =
                                (pic.aspectRatio ?? 0) > 0 ? pic.aspectRatio! : 0.75;
                            return Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(top: 10, bottom: 10),
                                child: InkWell(
                                  onTap: () {
                                    controller.onPreviewImg(
                                      picList,
                                      picList.indexOf(pic.url ?? ''),
                                      context,
                                    );
                                  },
                                  child: NetworkImgLayer(
                                    src: pic.url,
                                    width: boxWidth * scale,
                                    height: boxWidth * scale / ratio,
                                    type: 'emote',
                                  ),
                                ),
                              ),
                            );
                          },
                        ) ??
                        [],
                  ] else
                    const SizedBox(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorWidget(OpusDataModel opusData) {
    final List<OpusModuleDataModel>? modules = opusData.detail?.modules;
    if (modules == null || modules.isEmpty) {
      return const SizedBox();
    }
    final int moduleIndex =
        modules.indexWhere((module) => module.moduleAuthor != null);
    if (moduleIndex == -1) {
      return const SizedBox();
    }
    final ModuleAuthor moduleAuthor = modules[moduleIndex].moduleAuthor!;
    return Row(
      children: [
        NetworkImgLayer(
          width: 48,
          height: 48,
          type: 'avatar',
          src: moduleAuthor.face,
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              moduleAuthor.name ?? '',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
            StyledText(moduleAuthor.pubTime ?? ''),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsWidget(OpusDataModel opusData) {
    final List<OpusModuleDataModel>? modules = opusData.detail?.modules;
    if (modules == null || modules.isEmpty) {
      return const SizedBox();
    }
    final int moduleIndex =
        modules.lastIndexWhere((module) => module.moduleStat != null);
    if (moduleIndex == -1) {
      return const SizedBox();
    }
    final ModuleStat moduleStat = modules[moduleIndex].moduleStat!;
    final List<Widget> parts = [];
    void addPart(String text) {
      if (parts.isNotEmpty) parts.add(const SizedBox(width: 10));
      parts.add(StyledText(text));
    }

    if (moduleStat.comment?.count != null) {
      addPart('${moduleStat.comment!.count}评论');
    }
    if (moduleStat.like?.count != null) {
      addPart('${moduleStat.like!.count}赞');
    }
    if (moduleStat.favorite?.count != null) {
      addPart('${moduleStat.favorite!.count}转发');
    }
    if (parts.isEmpty) {
      return const SizedBox();
    }
    return Row(children: parts);
  }

  Widget _buildError(String? message) {
    return SizedBox(
      height: 100,
      child: Center(
        child: Text(
          message == null || message.isEmpty ? '加载失败' : message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const SizedBox(
      height: 100,
      child: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class StyledText extends StatelessWidget {
  final String text;

  const StyledText(this.text, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
