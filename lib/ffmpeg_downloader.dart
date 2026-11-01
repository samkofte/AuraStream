import 'dart:async';
import 'dart:io' as io;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'quality_service.dart';

class LocalFFmpegDownloader {
  /// Android YouTube Client headers to avoid 403 Forbidden on adaptive video/audio streams
  static const Map<String, String> defaultHeaders = {
    'User-Agent': 'com.google.android.youtube/19.29.35 (Linux; U; Android 14) gzip',
    'Accept': '*/*',
  };

  /// Download a stream to a local file with live progress tracking
  static Future<void> downloadStreamToFile({
    required Uri streamUrl,
    required io.File destinationFile,
    required int totalBytes,
    required void Function(double progress) onProgress,
    Completer<void>? cancelCompleter,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', streamUrl);
      req.headers.addAll(defaultHeaders);

      final resp = await client.send(req);
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw Exception('Akış indirilemedi (HTTP ${resp.statusCode})');
      }

      final sink = destinationFile.openWrite();
      int received = 0;

      final subscription = resp.stream.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (totalBytes > 0) {
            onProgress(received / totalBytes);
          }
        },
        onError: (err) {
          sink.close();
          throw err;
        },
        cancelOnError: true,
      );

      if (cancelCompleter != null) {
        cancelCompleter.future.then((_) {
          subscription.cancel();
          sink.close();
        });
      }

      await subscription.asFuture();
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
  }

  /// Downloads both Video and Audio streams, then merges them with FFmpeg into a single high-quality MP4 file.
  static Future<String> downloadAndMergeHighQualityVideo({
    required VideoQualityOption option,
    required String videoTitle,
    required io.Directory outputDirectory,
    required void Function(String stageText, double progress) onOverallProgress,
  }) async {
    final sanitizedTitle = videoTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final finalFilePath = '${outputDirectory.path}/$sanitizedTitle [${option.label}].mp4';
    final tempDir = await getTemporaryDirectory();

    // 1. If the stream is already muxed (e.g. 360p/720p progressive), direct download
    if (option.isMuxed || option.audioStream == null) {
      onOverallProgress('Video indiriliyor...', 0.05);
      final finalFile = io.File(finalFilePath);
      await downloadStreamToFile(
        streamUrl: option.videoStream.url,
        destinationFile: finalFile,
        totalBytes: option.videoStream.size.totalBytes,
        onProgress: (p) => onOverallProgress('Video indiriliyor...', p),
      );
      return finalFilePath;
    }

    // 2. Adaptive (1080p, 1440p, 4K) -> Download video temp and audio temp
    final tempVideoPath = '${tempDir.path}/temp_vid_${DateTime.now().millisecondsSinceEpoch}.${option.videoStream.container.name}';
    final tempAudioPath = '${tempDir.path}/temp_aud_${DateTime.now().millisecondsSinceEpoch}.${option.audioStream!.container.name}';

    final tempVideoFile = io.File(tempVideoPath);
    final tempAudioFile = io.File(tempAudioPath);

    try {
      // Step A: Download Video Track (weighted 70% of total progress)
      onOverallProgress('Görüntü akışı indiriliyor (${option.label})...', 0.05);
      await downloadStreamToFile(
        streamUrl: option.videoStream.url,
        destinationFile: tempVideoFile,
        totalBytes: option.videoStream.size.totalBytes,
        onProgress: (p) => onOverallProgress('Görüntü indiriliyor (${(p * 100).toInt()}%)...', p * 0.70),
      );

      // Step B: Download Audio Track (weighted 20% of total progress)
      onOverallProgress('Yüksek kalite ses indiriliyor...', 0.70);
      await downloadStreamToFile(
        streamUrl: option.audioStream!.url,
        destinationFile: tempAudioFile,
        totalBytes: option.audioStream!.size.totalBytes,
        onProgress: (p) => onOverallProgress('Ses indiriliyor (${(p * 100).toInt()}%)...', 0.70 + (p * 0.20)),
      );

      // Step C: Merge with FFmpeg locally on device (Remaining 10%)
      onOverallProgress('FFmpeg ile yüksek kalite birleştiriliyor...', 0.92);
      
      // Fast remux: -c copy if compatible, or transcode audio to aac for pristine MP4
      final isAudioAac = option.audioStream!.container.name == 'mp4';
      final audioCodecParam = isAudioAac ? '-c:a copy' : '-c:a aac -b:a 192k';
      final ffmpegCmd = '-y -i "$tempVideoPath" -i "$tempAudioPath" -c:v copy $audioCodecParam -map 0:v:0 -map 1:a:0 -shortest "$finalFilePath"';

      debugPrint('Executing FFmpeg command: $ffmpegCmd');
      final session = await FFmpegKit.execute(ffmpegCmd);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        onOverallProgress('✓ Tamamlandı!', 1.0);
        return finalFilePath;
      } else {
        final logs = await session.getAllLogsAsString();
        debugPrint('FFmpeg Error Logs:\n$logs');
        throw Exception('FFmpeg birleştirme hatası: $returnCode');
      }
    } finally {
      // Clean up temporary files
      try {
        if (tempVideoFile.existsSync()) await tempVideoFile.delete();
        if (tempAudioFile.existsSync()) await tempAudioFile.delete();
      } catch (_) {}
    }
  }
}
