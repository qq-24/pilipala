import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/utils/extension.dart';
import 'package:pilipala/utils/global_data_cache.dart';
import '../../utils/storage.dart';
import '../constants.dart';

Box<dynamic> setting = GStorage.setting;

class NetworkImgLayer extends StatelessWidget {
  const NetworkImgLayer({
    super.key,
    this.src,
    required this.width,
    required this.height,
    this.type,
    this.fadeOutDuration,
    this.fadeInDuration,
    // 图片质量 默认1%
    this.quality,
    this.origAspectRatio,
    this.radius,
  });

  final String? src;
  final double width;
  final double height;
  final String? type;
  final Duration? fadeOutDuration;
  final Duration? fadeInDuration;
  final int? quality;
  final double? origAspectRatio;
  final double? radius;

  BorderRadius getBorderRadius(String? type, double? radius) {
    return BorderRadius.circular(
      radius ??
          (type == 'avatar'
              ? 50
              : type == 'emote'
                  ? 0
                  : StyleString.imgRadius.x),
    );
  }

  @override
  Widget build(BuildContext context) {
    int defaultImgQuality = 10;
    try {
      defaultImgQuality = GlobalDataCache.imgQuality;
    } catch (_) {}

    if (src == '' || src == null) {
      return placeholder(context);
    }
    String imageUrl = src!.startsWith('//') ? 'https:${src!}' : src!;
    // opus 正文图有一部分 B 站下发的是 http://，而 targetSdk 34 默认禁明文，
    // 图片会静默加载失败；hdslb 同一对象 https 可直接取（实测字节数一致）
    if (imageUrl.startsWith('http://') && imageUrl.contains('hdslb.com')) {
      imageUrl = imageUrl.replaceFirst('http://', 'https://');
    }
    imageUrl = '$imageUrl@${quality ?? defaultImgQuality}q.webp';
    int? memCacheWidth, memCacheHeight;
    double aspectRatio = (width / height).toDouble();

    void setMemCacheSizes() {
      if (aspectRatio > 1) {
        memCacheHeight = height.cacheSize(context);
      } else if (aspectRatio < 1) {
        memCacheWidth = width.cacheSize(context);
      } else {
        if (origAspectRatio != null && origAspectRatio! > 1) {
          memCacheWidth = width.cacheSize(context);
        } else if (origAspectRatio != null && origAspectRatio! < 1) {
          memCacheHeight = height.cacheSize(context);
        } else {
          memCacheWidth = width.cacheSize(context);
          memCacheHeight = height.cacheSize(context);
        }
      }
    }

    setMemCacheSizes();

    if (memCacheWidth == null && memCacheHeight == null) {
      memCacheWidth = width.toInt();
    }

    return src != '' && src != null
        ? ClipRRect(
            clipBehavior: Clip.antiAlias,
            borderRadius: getBorderRadius(type, radius),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: width,
              height: height,
              memCacheWidth: memCacheWidth,
              memCacheHeight: memCacheHeight,
              fit: BoxFit.cover,
              fadeOutDuration:
                  fadeOutDuration ?? const Duration(milliseconds: 120),
              fadeInDuration:
                  fadeInDuration ?? const Duration(milliseconds: 120),
              filterQuality: FilterQuality.low,
              errorWidget: (BuildContext context, String url, Object error) =>
                  placeholder(context),
              placeholder: (BuildContext context, String url) =>
                  placeholder(context),
            ),
          )
        : placeholder(context);
  }

  Widget placeholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onInverseSurface.withOpacity(0.4),
        borderRadius: getBorderRadius(type, radius),
      ),
      child: type == 'bg'
          ? const SizedBox()
          : Center(
              child: Image.asset(
                type == 'avatar'
                    ? 'assets/images/noface.jpeg'
                    : 'assets/images/loading.png',
                width: width,
                height: height,
                cacheWidth: width.cacheSize(context),
                cacheHeight: height.cacheSize(context),
              ),
            ),
    );
  }
}
