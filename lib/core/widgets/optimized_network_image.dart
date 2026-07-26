import 'package:flutter/material.dart';

enum OptimizedImageQuality { thumbnail, medium, original }

class OptimizedNetworkImage extends StatelessWidget {
  const OptimizedNetworkImage({
    super.key,
    required this.url,
    required this.fit,
    required this.quality,
    this.width,
    this.height,
    this.filterQuality = FilterQuality.medium,
    this.frameBuilder,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final String url;
  final BoxFit fit;
  final OptimizedImageQuality quality;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;
  final ImageFrameBuilder? frameBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: providerFor(
        context,
        url: url,
        width: width,
        height: height,
        quality: quality,
      ),
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      frameBuilder: frameBuilder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
    );
  }

  static ImageProvider<Object> providerFor(
    BuildContext context, {
    required String url,
    required double? width,
    required double? height,
    required OptimizedImageQuality quality,
  }) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = quality == OptimizedImageQuality.original
        ? null
        : _decodeSize(width, pixelRatio, quality);
    final decodeHeight = quality == OptimizedImageQuality.original
        ? null
        : _decodeSize(height, pixelRatio, quality);

    return ResizeImage.resizeIfNeeded(
      decodeWidth,
      decodeHeight,
      NetworkImage(url),
    );
  }

  static Future<void> preload(
    BuildContext context, {
    required String url,
    required double? width,
    required double? height,
    required OptimizedImageQuality quality,
  }) {
    return precacheImage(
      providerFor(
        context,
        url: url,
        width: width,
        height: height,
        quality: quality,
      ),
      context,
      onError: (_, __) {},
    );
  }

  static int? _decodeSize(
    double? logicalSize,
    double pixelRatio,
    OptimizedImageQuality quality,
  ) {
    if (logicalSize == null || logicalSize <= 0) return null;
    final multiplier = switch (quality) {
      OptimizedImageQuality.thumbnail => 1.15,
      OptimizedImageQuality.medium => 1.35,
      OptimizedImageQuality.original => 1.0,
    };
    return (logicalSize * pixelRatio * multiplier).round();
  }
}
