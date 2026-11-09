import 'package:xml/xml.dart';

final _invalidXmlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F￾￿]');

/// Escapes all five XML special characters (safe in text and in
/// double- or single-quoted attributes) and drops characters XML 1.0 forbids.
///
/// `>` and `"` are escaped too even where XML would allow them raw: embedded
/// renderer stacks are picky, and DIDL-Lite is double-escaped inside SOAP.
String escapeXml(String input) => input
    .replaceAll(_invalidXmlChars, '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Namespace-agnostic helpers: UPnP devices are inconsistent with prefixes,
/// so elements are matched by local name only.
extension LocalNames on XmlElement {
  /// Direct children whose local name is [name].
  Iterable<XmlElement> childrenNamed(String name) =>
      childElements.where((e) => e.name.local == name);

  /// The first direct child named [name], or null.
  XmlElement? childNamed(String name) => childrenNamed(name).firstOrNull;

  /// Trimmed text of the first direct child named [name]; null when missing
  /// or blank.
  String? childText(String name) {
    final text = childNamed(name)?.innerText.trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// All descendants whose local name is [name], in document order.
  Iterable<XmlElement> descendantsNamed(String name) =>
      descendantElements.where((e) => e.name.local == name);
}
