import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/artwork.dart';
import '../../ui/widgets/media.dart';
import '../home/rows.dart';
import '../settings/widgets/settings_ui.dart';
import '../../services/tmdb.dart';

/// The cast with their photos (from TMDB).
class CastRow extends StatelessWidget {
  const CastRow({super.key, required this.people});

  final List<TmdbPerson> people;

  static const _photo = 76.0;

  @override
  Widget build(BuildContext context) => RowSection(
    title: 'Cast',
    // Photo, gap, two lines of name and one of role, at the reader's text
    // size.
    height: _photo + 14 + MediaQuery.textScalerOf(context).scale(16) * 3,
    itemWidth: _photo + 12,
    itemCount: people.length,
    itemBuilder: (context, i) {
      final p = people[i];
      return Semantics(
        label: p.role == null ? p.name : '${p.name} as ${p.role}',
        excludeSemantics: true,
        child: Column(
          children: [
            ClipOval(
              child: SizedBox.square(
                dimension: _photo,
                child: p.photo == null
                    // No photo: their initials, centered.
                    ? ColoredBox(
                        color: KColors.seat,
                        child: Center(
                          child: Text(
                            p.name
                                .split(RegExp(r'\s+'))
                                .where((w) => w.isNotEmpty)
                                .take(2)
                                .map((w) => w[0])
                                .join(),
                            style: KType.h2.copyWith(color: KColors.haze),
                          ),
                        ),
                      )
                    : Artwork(
                        url: p.photo,
                        fallbackText: p.name,
                        memCacheWidth: decodeWidth(context, _photo),
                      ),
              ),
            ),
            const SizedBox(height: KSpace.x2),
            Text(
              p.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: KType.small.copyWith(color: KColors.lamp),
            ),
            if (p.role != null)
              Text(
                p.role!,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: KType.small,
              ),
          ],
        ),
      );
    },
  );
}

/// "More like this": TMDB's recommendations as posters. Opening one looks
/// up its IMDb id, which the sources use.
class SimilarRow extends ConsumerStatefulWidget {
  const SimilarRow({super.key, required this.titles});

  final List<TmdbSimilar> titles;

  @override
  ConsumerState<SimilarRow> createState() => _SimilarRowState();
}

class _SimilarRowState extends ConsumerState<SimilarRow> {
  /// The title being looked up; taps wait for it.
  int? _opening;

  Future<void> _open(TmdbSimilar s) async {
    if (_opening != null) return;
    setState(() => _opening = s.id);
    String? imdb;
    String? problem;
    try {
      final key = await ref.read(tmdbKeyProvider.future);
      if (key != null) {
        imdb = await TmdbClient(
          key,
          ref.read(httpClientProvider),
        ).imdbId(s.id, s.type);
      }
      if (imdb == null) {
        problem = 'Kinora couldn’t find ${s.name} in your sources.';
      }
    } on Object {
      problem = 'Couldn’t reach TMDB. Check your connection, then try again.';
    }
    if (!mounted) return;
    setState(() => _opening = null);
    if (problem != null) {
      showNote(context, problem);
    } else {
      openTitle(context, type: s.type, id: imdb!);
    }
  }

  @override
  Widget build(BuildContext context) => RowSection(
    title: 'More like this',
    height: PosterSize.height,
    itemWidth: PosterSize.width,
    itemCount: widget.titles.length,
    itemBuilder: (context, i) {
      final s = widget.titles[i];
      return AnimatedOpacity(
        opacity: _opening == s.id ? 0.5 : 1,
        duration: KMotion.base,
        child: PosterTile(
          name: s.name,
          poster: s.poster,
          onTap: () => unawaited(_open(s)),
        ),
      );
    },
  );
}
