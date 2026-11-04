import 'dart:async';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class VideoQualityOption {
  final String label;
  final VideoStreamInfo videoStream;
  final int totalBytes;

  VideoQualityOption({
    required this.label,
    required this.videoStream,
    required this.totalBytes,
  });

  String get sizeText {
    final mb = totalBytes / (1024 * 1024);
    if (mb >= 1000) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class AudioQualityOption {
  final String label;
  final AudioStreamInfo audioStream;
  final int totalBytes;

  AudioQualityOption({
    required this.label,
    required this.audioStream,
    required this.totalBytes,
  });

  String get sizeText {
    final mb = totalBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class QualityService {
  static final yt = YoutubeExplode();

  /// Doğrudan cihazda çalışan, dönüşüm ve FFmpeg gerektirmeyen hazır video akışları
  static Future<List<VideoQualityOption>> getVideoQualities(String videoId) async {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    final List<VideoQualityOption> list = [];

    // 1. Muxed (Hem ses hem görüntü içeren tek parça saf MP4 akışları - En hızlı ve stabil)
    for (final m in manifest.muxed) {
      list.add(VideoQualityOption(
        label: '${m.qualityLabel} HD Video',
        videoStream: m,
        totalBytes: m.size.totalBytes,
      ));
    }

    // 2. Alternatif olarak en yüksek video akışı
    if (list.isEmpty) {
      for (final v in manifest.videoOnly.sortByVideoQuality().take(3)) {
        list.add(VideoQualityOption(
          label: '${v.videoResolution.height}p Video',
          videoStream: v,
          totalBytes: v.size.totalBytes,
        ));
      }
    }

    return list;
  }

  /// Doğrudan YouTube sunucusundaki saf M4A ve AAC ses akışları
  static Future<List<AudioQualityOption>> getAudioQualities(String videoId) async {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    final audioList = manifest.audioOnly.toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));

    final List<AudioQualityOption> options = [];
    for (final a in audioList) {
      final kbps = a.bitrate.kiloBitsPerSecond.round();
      final label = '$kbps kbps (${a.container.name.toUpperCase()} Ses)';
      if (!options.any((o) => o.label.startsWith('$kbps kbps'))) {
        options.add(AudioQualityOption(
          label: label,
          audioStream: a,
          totalBytes: a.size.totalBytes,
        ));
      }
    }
    return options;
  }
}
