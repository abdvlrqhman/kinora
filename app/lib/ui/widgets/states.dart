import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stremio/stremio.dart';

import '../../core/log.dart';

import '../glass.dart';
import '../tokens.dart';

/// An empty screen is an invitation to act.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final content = _content();
      // Scrolls instead of overflowing (long errors, large text sizes).
      if (!constraints.hasBoundedHeight) return content;
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: content),
        ),
      );
    },
  );

  Widget _content() => Padding(
    padding: const EdgeInsets.all(KSpace.margin * 1.5),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 36, color: KColors.haze),
          const SizedBox(height: KSpace.x4),
        ],
        Text(title, style: KType.h1),
        const SizedBox(height: KSpace.x2),
        Text(message, style: KType.body.copyWith(color: KColors.haze)),
        if (actionLabel != null) ...[
          const SizedBox(height: KSpace.margin),
          GlassButton(
            label: actionLabel!,
            onPressed: onAction,
            prominent: true,
          ),
        ],
      ],
    ),
  );
}

/// Errors say what happened and what to do; they never apologize.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Couldn’t load this',
  });

  final String message;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off_rounded,
    title: title,
    message: message,
    actionLabel: onRetry == null ? null : 'Try again',
    onAction: onRetry,
  );
}

/// Calm loading block (no spinners over content).
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({
    super.key,
    this.height = 180,
    this.radius = KRadius.poster,
  });

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: KColors.seat,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// What went wrong with an addon, in words. Never includes the URL.
String addonError(Object e) => switch (e) {
  InvalidAddonUrlException() =>
    'That isn’t an addon link. Paste the full link, usually ending in '
        'manifest.json.',
  AddonHttpException(statusCode: 404) =>
    'Nothing was found at that link. Check that it’s complete.',
  AddonHttpException(:final statusCode) =>
    'The addon answered with error $statusCode. Try again later.',
  AddonNetworkException() =>
    'Couldn’t reach the addon. Check your connection and the link.',
  AddonTimeoutException() => 'The addon took too long to answer. Try again.',
  AddonResponseException() =>
    'That link isn’t a Stremio addon, or it sent something Kinora can’t '
        'read.',
  AddonCancelledException() => 'Cancelled.',
  DebridKeyRejectedException() =>
    'Your debrid service rejected the key set in this addon. Configure the '
        'addon again and add the new link.',
  _ => 'The addon couldn’t be added. Try again.',
};

/// User-facing text for any error, never with a URL. The raw error goes
/// to the log (Settings › Diagnostics), not to the screen.
String friendlyError(Object error) {
  final s = error.toString();
  Log.w('error', s);
  return switch (error) {
    // Browsing, not adding: no link was typed, so no "check the link".
    AddonHttpException(statusCode: 404) =>
      'Your sources have nothing for this.',
    AddonHttpException(:final statusCode) =>
      'A source answered with error $statusCode. Try again later.',
    AddonNetworkException() =>
      'Couldn’t reach your sources. Check your connection, then try again.',
    AddonTimeoutException() => 'A source took too long to answer. Try again.',
    DebridKeyRejectedException() => addonError(error),
    StremioException() =>
      'A source sent something Kinora can’t read. Try again, or turn it off '
          'in Settings › Sources.',
    SocketException() => 'Check your connection, then try again.',
    TimeoutException() => 'The source took too long to answer. Try again.',
    HttpException() || HandshakeException() || FormatException() =>
      'The source sent something Kinora can’t read. Try again, or turn this '
          'source off in Settings › Sources.',
    // Kinora's own plain sentences ("No source has details for this title.").
    StateError(:final message) => message,
    _ when s.contains('SocketException') || s.contains('Network') =>
      'Check your connection, then try again.',
    _ when s.contains('Timeout') =>
      'The source took too long to answer. Try again.',
    _ => 'Something went wrong. Try again.',
  };
}
