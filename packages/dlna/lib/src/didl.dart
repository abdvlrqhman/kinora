import 'time.dart';
import 'xml_util.dart';

/// DLNA 4th field for streamed, byte-seekable, non-transcoded media:
/// OP=01 (Range seek), CI=0, FLAGS = streaming + background + stall + DLNA 1.5.
const dlnaContentFeatures =
    'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000';

/// Response headers the stream server should send for media it serves to a
/// DLNA renderer (merge them into the HTTP response of the media URL).
///
/// Samsung TVs request subtitles by sending `getcaptionInfo.sec: 1` on the
/// media request; answer with [captionSrt] in `CaptionInfo.sec` (sending it
/// unconditionally is harmless).
Map<String, String> dlnaStreamHeaders({
  required String mimeType,
  Uri? captionSrt,
}) => {
  'Content-Type': mimeType,
  'Accept-Ranges': 'bytes',
  'contentFeatures.dlna.org': dlnaContentFeatures,
  'transferMode.dlna.org': 'Streaming',
  'CaptionInfo.sec': ?captionSrt?.toString(),
};

/// Builds the DIDL-Lite `CurrentURIMetaData` for a video item.
///
/// [minimal] drops everything optional (size, duration, poster, captions,
/// DLNA flags) for renderers that reject richer metadata.
String buildVideoDidl({
  required Uri media,
  required String title,
  required String mimeType,
  int? sizeBytes,
  Duration? duration,
  Uri? subtitleSrt,
  Uri? posterUrl,
  bool minimal = false,
}) {
  final out = StringBuffer(
    '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"',
  );
  if (!minimal && subtitleSrt != null) {
    out.write(' xmlns:sec="http://www.sec.co.kr/"');
  }
  out
    ..write('><item id="0" parentID="-1" restricted="1">')
    ..write('<dc:title>${escapeXml(title)}</dc:title>')
    ..write('<upnp:class>object.item.videoItem</upnp:class>');
  if (!minimal && posterUrl != null) {
    out.write(
      '<upnp:albumArtURI>${escapeXml('$posterUrl')}</upnp:albumArtURI>',
    );
  }
  final features = minimal ? '*' : dlnaContentFeatures;
  out.write(
    '<res protocolInfo="${escapeXml('http-get:*:$mimeType:$features')}"',
  );
  if (!minimal && sizeBytes != null) out.write(' size="$sizeBytes"');
  if (!minimal && duration != null) {
    out.write(' duration="${formatDlnaTime(duration, withMillis: true)}"');
  }
  out.write('>${escapeXml('$media')}</res>');
  if (!minimal && subtitleSrt != null) {
    final srt = escapeXml('$subtitleSrt');
    out
      ..write('<sec:CaptionInfoEx sec:type="srt">$srt</sec:CaptionInfoEx>')
      ..write('<sec:CaptionInfo sec:type="srt">$srt</sec:CaptionInfo>');
  }
  out.write('</item></DIDL-Lite>');
  return out.toString();
}
