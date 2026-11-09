import 'package:flutter/material.dart';

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
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off_rounded,
    title: 'Couldn’t load this',
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

/// User-facing text for any error.
String friendlyError(Object error) {
  final s = error.toString();
  if (s.contains('SocketException') || s.contains('Network')) {
    return 'Check your connection, then try again.';
  }
  if (s.contains('Timeout'))
    return 'The source took too long to answer. Try again.';
  return s.replaceFirst(RegExp(r'^[A-Za-z]+Exception: '), '');
}
