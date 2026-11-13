import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:stremio/stremio.dart';

import '../../app/desktop.dart';
import '../../core/format.dart';
import '../tint.dart';
import '../tokens.dart';
import 'artwork.dart';
import 'pointer.dart';

final _firstLetter = RegExp(r'\p{L}', unicode: true);
final _rtlLetter = RegExp(r'[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');

/// Direction of content text (titles, overviews) from its first letter:
/// Arabic, Hebrew and similar scripts read right to left.
TextDirection contentDir(String text) {
  final first = _firstLetter.firstMatch(text)?[0];
  return first != null && _rtlLetter.hasMatch(first)
      ? TextDirection.rtl
      : TextDirection.ltr;
}

/// [text] isolated (U+2068 … U+2069) so its direction can't reorder the
/// text around it in a mixed line ("E3  <Arabic title>").
String isolate(String text) => '\u2068$text\u2069';

/// Decode width in physical pixels for an image shown [logical] px wide.
int decodeWidth(BuildContext context, double logical) =>
    (logical * MediaQuery.devicePixelRatioOf(context)).round();

/// Tappable content (posters, stills, rows): scales down slightly while
/// pressed, unless reduced motion is on. One semantics node with [label].
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.label,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.hint,
    this.actions,
    this.lift = false,
    this.plain = false,
  });

  final String label;
  final Widget child;

  /// Artwork (posters, stills): grows a little under the mouse. Rows get a
  /// faint highlight instead.
  final bool lift;

  /// No hover effect of its own (the child draws one).
  final bool plain;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Spoken after the label, e.g. "Plays episode".
  final String? hint;

  /// Extra screen-reader actions (stand-ins for the long-press menu).
  final Map<CustomSemanticsAction, VoidCallback>? actions;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      hint: widget.hint,
      customSemanticsActions: widget.actions,
      onLongPress: widget.onLongPress,
      excludeSemantics: true,
      child: PointerFocus(
        onActivate: widget.onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.poster),
        ),
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _set(true) : null,
          onTapUp: enabled ? (_) => _set(false) : null,
          onTapCancel: () => _set(false),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress == null
              ? null
              : () {
                  _set(false);
                  HapticFeedback.mediumImpact();
                  widget.onLongPress!();
                },
          child: AnimatedScale(
            scale: reduce
                ? 1
                : _down
                ? 0.97
                : hovered && widget.lift && !widget.plain
                ? 1.03
                : 1,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: hovered && !widget.lift && !widget.plain
                ? DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      color: const Color(0x0AFFFFFF),
                      borderRadius: BorderRadius.circular(KRadius.poster),
                    ),
                    child: widget.child,
                  )
                : widget.child,
          ),
        ),
      ),
    );
  }
}

/// Hero tag for a video's artwork: the still or backdrop you tap grows into
/// the player while it prepares. One per video on a page.
String artHeroTag(String videoId) => 'art-$videoId';

/// The video whose artwork is flying into the player right now. Set by
/// `openPlayer`, cleared when the player closes; every other ArtHero stays
/// put, so artwork never flies between Home and Title.
final launchingArt = ValueNotifier<String?>(null);

/// Artwork that flies into the player when its video starts.
class ArtHero extends StatelessWidget {
  const ArtHero({super.key, required this.videoId, required this.child});

  final String videoId;
  final Widget child;

  // Off in hidden tabs (go_router keeps them alive offstage, tickers off),
  // so nothing flies from a screen you can't see.
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: launchingArt,
    child: Hero(
      tag: artHeroTag(videoId),
      curve: KMotion.emphasized,
      child: child,
    ),
    builder: (context, launching, hero) => HeroMode(
      enabled: launching == videoId && TickerMode.valuesOf(context).enabled,
      child: hero!,
    ),
  );
}

/// Poster size used in rows (and Search's grid). A computer's window
/// shows them larger as it widens; a phone keeps one size.
abstract final class PosterSize {
  static const double width = 116;
  static const double height = width * 1.5;

  static double widthOf(BuildContext context) {
    if (!isDesktop) return width;
    final w = MediaQuery.sizeOf(context).width;
    return w < 800
        ? 140
        : w < 1180
        ? 160
        : w < 1580
        ? 180
        : 200;
  }

  static double heightOf(BuildContext context) => widthOf(context) * 1.5;
}

/// A 2:3 poster that opens its title. No caption: the art carries the name,
/// and the placeholder shows it when there's no art.
class PosterTile extends StatelessWidget {
  const PosterTile({
    super.key,
    required this.name,
    required this.poster,
    required this.onTap,
    this.width = PosterSize.width,
  });

  final String name;
  final String? poster;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) => Pressable(
    lift: true,
    label: name,
    onTap: onTap,
    child: Artwork(
      url: poster,
      fallbackText: name,
      radius: KRadius.poster,
      aspectRatio: 2 / 3,
      memCacheWidth: decodeWidth(context, width),
    ),
  );
}

