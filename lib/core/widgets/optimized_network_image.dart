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
    this.loadingBuilder,
    this.errorBuilder,
  });

  final String url;
  final BoxFit fit;
  final OptimizedImageQuality quality;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = _decodeSize(width, pixelRatio);
    final decodeHeight = _decodeSize(height, pixelRatio);

    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: quality == OptimizedImageQuality.original ? null : decodeWidth,
      cacheHeight:
          quality == OptimizedImageQuality.original ? null : decodeHeight,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
    );
  }

  int? _decodeSize(double? logicalSize, double pixelRatio) {
    if (logicalSize == null || logicalSize <= 0) return null;
    final multiplier = switch (quality) {
      OptimizedImageQuality.thumbnail => 1.15,
      OptimizedImageQuality.medium => 1.35,
      OptimizedImageQuality.original => 1.0,
    };
    return (logicalSize * pixelRatio * multiplier).round();
  }
}
