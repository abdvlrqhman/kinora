import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../tokens.dart';

/// Network artwork (poster, backdrop, still) with a quiet placeholder that
/// shows the title when there's no image. Never flashes white.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    this.fallbackText,
    this.radius = 0,
    this.fit = BoxFit.cover,
    this.aspectRatio,
    this.memCacheWidth,
    this.alignment = Alignment.center,
  });

  final String? url;
  final String? fallbackText;
  final double radius;
  final BoxFit fit;
  final double? aspectRatio;

  /// Decode width in physical pixels (keeps memory low in long rows).
  final int? memCacheWidth;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(text: fallbackText);
    final local = _localProvider(url);
    Widget child = url == null || url!.isEmpty
        ? placeholder
        : local != null
        ? Image(
            image: ResizeImage.resizeIfNeeded(memCacheWidth, null, local),
            fit: fit,
            alignment: alignment,
            errorBuilder: (_, _, _) => placeholder,
          )
        : CachedNetworkImage(
            imageUrl: url!,
            fit: fit,
            alignment: alignment,
            memCacheWidth: memCacheWidth,
            fadeInDuration: KMotion.base,
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
    if (radius > 0) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      );
    }
    if (aspectRatio != null)
      child = AspectRatio(aspectRatio: aspectRatio!, child: child);
    return child;
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.text});
  final String? text;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: KColors.seat,
    child: text == null
        ? const SizedBox.expand()
        : LayoutBuilder(
            // Too small for the name (a list thumbnail): a film mark.
            builder: (context, box) => box.maxWidth < 110
                ? const Center(
                    child: Icon(Icons.movie_outlined, color: KColors.reel),
                  )
                : _name(),
          ),
  );

  Widget _name() => Padding(
    padding: const EdgeInsets.all(KSpace.x3),
    child: Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        text!,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: KType.h2.copyWith(
          fontSize: 20,
          height: 1.05,
          color: KColors.haze,
        ),
      ),
    ),
  );
}

/// Image provider for tinting from a URL (null-safe). Besides http(s) it
/// takes `asset:<path>` and `file:` URIs (local art, tests).
ImageProvider? artworkProvider(String? url) => url == null || url.isEmpty
    ? null
    : _localProvider(url) ?? CachedNetworkImageProvider(url);

ImageProvider? _localProvider(String? url) {
  if (url == null) return null;
  if (url.startsWith('asset:')) return AssetImage(url.substring(6));
  if (url.startsWith('file:'))
    return FileImage(File(Uri.parse(url).toFilePath()));
  return null;
}