/// Thin progress bar in the current accent over a faint track. Always
/// fills the width it's given, so the track shows how far there is to go.
class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.fraction,
    this.height = 3,
    this.color,
    this.trackAlpha = 0.24,
  });

  final double fraction;
  final double height;

  /// Defaults to the accent.
  final Color? color;

  /// Opacity of the Lamp track.
  final double trackAlpha;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: height,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: ColoredBox(
        color: KColors.lamp.withValues(alpha: trackAlpha),
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: fraction.clamp(0.02, 1),
          heightFactor: 1,
          child: ColoredBox(color: color ?? KinoraTint.of(context)),
        ),
      ),
    ),
  );
}

/// Year, length and rating, separated by space and weight (never dots).
class FactLine extends StatelessWidget {
  const FactLine({super.key, required this.meta, this.certification});

  final MetaPreview meta;

  /// Age rating ("TV-MA"), shown in a thin outline.
  final String? certification;

  @override
  Widget build(BuildContext context) {
    final strong = KType.tabular(
      KType.label.copyWith(fontWeight: FontWeight.w700),
    );
    final soft = KType.tabular(KType.label.copyWith(color: KColors.haze));
    final length = lengthLabel(meta);
    final rating = meta.imdbRating;
    return Wrap(
      spacing: KSpace.x4,
      runSpacing: KSpace.x1,
      children: [
        if (meta.releaseInfo case final year? when year.isNotEmpty)
          Text(year, style: strong),
        if (certification != null)
          Text(
            certification!,
            style: soft.copyWith(fontWeight: FontWeight.w600),
            semanticsLabel: 'Rated $certification',
          ),
        if (length != null) Text(length, style: soft),
        if (rating != null && rating.isNotEmpty)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: rating, style: strong),
                TextSpan(text: ' IMDb', style: soft),
              ],
            ),
            semanticsLabel: 'Rated $rating on IMDb',
          ),
      ],
    );
  }
}

/// "2h 10m" for movies, "3 seasons" for shows; null when unknown.
String? lengthLabel(MetaPreview meta) {
  if (meta is! MetaDetail) return null;
  final seasons = {
    for (final v in meta.videos)
      if ((v.season ?? 0) > 0) v.season,
  }.length;
  if (seasons > 0) return seasons == 1 ? '1 season' : '$seasons seasons';
  final minutes = runtimeMinutes(meta.runtime);
  if (minutes != null) return Fmt.duration(Duration(minutes: minutes));
  return meta.runtime;
}

/// Minutes from addon runtimes: "49 min", "2h 10min", "1h", "130".
int? runtimeMinutes(String? runtime) {
  if (runtime == null) return null;
  final h = RegExp(r'(\d+)\s*h').firstMatch(runtime);
  final m = RegExp(r'(\d+)\s*m').firstMatch(runtime);
  if (h == null && m == null) return int.tryParse(runtime.trim());
  return int.parse(h?.group(1) ?? '0') * 60 + int.parse(m?.group(1) ?? '0');
}

/// The title's logo art, or its name in marquee type when there's none (or
/// it fails to load). Reserves its box so nothing jumps when it arrives.
class TitleLogo extends StatelessWidget {
  const TitleLogo({
    super.key,
    required this.name,
    required this.logo,
    this.maxWidth = 260,
    this.height = 96,
  });

  final String name;
  final String? logo;
  final double maxWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      style: KType.hero,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      textDirection: contentDir(name),
    );
    final image = artworkProvider(logo);
    if (image == null) return text;
    return SizedBox(
      width: maxWidth,
      height: height,
      child: Image(
        image: ResizeImage.resizeIfNeeded(
          decodeWidth(context, maxWidth),
          null,
          image,
        ),
        semanticLabel: name,
        fit: BoxFit.contain,
        alignment: Alignment.bottomLeft,
        frameBuilder: (_, child, frame, sync) =>
            frame == null && !sync ? const SizedBox.shrink() : child,
        errorBuilder: (_, _, _) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomLeft,
          child: text,
        ),
      ),
    );
  }
}

/// Keeps the status bar readable over bright artwork.
class TopShade extends StatelessWidget {
  const TopShade({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: IgnorePointer(
      child: SizedBox(
        height: MediaQuery.paddingOf(context).top + 72,
        width: double.infinity,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x99000000), Color(0x00000000)],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Text clipped to [maxLines] that opens fully on tap.
class ExpandableText extends StatefulWidget {
  const ExpandableText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 3,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      expanded: _open,
      onTapHint: _open ? 'Show less' : 'Show more',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _open = !_open),
        child: AnimatedSize(
          duration: reduce ? Duration.zero : KMotion.base,
          curve: KMotion.curve,
          alignment: Alignment.topLeft,
          child: Text(
            widget.text,
            style: widget.style,
            textDirection: contentDir(widget.text),
            maxLines: _open ? null : widget.maxLines,
            overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Soft shade at the foot of a still so its progress line reads.
const stillShade = DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0.5, 1],
      colors: [Color(0x00000000), Color(0x99000000)],
    ),
  ),
);
