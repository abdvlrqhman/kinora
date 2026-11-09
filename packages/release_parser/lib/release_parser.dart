/// Parses torrent / debrid release names and Stremio addon stream texts
/// into structured metadata ([ParsedRelease]).
library;

export 'src/addon_stream.dart' show parseAddonStream;
export 'src/enums.dart';
export 'src/episode_match.dart' show coversEpisode;
export 'src/languages.dart' show languageName;
export 'src/parsed_release.dart' show ParsedRelease;
export 'src/parser.dart' show parseRelease;
