import 'json.dart';

/// A subtitle file offered by a subtitles addon (Subtitles Object).
final class SubtitleItem {
  /// Creates a subtitle.
  const SubtitleItem({
    required this.id,
    required this.url,
    required this.lang,
    this.label,
  });

  /// Parses a Subtitles Object; returns null without `url` or `lang`.
  /// A missing `id` falls back to the URL.
  static SubtitleItem? tryParse(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final url = readString(value, 'url');
    final lang = readString(value, 'lang');
    if (url == null || lang == null) return null;
    return SubtitleItem(
      id: readString(value, 'id') ?? url,
      url: url,
      lang: lang,
      label: readString(value, 'label'),
    );
  }

  /// Unique id within the addon.
  final String id;

  /// Subtitle file URL.
  final String url;

  /// Language: ISO 639-2 code (`eng`) or free text.
  final String lang;

  /// Optional picker label (`English [CC]`).
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is SubtitleItem &&
      other.id == id &&
      other.url == url &&
      other.lang == lang &&
      other.label == label;

  @override
  int get hashCode => Object.hash(id, url, lang, label);

  @override
  String toString() => 'SubtitleItem($lang, $id)';
}
