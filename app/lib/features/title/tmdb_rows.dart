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
    height: _photo + 62,
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
                child: Artwork(
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
class SimilarRow extends ConsumerWidget {
  const SimilarRow({super.key, required this.titles});

  final List<TmdbSimilar> titles;

  Future<void> _open(BuildContext context, WidgetRef ref, TmdbSimilar s) async {
    final key = await ref.read(tmdbKeyProvider.future);
    if (key == null) return;
    String? imdb;
    try {
      imdb = await TmdbClient(
        key,
        ref.read(httpClientProvider),
      ).imdbId(s.id, s.type);
    } on Object {
      imdb = null;
    }
    if (!context.mounted) return;
    if (imdb == null) {
      showNote(
        context,
        'Kinora can’t open ${s.name}: your sources need an IMDb id.',
      );
      return;
    }
    openTitle(context, type: s.type, id: imdb);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => RowSection(
    title: 'More like this',
    height: PosterSize.height,
    itemWidth: PosterSize.width,
    itemCount: titles.length,
    itemBuilder: (context, i) {
      final s = titles[i];
      return PosterTile(
        name: s.name,
        poster: s.poster,
        onTap: () => _open(context, ref, s),
      );
    },
  );
}
