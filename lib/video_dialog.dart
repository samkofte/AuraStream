import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class ModernVideoPlayerDialog extends StatefulWidget {
  final String title;
  final String source;
  final bool isLocalFile;
  final VoidCallback? onPlayAudioBackground;

  const ModernVideoPlayerDialog({
    super.key,
    required this.title,
    required this.source,
    required this.isLocalFile,
    this.onPlayAudioBackground,
  });

  @override
  State<ModernVideoPlayerDialog> createState() => _ModernVideoPlayerDialogState();
}

class _ModernVideoPlayerDialogState extends State<ModernVideoPlayerDialog> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      if (widget.isLocalFile) {
        _controller = VideoPlayerController.file(io.File(widget.source));
      } else {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.source),
          httpHeaders: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        );
      }

      await _controller.initialize();
      _controller.play();
      _controller.addListener(() {
        if (mounted) setState(() {});
      });
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
    if (_isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    if (_isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _isInitialized ? _controller.value.aspectRatio : 16 / 9,
                child: _isInitialized ? VideoPlayer(_controller) : const SizedBox.shrink(),
              ),
            ),
            _buildControlsOverlay(isFullScreen: true),
          ],
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child: Center(
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF101016),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.85),
                blurRadius: 30,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Başlık Çubuğu
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF181824),
                    border: Border(bottom: BorderSide(color: Colors.white10)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.videocam_rounded,
                            color: Color(0xFF00E5FF), size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      // Arka Planda Sesi Çal
                      if (widget.onPlayAudioBackground != null)
                        IconButton(
                          icon: const Icon(Icons.headset_rounded, color: Color(0xFF1DB954), size: 20),
                          tooltip: 'Arka Planda Dinle',
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onPlayAudioBackground!();
                          },
                        ),
                      // Kapat Butonu
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white70, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.of(context).pop(),
                      )
                    ],
                  ),
                ),

                // Video Alanı
                AspectRatio(
                  aspectRatio: _isInitialized
                      ? _controller.value.aspectRatio
                      : 16 / 9,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_isInitialized) VideoPlayer(_controller),
                      if (!_isInitialized && !_hasError)
                        const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF00E5FF),
                            strokeWidth: 2.5,
                          ),
                        ),
                      if (_hasError)
                        const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline,
                                  color: Colors.redAccent, size: 36),
                              SizedBox(height: 8),
                              Text('Video yüklenemedi',
                                  style: TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                      _buildControlsOverlay(isFullScreen: false),
                    ],
                  ),
                ),

                // Video İlerleme & Süre Çubuğu
                if (_isInitialized)
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                    color: const Color(0xFF14141E),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          colors: const VideoProgressColors(
                            playedColor: Color(0xFF00E5FF),
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.white10,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(_controller.value.position),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11.5),
                            ),
                            Text(
                              _formatDuration(_controller.value.duration),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11.5),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlsOverlay({required bool isFullScreen}) {
    if (!_isInitialized) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        setState(() => _showControls = !_showControls);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        color: _showControls ? Colors.black.withValues(alpha: 0.45) : Colors.transparent,
        child: _showControls
            ? Stack(
                children: [
                  // Ortadaki Oynatma Kontrolleri
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.replay_10_rounded,
                              color: Colors.white, size: 32),
                          onPressed: () {
                            final current = _controller.value.position;
                            _controller.seekTo(current - const Duration(seconds: 10));
                          },
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _controller.value.isPlaying
                                  ? _controller.pause()
                                  : _controller.play();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Color(0xFF00E5FF),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _controller.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 32,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.forward_10_rounded,
                              color: Colors.white, size: 32),
                          onPressed: () {
                            final current = _controller.value.position;
                            _controller.seekTo(current + const Duration(seconds: 10));
                          },
                        ),
                      ],
                    ),
                  ),
                  // Sağ alt: Tam Ekran / Ekran Döndürme Butonu
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: IconButton(
                      icon: Icon(
                        isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      tooltip: isFullScreen ? 'Küçült' : 'Tam Ekran & Döndür',
                      onPressed: _toggleFullScreen,
                    ),
                  ),
                ],
              )
            : const SizedBox.expand(),
      ),
    );
  }
}
