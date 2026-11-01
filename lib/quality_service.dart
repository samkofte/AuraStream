import 'dart:async';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class VideoQualityOption {
  final String label; // "4K (2160p)", "1440p", "1080p", "720p", "480p", "360p"
  final VideoStreamInfo videoStream;
  final AudioStreamInfo? audioStream;
  final bool isMuxed; // True if it already contains audio (e.g. 360p tag 18)
  final int totalBytes;

  VideoQualityOption({
    required this.label,
    required this.videoStream,
    this.audioStream,
    required this.isMuxed,
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
  final String label; // "Yüksek Kalite (160 kbps)", "Standart (128 kbps)"
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

  /// Returns sorted list of available video quality options (from 4K down to 360p)
  static Future<List<VideoQualityOption>> getVideoQualities(String videoId) async {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    final audioStream = manifest.audioOnly.isNotEmpty
        ? manifest.audioOnly.withHighestBitrate()
        : null;

    final Map<String, VideoQualityOption> qualityMap = {};

    // 1. Process adaptive video streams (4K, 1440p, 1080p, 720p, 480p, 360p)
    final sortedVideo = manifest.videoOnly.sortByVideoQuality();
    for (final v in sortedVideo) {
      final res = v.videoResolution.height;
      String label;
      if (res >= 2160) {
        label = '4K Ultra HD (2160p)';
      } else if (res >= 1440) {
        label = '2K Quad HD (1440p)';
      } else if (res >= 1080) {
        label = 'Full HD (1080p)';
      } else if (res >= 720) {
        label = 'HD (720p)';
      } else if (res >= 480) {
        label = 'SD (480p)';
      } else {
        label = '${res}p';
      }

      // MP4 container preferred for wider ExoPlayer and FFmpeg compatibility
      if (!qualityMap.containsKey(label) || v.container.name == 'mp4') {
        final audioBytes = audioStream?.size.totalBytes ?? 0;
        qualityMap[label] = VideoQualityOption(
          label: label,
          videoStream: v,
          audioStream: audioStream,
          isMuxed: false,
          totalBytes: v.size.totalBytes + audioBytes,
        );
      }
    }

    // 2. Add muxed streams as fallback / quick option
    for (final m in manifest.muxed) {
      final label = '${m.qualityLabel} (Hızlı İzle)';
      if (!qualityMap.containsKey(label)) {
        qualityMap[label] = VideoQualityOption(
          label: label,
          videoStream: m,
          audioStream: null,
          isMuxed: true,
          totalBytes: m.size.totalBytes,
        );
      }
    }

    return qualityMap.values.toList();
  }

  /// Returns available audio quality options
  static Future<List<AudioQualityOption>> getAudioQualities(String videoId) async {
    final manifest = await yt.videos.streamsClient.getManifest(videoId);
    final audioList = manifest.audioOnly.toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));

    final List<AudioQualityOption> options = [];
    for (final a in audioList) {
      final kbps = a.bitrate.kiloBitsPerSecond.round();
      final label = '$kbps kbps (${a.container.name.toUpperCase()})';
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
