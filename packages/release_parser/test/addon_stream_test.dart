import 'package:release_parser/release_parser.dart';
import 'package:test/test.dart';

// Stream texts as returned by the public addons (Torrentio and its fork
// Knightcrawler, Comet, MediaFusion, StremThru, Jackettio, Peerflix, Orion).
void main() {
  group('Torrentio / Knightcrawler', () {
    test('movie with flags line', () {
      final r = parseAddonStream(
        name: 'Torrentio\n4k DV | HDR',
        title:
            'Movie.2024.2160p.WEB-DL.DDP5.1.DV.HDR.H.265-GROUP\n'
            '👤 245 💾 15.2 GB ⚙️ ThePirateBay\n'
            'Multi Audio / 🇬🇧 / 🇫🇷',
      );
      expect(r.raw, 'Movie.2024.2160p.WEB-DL.DDP5.1.DV.HDR.H.265-GROUP');
      expect(r.title, 'Movie');
      expect(r.resolution, Resolution.p2160);
      expect(r.hdr, {HdrFormat.dolbyVision, HdrFormat.hdr10});
      expect(r.seeders, 245);
      expect(r.sizeBytes, (15.2 * 1024 * 1024 * 1024).round());
      expect(r.provider, 'ThePirateBay');
      expect(r.languages, {'en', 'fr'});
      expect(r.multiAudio, isTrue);
      expect(r.debridCached, isNull);
    });

    test('pack: file line wins, torrent title fills the gaps', () {
      final r = parseAddonStream(
        name: '[RD+] Torrentio\n720p',
        title:
            'Black Snow 2023 S01-S02 720p WEB-DL HEVC x265 BONE\n'
            'Black Snow 2023 S01E02 720p WEB-DL HEVC x265 BONE.mkv\n'
            '👤 89 💾 410.26 MB ⚙️ TorrentGalaxy',
      );
      expect(r.seasons, [1]);
      expect(r.episodes, [2]);
      expect(r.isSeasonPack, isFalse);
      expect(r.container, 'mkv');
      expect(r.debridCached, isTrue);
      expect(r.sizeBytes, (410.26 * 1024 * 1024).round());
    });

    test('pack file named only by number takes season from torrent title', () {
      final r = parseAddonStream(
        name: 'Torrentio\n1080p',
        title:
            'Show.Name.S03.1080p.BluRay.x264-ROVERS\n'
            'Show.Name.S03.1080p.BluRay.x264-ROVERS/05.mkv\n'
            '👤 12 💾 1.1 GB ⚙️ 1337x',
      );
      expect(r.raw, '05.mkv');
      expect(r.title, 'Show Name');
      expect(r.seasons, [3]);
      expect(r.isSeasonPack, isTrue);
      expect(r.source, Source.bluray);
      expect(r.provider, '1337x');
    });

    test('behaviorHints.filename beats the title text', () {
      final r = parseAddonStream(
        name: 'Torrentio\n1080p',
        title:
            'X-Men Complete 13 Movie Collection Sci-Fi 2000 - 2020 Eng Rus Multi-Subs 1080p [H264-mp4]\n'
            'X-Men Complete 13 Movie Collection 2000-2020/08 Deadpool - Action 2016 Eng Rus Multi-Subs 1080p [H264-mp4].mp4\n'
            '👤 20 💾 3.65 GB ⚙️ TorrentGalaxy\n'
            'Multi Subs / 🇬🇧 / 🇷🇺 / 🇫🇮',
        filename:
            '08 Deadpool - Action 2016 Eng Rus Multi-Subs 1080p [H264-mp4].mp4',
      );
      expect(r.year, 2016);
      expect(r.container, 'mp4');
      expect(r.languages, containsAll(['en', 'ru', 'fi']));
      expect(r.multiAudio, isFalse);
    });

    test('dual audio line and uncached debrid', () {
      final r = parseAddonStream(
        name: '[RD download] Torrentio\n720p',
        title:
            'Deadpool (2016) 720p BluRay x264 [Dual Audio] [Hindi (Line Audio) - English] ESubs - Downloadhub\n'
            '👤 3 💾 934.8 MB ⚙️ 1337x\n'
            'Dual Audio / 🇬🇧 / 🇮🇳',
      );
      expect(r.dualAudio, isTrue);
      expect(r.languages, {'hi', 'en'});
      expect(r.debridCached, isFalse);
      expect(r.seeders, 3);
    });

    test('Knightcrawler uses the Torrentio layout', () {
      final r = parseAddonStream(
        name: 'Knightcrawler\n1080p',
        title:
            'Dune.Part.Two.2024.1080p.WEB-DL.DDP5.1.Atmos.H.264-FLUX\n'
            '👤 1500 💾 6.4 GB ⚙️ TorrentGalaxy',
      );
      expect(r.title, 'Dune Part Two');
      expect(r.seeders, 1500);
      expect(r.atmos, isTrue);
    });
  });

  group('Comet', () {
    test('emoji description', () {
      final r = parseAddonStream(
        name: '[PM⚡] Comet 2160p',
        description:
            '📄 The.Matrix.1999.2160p.UHD.BluRay.REMUX.HDR.HEVC.Atmos-EPSiLON\n'
            '📹 HEVC • HDR • 10bit | 🔊 Atmos • TrueHD • 7.1\n'
            '⭐ BluRay • REMUX | 🏷️ EPSiLON\n'
            '👤 45 💾 58.3 GB 🔎 Comet|TorrentGalaxy\n'
            '🇬🇧/🇫🇷',
      );
      expect(r.title, 'The Matrix');
      expect(r.source, Source.remux);
      expect(r.audioCodecs, [AudioCodec.trueHd]);
      expect(r.channels, '7.1');
      expect(r.bitDepth, 10);
      expect(r.provider, 'TorrentGalaxy');
      expect(r.languages, {'en', 'fr'});
      expect(r.debridCached, isTrue);
    });

    test('older layout with scraper prefix', () {
      final r = parseAddonStream(
        name: '[TORRENT🧲] Comet 1080p',
        description:
            'Black Snow S01 MULTi HDR 2160p WEB H265-BraD\n'
            '💿 WEB|HDR|hevc|BraD\n'
            '👤 0 💾 27.93 GB 🔎 MediaFusion|Zilean DMM',
      );
      expect(r.seasons, [1]);
      expect(r.isSeasonPack, isTrue);
      expect(r.resolution, Resolution.p2160);
      expect(r.seeders, 0);
      expect(r.provider, 'Zilean DMM');
      expect(r.debridCached, isNull);
    });

    test('plain-text layout', () {
      final r = parseAddonStream(
        name: '[RD⬇️] Comet 1080p',
        description:
            'Arabic.Series.S01E02.1080p.WEB-DL.AAC2.0.H.264\n'
            'Seeders: 12\nSize: 1.2 GB\nSource: Comet|EZTV\nLanguages: ar',
      );
      expect(r.title, 'Arabic Series');
      expect(r.languages, {'ar'});
      expect(r.seeders, 12);
      expect(r.sizeBytes, (1.2 * 1024 * 1024 * 1024).round());
      expect(r.provider, 'EZTV');
      expect(r.debridCached, isFalse);
    });
  });

  group('MediaFusion', () {
    test('cached with filename hint', () {
      final r = parseAddonStream(
        name: 'MediaFusion | ElfHosted 🧲 RD ⚡️ 2160P',
        description: '🎨 DV|HDR 📺 BluRay REMUX 🎞️ hevc \n📦 35.09 GB \n🌐 English + Italian\n🔗 Torlock',
        filename:
            'Deadpool.2016.4K.HDR.DV.2160p.BDRemux Ita Eng x265-NAHOM.mkv',
      );
      expect(r.title, 'Deadpool');
      expect(r.source, Source.remux);
      expect(r.languages, {'en', 'it'});
      expect(r.provider, 'Torlock');
      expect(r.debridCached, isTrue);
      expect(r.group, 'NAHOM');
    });

    test('no release name: everything from the metadata lines', () {
      final r = parseAddonStream(
        name: 'MediaFusion | ElfHosted 🧲 P2P ⏳ 1080P',
        description: '📺 BluRay 🎞️ avc 🎵 Dolby Digital \n📦 2.43 GB / 33.48 GB \n🌐 English\n🔗 Zilean DMM',
      );
      expect(r.title, '');
      expect(r.resolution, Resolution.p1080);
      expect(r.source, Source.bluray);
      expect(r.videoCodec, VideoCodec.h264);
      expect(r.audioCodecs, [AudioCodec.ac3]);
      expect(r.languages, {'en'});
      expect(r.sizeBytes, (2.43 * 1024 * 1024 * 1024).round());
      expect(r.debridCached, isFalse);
    });
  });

  test('StremThru: group after ⚙️, indexer after 🔍, subtitle flags', () {
    final r = parseAddonStream(
      name: '⚡️ [RD]\nStremThru Torz\n1080p',
      description:
          '💿 WEB-DL 🎞️ HEVC\n📺 HDR10 🎧 DD+ | 5.1\n💾 1.2 GB 📦 14.8 GB 👤 52\n'
          '🌐 🇬🇧 🇸🇦\n💬 🇫🇷\n⚙️ FLUX 🔍 TorrentGalaxy\n'
          '📄 Show.S01E03.1080p.WEB-DL.DDP5.1.HDR.HEVC.mkv',
    );
    expect(r.raw, 'Show.S01E03.1080p.WEB-DL.DDP5.1.HDR.HEVC.mkv');
    expect(r.group, 'FLUX');
    expect(r.provider, 'TorrentGalaxy');
    expect(r.sizeBytes, (1.2 * 1024 * 1024 * 1024).round());
    expect(r.languages, {'en', 'ar'});
    expect(r.subtitleLanguages, {'fr'});
    expect(r.seeders, 52);
  });

  test('Jackettio', () {
    final r = parseAddonStream(
      name: '[RD+] Jackettio 1080p',
      title:
          'Show S01 1080p WEB-DL x264\nShow.S01E04.1080p.WEB-DL.x264.mkv\n'
          '💾1.4 GB 👥120 ⚙️YggTorrent 🇫🇷 🇬🇧',
    );
    expect(r.episodes, [4]);
    expect(r.seeders, 120);
    expect(r.provider, 'YggTorrent');
    expect(r.languages, {'fr', 'en'});
    expect(r.debridCached, isTrue);
  });

  test('Orion: spaced channels, 👂 language codes, ☁️ provider', () {
    final r = parseAddonStream(
      name: '🚀 ORION\n[Offcloud]',
      title:
          'Reacher S03E07 L A Story 2160p AMZN WEB-DL DDP5 1 Atmos DV HDR H 265-FLUX mkv\n'
          '📺4K 💾5.31 GB 🎥h265 🔊5.1\n👂EN ☁️torrentscsv',
    );
    expect(r.title, 'Reacher');
    expect(r.channels, '5.1');
    expect(r.videoCodec, VideoCodec.h265);
    expect(r.container, 'mkv');
    expect(r.languages, {'en'});
    expect(r.provider, 'torrentscsv');
  });

  test('Peerflix: provider after 🌐, flag in the name', () {
    final r = parseAddonStream(
      name: '[RD download] Peerflix 🇪🇸 4K',
      title:
          'Deadpool [4K UHD 2160p HEVC X265][DTS 5.1 Castellano DTS 5.1-Ingles+Subs][ES-EN]\n'
          '  👤 1 💾 20.38 GB 🌐 Peerflix',
    );
    expect(r.provider, 'Peerflix');
    expect(r.languages, {'es', 'en'});
    expect(r.debridCached, isFalse);
  });

  test('empty stream', () {
    final r = parseAddonStream();
    expect(r.title, '');
    expect(r.sizeBytes, isNull);
    expect(r.seeders, isNull);
    expect(r.provider, isNull);
  });

  test('size units', () {
    int? size(String s) => parseAddonStream(title: 'X\n💾 $s').sizeBytes;
    expect(size('512 B'), 512);
    expect(size('2 KB'), 2048);
    expect(size('1,5 GB'), (1.5 * 1024 * 1024 * 1024).round());
    expect(size('1 TB'), 1024 * 1024 * 1024 * 1024);
    expect(size('700 MiB'), 700 * 1024 * 1024);
  });
}
