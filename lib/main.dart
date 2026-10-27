import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

// Local Notification Plugin for Download Progress Tracking
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Background Audio Service Initialization (Only non-web for Android/iOS)
  if (!kIsWeb) {
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.aurastream.music.channel.audio',
        androidNotificationChannelName: 'AuraStream Müzik & Video Yayını',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      );

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
      );
    } catch (e) {
      debugPrint('Background audio init failed: $e');
    }
  }

  runApp(const AuraStreamApp());
}

class AuraStreamApp extends StatelessWidget {
  const AuraStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AuraStream - Hi-Fi Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F13),
        primaryColor: const Color(0xFF1DB954),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1DB954),
          secondary: Color(0xFF1ED760),
          tertiary: Color(0xFFFF2A55),
          surface: Color(0xFF181820),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class SongItem {
  final String id;
  final String title;
  final String artist;
  final String duration;
  final String thumbnailUrl;
  final String format;
  final String? localFilePath;
  final DateTime? downloadDate;

  SongItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.thumbnailUrl,
    this.format = 'MAX SES',
    this.localFilePath,
    this.downloadDate,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'duration': duration,
        'thumbnailUrl': thumbnailUrl,
        'format': format,
        'localFilePath': localFilePath,
        'downloadDate': downloadDate?.toIso8601String(),
      };

  factory SongItem.fromJson(Map<String, dynamic> json) => SongItem(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        artist: json['artist'] ?? '',
        duration: json['duration'] ?? '--:--',
        thumbnailUrl: json['thumbnailUrl'] ?? '',
        format: json['format'] ?? 'MAX SES',
        localFilePath: json['localFilePath'],
        downloadDate: json['downloadDate'] != null
            ? DateTime.tryParse(json['downloadDate'])
            : null,
      );
}

class PlaylistModel {
  final String id;
  String name;
  final List<SongItem> songs;

  PlaylistModel({
    required this.id,
    required this.name,
    required this.songs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'songs': songs.map((s) => s.toJson()).toList(),
      };

  factory PlaylistModel.fromJson(Map<String, dynamic> json) => PlaylistModel(
        id: json['id'] ?? UniqueKey().toString(),
        name: json['name'] ?? 'Yeni Çalma Listesi',
        songs: (json['songs'] as List<dynamic>?)
                ?.map((s) => SongItem.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentTabIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final yt.YoutubeExplode _ytExplode = yt.YoutubeExplode();

  List<SongItem> _downloadedSongs = [];
  List<PlaylistModel> _playlists = [];

  final List<SongItem> _queue = [];
  int _currentQueueIndex = -1;
  SongItem? _currentSong;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isShuffle = false;
  LoopMode _loopMode = LoopMode.off;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;

  // Active Download Tasks Tracking in Notification Bar
  final Map<String, double> _activeDownloadProgress = {};

  @override
  void initState() {
    super.initState();
    _initAudio();
    _loadFromStorage();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _ytExplode.close();
    super.dispose();
  }

  Future<void> _loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();

    final dlJson = prefs.getString('cached_downloads');
    if (dlJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(dlJson);
        setState(() {
          _downloadedSongs =
              decoded.map((e) => SongItem.fromJson(e)).toList();
        });
      } catch (_) {}
    }

    final plJson = prefs.getString('cached_playlists');
    if (plJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(plJson);
        setState(() {
          _playlists =
              decoded.map((e) => PlaylistModel.fromJson(e)).toList();
        });
      } catch (_) {}
    } else {
      setState(() {
        _playlists = [
          PlaylistModel(id: 'favs', name: 'Beğenilen Şarkılar', songs: [])
        ];
      });
      _savePlaylists();
    }
  }

  Future<void> _saveDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr =
        jsonEncode(_downloadedSongs.map((e) => e.toJson()).toList());
    await prefs.setString('cached_downloads', jsonStr);
  }

  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr =
        jsonEncode(_playlists.map((e) => e.toJson()).toList());
    await prefs.setString('cached_playlists', jsonStr);
  }

  void _initAudio() {
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing &&
              state.processingState != ProcessingState.completed;
          _isBuffering = state.processingState == ProcessingState.buffering ||
              (state.processingState == ProcessingState.loading && state.playing);
        });
        if (state.processingState == ProcessingState.completed) {
          _playNext();
        }
      }
    });

    _audioPlayer.positionStream.listen((pos) {
      if (mounted) {
        setState(() {
          _position = pos;
          if (pos > Duration.zero) {
            _isBuffering = false;
          }
        });
      }
    });

    _audioPlayer.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _totalDuration = dur);
    });
  }

  // Client-Side Stream Resolver (Web'de proxy, Mobilde doğrudan YouTube CDN)
  Future<String?> _resolveStreamUrl(String videoId, {bool isVideo = false}) async {
    if (kIsWeb) {
      return isVideo
          ? "http://127.0.0.1:5050/download_video_max/$videoId"
          : "http://127.0.0.1:5050/audio/$videoId";
    }
    try {
      final manifest =
          await _ytExplode.videos.streamsClient.getManifest(videoId);
      if (isVideo) {
        final videoStream = manifest.muxed.withHighestBitrate();
        return videoStream.url.toString();
      }
      final audioStream = manifest.audioOnly.withHighestBitrate();
      return audioStream.url.toString();
    } catch (e) {
      return null;
    }
  }

  Future<void> _playSong(SongItem song,
      {List<SongItem>? newQueue, int? queueIndex, bool isVideo = false}) async {
    setState(() {
      _currentSong = song;
      _position = Duration.zero;
      _totalDuration = Duration.zero;
      _isBuffering = true;
    });

    if (newQueue != null) {
      _queue.clear();
      _queue.addAll(newQueue);
      _currentQueueIndex = queueIndex ?? _queue.indexOf(song);
    } else if (!_queue.any((s) => s.id == song.id)) {
      _queue.add(song);
      _currentQueueIndex = _queue.length - 1;
    }

    try {
      if (song.localFilePath != null &&
          !kIsWeb &&
          io.File(song.localFilePath!).existsSync()) {
        final audioSource = AudioSource.uri(
          Uri.file(song.localFilePath!),
          tag: MediaItem(
            id: song.id,
            album: 'AuraStream Offline',
            title: song.title,
            artist: song.artist,
            artUri: Uri.tryParse(song.thumbnailUrl),
          ),
        );
        await _audioPlayer.setAudioSource(audioSource);
      } else {
        final streamUrl =
            await _resolveStreamUrl(song.id, isVideo: isVideo);
        if (streamUrl != null) {
          if (kIsWeb) {
            // Web için doğrudan setUrl en kararlı ve kesintisiz yöntemdir
            await _audioPlayer.setUrl(streamUrl);
          } else {
            final audioSource = AudioSource.uri(
              Uri.parse(streamUrl),
              tag: MediaItem(
                id: song.id,
                album: isVideo ? 'AuraStream Video Sesi' : 'AuraStream Canlı',
                title: song.title,
                artist: song.artist,
                artUri: Uri.tryParse(song.thumbnailUrl),
              ),
            );
            await _audioPlayer.setAudioSource(audioSource);
          }
        } else {
          throw Exception("Yayın adresi çözülemedi");
        }
      }
      _audioPlayer.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Şarkı oynatılamadı: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBuffering = false);
    }
  }

  void _togglePlayPause() {
    setState(() {
      _isBuffering = false;
    });
    if (_audioPlayer.playing) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  void _playNext() {
    if (_queue.isEmpty) return;
    if (_isShuffle) {
      final nextIdx = (List<int>.generate(_queue.length, (i) => i)..shuffle())
          .firstWhere((i) => i != _currentQueueIndex, orElse: () => 0);
      _currentQueueIndex = nextIdx;
    } else {
      _currentQueueIndex = (_currentQueueIndex + 1) % _queue.length;
    }
    _playSong(_queue[_currentQueueIndex]);
  }

  void _playPrevious() {
    if (_queue.isEmpty) return;
    if (_position.inSeconds > 3) {
      _audioPlayer.seek(Duration.zero);
      return;
    }
    _currentQueueIndex =
        (_currentQueueIndex - 1 + _queue.length) % _queue.length;
    _playSong(_queue[_currentQueueIndex]);
  }

  void _addToQueue(SongItem song) {
    setState(() {
      _queue.add(song);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sıraya eklendi: ${song.title}'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF1DB954),
      ),
    );
  }

  // Background Download Tracking with Android Notification Bar
  Future<void> _updateNotificationProgress(
      int notifId, String title, int progress, int maxProgress) async {
    if (kIsWeb) return;
    try {
      final androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'download_channel',
        'İndirme Takibi',
        channelDescription: 'AuraStream indirme ilerleme bildirimleri',
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true,
        showProgress: true,
        maxProgress: maxProgress,
        progress: progress,
        ongoing: progress < maxProgress,
      );
      final platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);
      await flutterLocalNotificationsPlugin.show(
        id: notifId,
        title: progress < maxProgress ? 'İndiriliyor: $title' : '✓ İndirme Tamamlandı',
        body: progress < maxProgress ? '%$progress tamamlandı' : title,
        notificationDetails: platformChannelSpecifics,
      );
    } catch (_) {}
  }

  Future<void> _downloadOrCacheSong(SongItem song,
      {bool isOfflineCache = false, bool isVideo = false}) async {
    final notifId = song.id.hashCode.abs() % 100000;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isOfflineCache
            ? 'Önbelleğe indiriliyor: ${song.title}...'
            : (isVideo
                ? 'Video indiriliyor: ${song.title}...'
                : 'Telefona indiriliyor: ${song.title}...')),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1DB954),
      ),
    );

    try {
      if (kIsWeb) {
        final streamUrl =
            await _resolveStreamUrl(song.id, isVideo: isVideo);
        if (streamUrl != null) {
          final anchor =
              web.document.createElement('a') as web.HTMLAnchorElement;
          anchor.href = streamUrl;
          anchor.download =
              isVideo ? '${song.title}.mp4' : '${song.title}.m4a';
          anchor.target = '_blank';
          web.document.body?.appendChild(anchor);
          anchor.click();
          anchor.remove();
        }
      } else {
        final manifest =
            await _ytExplode.videos.streamsClient.getManifest(song.id);
        final streamInfo = isVideo
            ? manifest.muxed.withHighestBitrate()
            : manifest.audioOnly.withHighestBitrate();

        final totalBytes = streamInfo.size.totalBytes;
        final stream = _ytExplode.videos.streamsClient.get(streamInfo);

        final dir = isOfflineCache
            ? await getApplicationSupportDirectory()
            : (await getDownloadsDirectory() ??
                await getApplicationDocumentsDirectory());

        final sanitizedTitle =
            song.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final ext = isVideo ? 'mp4' : streamInfo.container.name;
        final filePath = '${dir.path}/$sanitizedTitle.$ext';
        final file = io.File(filePath);
        final output = file.openWrite();

        int downloaded = 0;
        int lastReportedPercent = -1;

        await for (final chunk in stream) {
          output.add(chunk);
          downloaded += chunk.length;
          final currentPercent = ((downloaded / totalBytes) * 100).toInt();
          if (currentPercent != lastReportedPercent &&
              currentPercent % 5 == 0) {
            lastReportedPercent = currentPercent;
            setState(() {
              _activeDownloadProgress[song.id] = downloaded / totalBytes;
            });
            await _updateNotificationProgress(
                notifId, song.title, currentPercent, 100);
          }
        }

        await output.flush();
        await output.close();

        // Final Complete Notification
        await _updateNotificationProgress(notifId, song.title, 100, 100);

        setState(() {
          _activeDownloadProgress.remove(song.id);
        });

        final downloadedItem = SongItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
          duration: song.duration,
          thumbnailUrl: song.thumbnailUrl,
          format: isOfflineCache
              ? 'Önbellek (Offline)'
              : (isVideo ? '720p HD MP4' : 'MAX SES (Telefon)'),
          localFilePath: filePath,
          downloadDate: DateTime.now(),
        );

        setState(() {
          _downloadedSongs.removeWhere((s) => s.id == song.id);
          _downloadedSongs.insert(0, downloadedItem);
        });
        await _saveDownloads();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ İndirme tamamlandı: ${song.title}'),
            backgroundColor: const Color(0xFF1DB954),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _activeDownloadProgress.remove(song.id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İndirme hatası: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showAddToPlaylistDialog(SongItem song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF181820),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Çalma Listesine Ekle',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Color(0xFF1DB954)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showCreatePlaylistDialog(initialSong: song);
                    },
                  )
                ],
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _playlists.length,
                  itemBuilder: (c, idx) {
                    final pl = _playlists[idx];
                    final contains = pl.songs.any((s) => s.id == song.id);
                    return ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.queue_music,
                            color: Color(0xFF1DB954)),
                      ),
                      title: Text(pl.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${pl.songs.length} şarkı',
                          style: const TextStyle(color: Colors.grey)),
                      trailing: Icon(
                        contains
                            ? Icons.check_circle
                            : Icons.add_circle_outline,
                        color: contains
                            ? const Color(0xFF1DB954)
                            : Colors.white54,
                      ),
                      onTap: () {
                        setState(() {
                          if (contains) {
                            pl.songs.removeWhere((s) => s.id == song.id);
                          } else {
                            pl.songs.add(song);
                          }
                        });
                        _savePlaylists();
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreatePlaylistDialog({SongItem? initialSong}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Yeni Çalma Listesi'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          textAlignVertical: TextAlignVertical.center,
          decoration: const InputDecoration(
            hintText: 'Çalma listesi adı...',
            hintStyle: TextStyle(color: Colors.white38),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 10),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF1DB954)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final newPl = PlaylistModel(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  songs: initialSong != null ? [initialSong] : [],
                );
                setState(() {
                  _playlists.add(newPl);
                });
                _savePlaylists();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Oluştur',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openSpotifyPlayer() {
    if (_currentSong == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StreamBuilder<Duration>(
          stream: _audioPlayer.positionStream,
          builder: (context, snapshot) {
            final currentPos = snapshot.data ?? _position;
            final currentDur = _audioPlayer.duration ?? _totalDuration;
            final isCurrentlyPlaying = _audioPlayer.playing;

            return _SpotifyFullPlayer(
              song: _currentSong!,
              audioPlayer: _audioPlayer,
              isPlaying: isCurrentlyPlaying,
              isBuffering: _isBuffering,
              isShuffle: _isShuffle,
              loopMode: _loopMode,
              position: currentPos,
              totalDuration: currentDur,
              queue: _queue,
              currentQueueIndex: _currentQueueIndex,
              onTogglePlay: _togglePlayPause,
              onNext: _playNext,
              onPrev: _playPrevious,
              onToggleShuffle: () {
                setState(() => _isShuffle = !_isShuffle);
              },
              onToggleLoop: () {
                setState(() {
                  _loopMode = _loopMode == LoopMode.off
                      ? LoopMode.all
                      : (_loopMode == LoopMode.all ? LoopMode.one : LoopMode.off);
                  _audioPlayer.setLoopMode(_loopMode);
                });
              },
              onAddToPlaylist: () => _showAddToPlaylistDialog(_currentSong!),
              onDownload: (isCache) =>
                  _downloadOrCacheSong(_currentSong!, isOfflineCache: isCache),
              onPlayVideoBackground: () =>
                  _playSong(_currentSong!, isVideo: true),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _currentTabIndex,
                children: [
                  _SearchTab(
                    downloadProgress: _activeDownloadProgress,
                    onPlaySong: (s) => _playSong(s),
                    onPlayVideoBackground: (s) => _playSong(s, isVideo: true),
                    onAddToQueue: _addToQueue,
                    onAddToPlaylist: _showAddToPlaylistDialog,
                    onDownload: (s) =>
                        _downloadOrCacheSong(s, isOfflineCache: false),
                    onDownloadVideo: (s) => _downloadOrCacheSong(s,
                        isOfflineCache: false, isVideo: true),
                    onCache: (s) =>
                        _downloadOrCacheSong(s, isOfflineCache: true),
                  ),
                  _PlaylistsTab(
                    playlists: _playlists,
                    onPlayPlaylist: (pl, startIdx) {
                      if (pl.songs.isNotEmpty) {
                        _playSong(pl.songs[startIdx],
                            newQueue: pl.songs, queueIndex: startIdx);
                      }
                    },
                    onCreatePlaylist: () => _showCreatePlaylistDialog(),
                    onDeletePlaylist: (pl) {
                      setState(
                          () => _playlists.removeWhere((p) => p.id == pl.id));
                      _savePlaylists();
                    },
                    onDownloadAll: (pl, isCache) async {
                      for (final s in pl.songs) {
                        await _downloadOrCacheSong(s, isOfflineCache: isCache);
                      }
                    },
                  ),
                  _DownloadsCacheTab(
                    downloadedSongs: _downloadedSongs,
                    onPlaySong: (s) => _playSong(s),
                    onDeleteSong: (s) {
                      setState(() =>
                          _downloadedSongs.removeWhere((i) => i.id == s.id));
                      _saveDownloads();
                    },
                  ),
                ],
              ),
            ),
            if (_currentSong != null)
              _SpotifyMiniPlayer(
                song: _currentSong!,
                isPlaying: _isPlaying,
                isBuffering: _isBuffering,
                position: _position,
                totalDuration: _totalDuration,
                onTap: _openSpotifyPlayer,
                onTogglePlay: _togglePlayPause,
                onNext: _playNext,
              ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF121217),
          border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF1DB954),
          unselectedItemColor: Colors.white54,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          type: BottomNavigationBarType.fixed,
          onTap: (index) => setState(() => _currentTabIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.search_rounded),
              activeIcon:
                  Icon(Icons.search_rounded, color: Color(0xFF1DB954)),
              label: 'Ara & Keşfet',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.library_music_outlined),
              activeIcon: Icon(Icons.library_music_rounded,
                  color: Color(0xFF1DB954)),
              label: 'Çalma Listeleri',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.download_done_rounded),
              activeIcon: Icon(Icons.download_done_rounded,
                  color: Color(0xFF1DB954)),
              label: 'Önbellek & İndirilenler',
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== SEARCH TAB ====================
class _SearchTab extends StatefulWidget {
  final Map<String, double> downloadProgress;
  final Function(SongItem) onPlaySong;
  final Function(SongItem) onPlayVideoBackground;
  final Function(SongItem) onAddToQueue;
  final Function(SongItem) onAddToPlaylist;
  final Function(SongItem) onDownload;
  final Function(SongItem) onDownloadVideo;
  final Function(SongItem) onCache;

  const _SearchTab({
    required this.downloadProgress,
    required this.onPlaySong,
    required this.onPlayVideoBackground,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onDownload,
    required this.onDownloadVideo,
    required this.onCache,
  });

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;

  List<String> _suggestions = [];
  List<SongItem> _searchResults = [];
  bool _isLoadingSearch = false;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    // Uygulama açılır açılmaz en popüler / trend şarkıları hemen listele
    _performSearch('Trend Türkçe Pop Şarkılar 2026');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _activeQuery = '';
      });
      _performSearch('Trend Türkçe Pop Şarkılar 2026');
      return;
    }

    // Arama kutusunda yazı varsa önerileri getir
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (_searchController.text.trim().isNotEmpty) {
        _fetchAutocompleteSuggestions(_searchController.text.trim());
      } else {
        setState(() => _suggestions = []);
      }
    });
  }

  Future<void> _fetchAutocompleteSuggestions(String query) async {
    try {
      final encoded = Uri.encodeComponent(query);
      final url = kIsWeb
          ? Uri.parse('http://127.0.0.1:5050/suggest?q=$encoded')
          : Uri.parse(
              'https://suggestqueries-clients6.youtube.com/complete/search?client=youtube&ds=yt&q=$encoded');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final body = res.body;
        if (kIsWeb) {
          final List<dynamic> list = jsonDecode(body);
          if (mounted) setState(() => _suggestions = list.map((e) => e.toString()).toList());
          return;
        }
        final startIndex = body.indexOf('(');
        final endIndex = body.lastIndexOf(')');
        if (startIndex != -1 && endIndex != -1) {
          final jsonStr = body.substring(startIndex + 1, endIndex);
          final decoded = jsonDecode(jsonStr) as List<dynamic>;
          if (decoded.length > 1) {
            final rawList = decoded[1] as List<dynamic>;
            final list = rawList.map((item) => item[0].toString()).toList();
            if (mounted) {
              setState(() {
                _suggestions = list;
              });
            }
            return;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _performSearch(String query, {bool isLiveDebounce = false}) async {
    if (query.trim().isEmpty) return;
    if (!isLiveDebounce) {
      _focusNode.unfocus();
    }
    setState(() {
      _isLoadingSearch = true;
      _activeQuery = query;
      if (!isLiveDebounce) {
        _suggestions = [];
      }
    });

    try {
      List<SongItem> items = [];

      // Tarayıcıdaysa (Web CORS koruması nedeniyle) proxy veya alternatif endpoint kullan
      if (kIsWeb) {
        try {
          final res = await http.get(Uri.parse('http://127.0.0.1:5050/search?q=${Uri.encodeComponent(query)}'));
          if (res.statusCode == 200) {
            final List<dynamic> data = jsonDecode(res.body);
            items = data.map((json) => SongItem.fromJson(json)).toList();
          }
        } catch (_) {}
      }

      // Eğer mobil cihazdaysa veya doğrudan bağlantı açıksa YoutubeExplode çalıştır
      if (items.isEmpty) {
        final ytExplode = yt.YoutubeExplode();
        final searchResult = await ytExplode.search.search(query);
        items = searchResult.map((video) {
          return SongItem(
            id: video.id.value,
            title: video.title,
            artist: video.author,
            duration: video.duration != null
                ? '${video.duration!.inMinutes}:${(video.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
                : '--:--',
            thumbnailUrl: video.thumbnails.mediumResUrl,
          );
        }).toList();
        ytExplode.close();
      }

      if (mounted) {
        setState(() {
          _searchResults = items;
          _isLoadingSearch = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSearch = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Arama hatası: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'AuraStream',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1DB954).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: const Color(0xFF1DB954), width: 1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.music_video_rounded,
                            color: Color(0xFF1DB954), size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Background Engine',
                          style: TextStyle(
                            color: Color(0xFF1DB954),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF24242E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.search, color: Color(0xFF1DB954), size: 22),
                    ),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          if (_searchController.text.isEmpty)
                            const Text(
                              'Şarkı, sanatçı veya video ara...',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 14,
                              ),
                            ),
                          TextField(
                            controller: _searchController,
                            focusNode: _focusNode,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            textAlignVertical: TextAlignVertical.center,
                            onChanged: (val) {
                              setState(() {});
                              _onSearchChanged(val);
                            },
                            onSubmitted: (val) => _performSearch(val),
                            textInputAction: TextInputAction.search,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                        splashRadius: 18,
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                          _onSearchChanged('');
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF1DB954), size: 22),
                      splashRadius: 18,
                      tooltip: 'Ara',
                      onPressed: () => _performSearch(_searchController.text),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Canlı Öneriler (Sadece arama kutusunda yazı varken gösterilir, metin silinince anında kaybolur)
        if (_searchController.text.trim().isNotEmpty && _suggestions.isNotEmpty)
          Container(
            height: 38,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _suggestions.length,
              itemBuilder: (ctx, index) {
                final suggestion = _suggestions[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: const Color(0xFF24242E),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    avatar: const Icon(Icons.search, size: 14, color: Color(0xFF1DB954)),
                    label: Text(
                      suggestion,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    onPressed: () {
                      _searchController.text = suggestion;
                      _performSearch(suggestion);
                    },
                  ),
                );
              },
            ),
          ),

        // Yükleniyor Göstergesi (Kompakt üst bar şeklinde, şarkı listesini yok etmez)
        if (_isLoadingSearch)
          const LinearProgressIndicator(
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
            minHeight: 2,
          ),

        // Şarkı Listesi - Her harfte anlık olarak güncellenir ve asla kapanmaz
        if (_searchResults.isNotEmpty)
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemBuilder: (ctx, index) {
                final song = _searchResults[index];
                final progress = widget.downloadProgress[song.id];
                return _SpotifySongCard(
                  song: song,
                  downloadProgress: progress,
                  onPlay: () => widget.onPlaySong(song),
                  onPlayVideoBackground: () =>
                      widget.onPlayVideoBackground(song),
                  onAddToQueue: () => widget.onAddToQueue(song),
                  onAddToPlaylist: () => widget.onAddToPlaylist(song),
                  onDownload: () => widget.onDownload(song),
                  onDownloadVideo: () => widget.onDownloadVideo(song),
                  onCache: () => widget.onCache(song),
                );
              },
            ),
          )
        else if (!_isLoadingSearch)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.headphones_rounded,
                      size: 64, color: Colors.white.withValues(alpha: 0.15)),
                  const SizedBox(height: 16),
                  Text(
                    _activeQuery.isEmpty
                        ? 'Milyonlarca şarkıyı ve videoyu arka planda dinleyin'
                        : 'Sonuç bulunamadı',
                    style: const TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ==================== SPOTIFY SONG CARD (SADE & TEMİZ) ====================
class _SpotifySongCard extends StatelessWidget {
  final SongItem song;
  final double? downloadProgress;
  final VoidCallback onPlay;
  final VoidCallback onPlayVideoBackground;
  final VoidCallback onAddToQueue;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onDownload;
  final VoidCallback onDownloadVideo;
  final VoidCallback onCache;

  const _SpotifySongCard({
    required this.song,
    this.downloadProgress,
    required this.onPlay,
    required this.onPlayVideoBackground,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onDownload,
    required this.onDownloadVideo,
    required this.onCache,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                song.thumbnailUrl,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 50,
                  height: 50,
                  color: Colors.grey.shade900,
                  child: const Icon(Icons.music_note, color: Colors.white54),
                ),
              ),
            ),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
                color: Colors.white,
              ),
            ),
            subtitle: Text(
              '${song.artist} • ${song.duration}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // MYT Tarzı MP3 İndir Butonu (Kırmızı)
                _MytMiniButton(
                  label: 'MP3',
                  color: const Color(0xFFFF2A55),
                  icon: Icons.music_note,
                  onTap: onDownload,
                ),
                const SizedBox(width: 6),
                // MYT Tarzı Video İndir Butonu (Mavi)
                _MytMiniButton(
                  label: 'VİDEO',
                  color: const Color(0xFF00E5FF),
                  icon: Icons.videocam,
                  onTap: onDownloadVideo,
                ),
                const SizedBox(width: 4),
                // Diğer İşlemler (3 Nokta)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: const Color(0xFF24242E),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    if (val == 'cache') onCache();
                    if (val == 'playlist') onAddToPlaylist();
                    if (val == 'queue') onAddToQueue();
                    if (val == 'video_bg') onPlayVideoBackground();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'cache',
                      child: Row(
                        children: [
                          Icon(Icons.offline_pin_outlined,
                              color: Color(0xFF00E5FF), size: 18),
                          SizedBox(width: 10),
                          Text('Önbelleğe Al (Offline Dinle)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'playlist',
                      child: Row(
                        children: [
                          Icon(Icons.playlist_add, color: Color(0xFF1DB954), size: 18),
                          SizedBox(width: 10),
                          Text('Çalma Listesine Ekle'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'queue',
                      child: Row(
                        children: [
                          Icon(Icons.queue_music, color: Colors.white70, size: 18),
                          SizedBox(width: 10),
                          Text('Sıraya Ekle'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'video_bg',
                      child: Row(
                        children: [
                          Icon(Icons.video_library_outlined, color: Colors.amber, size: 18),
                          SizedBox(width: 10),
                          Text('Videoyu Arkada Oynat'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            onTap: onPlay,
          ),
          if (downloadProgress != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: LinearProgressIndicator(
                value: downloadProgress,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
                minHeight: 2,
              ),
            ),
        ],
      ),
    );
  }
}

class _MytMiniButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _MytMiniButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModernActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ModernActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// ==================== PLAYLISTS TAB ====================
class _PlaylistsTab extends StatelessWidget {
  final List<PlaylistModel> playlists;
  final Function(PlaylistModel, int) onPlayPlaylist;
  final VoidCallback onCreatePlaylist;
  final Function(PlaylistModel) onDeletePlaylist;
  final Function(PlaylistModel, bool) onDownloadAll;

  const _PlaylistsTab({
    required this.playlists,
    required this.onPlayPlaylist,
    required this.onCreatePlaylist,
    required this.onDeletePlaylist,
    required this.onDownloadAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Çalma Listelerin',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Yeni Liste',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: onCreatePlaylist,
              )
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: playlists.isEmpty
                ? const Center(
                    child: Text('Henüz bir çalma listesi oluşturmadınız.',
                        style: TextStyle(color: Colors.white54)),
                  )
                : ListView.builder(
                    itemCount: playlists.length,
                    itemBuilder: (ctx, idx) {
                      final pl = playlists[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF181820),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: ExpansionTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1DB954), Color(0xFF0F6E31)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.music_note,
                                color: Colors.black, size: 28),
                          ),
                          title: Text(pl.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Text('${pl.songs.length} şarkı',
                              style: const TextStyle(color: Colors.white54)),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert,
                                color: Colors.white70),
                            color: const Color(0xFF24242E),
                            onSelected: (val) {
                              if (val == 'download') onDownloadAll(pl, false);
                              if (val == 'cache') onDownloadAll(pl, true);
                              if (val == 'delete') onDeletePlaylist(pl);
                            },
                            itemBuilder: (c) => [
                              const PopupMenuItem(
                                value: 'cache',
                                child: Text('Tümünü Önbelleğe Al'),
                              ),
                              const PopupMenuItem(
                                value: 'download',
                                child: Text('Tümünü Telefona İndir'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Listeyi Sil',
                                    style: TextStyle(color: Colors.redAccent)),
                              ),
                            ],
                          ),
                          children: [
                            if (pl.songs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text(
                                  'Bu listede henüz şarkı yok. Arama ekranından ekleyin.',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 13),
                                ),
                              )
                            else ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF1DB954),
                                        foregroundColor: Colors.black,
                                      ),
                                      icon: const Icon(Icons.play_arrow),
                                      label: const Text('Tümünü Çal'),
                                      onPressed: () => onPlayPlaylist(pl, 0),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF00E5FF),
                                        side: const BorderSide(
                                            color: Color(0xFF00E5FF)),
                                      ),
                                      icon: const Icon(Icons.offline_pin,
                                          size: 16),
                                      label: const Text('Önbelleğe Al'),
                                      onPressed: () => onDownloadAll(pl, true),
                                    ),
                                  ],
                                ),
                              ),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: pl.songs.length,
                                itemBuilder: (cx, sIdx) {
                                  final song = pl.songs[sIdx];
                                  return ListTile(
                                    dense: true,
                                    leading: Text('${sIdx + 1}',
                                        style: const TextStyle(
                                            color: Colors.white54)),
                                    title: Text(song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    trailing: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Color(0xFF1DB954)),
                                    onTap: () => onPlayPlaylist(pl, sIdx),
                                  );
                                },
                              ),
                            ]
                          ],
                        ),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
}

// ==================== DOWNLOADS & CACHE TAB ====================
class _DownloadsCacheTab extends StatelessWidget {
  final List<SongItem> downloadedSongs;
  final Function(SongItem) onPlaySong;
  final Function(SongItem) onDeleteSong;

  const _DownloadsCacheTab({
    required this.downloadedSongs,
    required this.onPlaySong,
    required this.onDeleteSong,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Önbellek & İndirilenler',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${downloadedSongs.length} Dosya',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
              )
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'İnternetiniz kapalıyken veya ekran kilitliyken arka planda çalınabilir.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: downloadedSongs.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download_for_offline_outlined,
                            size: 64, color: Colors.white24),
                        SizedBox(height: 12),
                        Text(
                            'Henüz indirilmiş veya önbelleğe alınmış şarkı yok.',
                            style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: downloadedSongs.length,
                    itemBuilder: (ctx, idx) {
                      final item = downloadedSongs[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF181820),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              item.thumbnailUrl,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 48,
                                height: 48,
                                color: Colors.grey.shade900,
                                child: const Icon(Icons.music_note,
                                    color: Colors.white54),
                              ),
                            ),
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${item.artist} • ${item.format}',
                            style: const TextStyle(
                                color: Color(0xFF1DB954), fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.play_circle_fill,
                                    color: Color(0xFF1DB954), size: 32),
                                onPressed: () => onPlaySong(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.white38),
                                onPressed: () => onDeleteSong(item),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
}

// ==================== SPOTIFY MINI PLAYER ====================
class _SpotifyMiniPlayer extends StatelessWidget {
  final SongItem song;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration totalDuration;
  final VoidCallback onTap;
  final VoidCallback onTogglePlay;
  final VoidCallback onNext;

  const _SpotifyMiniPlayer({
    required this.song,
    required this.isPlaying,
    required this.isBuffering,
    required this.position,
    required this.totalDuration,
    required this.onTap,
    required this.onTogglePlay,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalDuration.inMilliseconds > 0
        ? (position.inMilliseconds / totalDuration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF24242E),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, -2),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  song.thumbnailUrl,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 44,
                    height: 44,
                    color: Colors.grey.shade900,
                    child:
                        const Icon(Icons.music_note, color: Colors.white54),
                  ),
                ),
              ),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              subtitle: Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isBuffering)
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF1DB954),
                      ),
                    )
                  else
                    IconButton(
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                      onPressed: onTogglePlay,
                    ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded,
                        color: Colors.white70, size: 28),
                    onPressed: onNext,
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(10)),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white10,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
                minHeight: 2.5,
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ==================== SPOTIFY FULL SCREEN PLAYER ====================
class _SpotifyFullPlayer extends StatelessWidget {
  final SongItem song;
  final AudioPlayer audioPlayer;
  final bool isPlaying;
  final bool isBuffering;
  final bool isShuffle;
  final LoopMode loopMode;
  final Duration position;
  final Duration totalDuration;
  final List<SongItem> queue;
  final int currentQueueIndex;
  final VoidCallback onTogglePlay;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleLoop;
  final VoidCallback onAddToPlaylist;
  final Function(bool) onDownload;
  final VoidCallback onPlayVideoBackground;

  const _SpotifyFullPlayer({
    required this.song,
    required this.audioPlayer,
    required this.isPlaying,
    required this.isBuffering,
    required this.isShuffle,
    required this.loopMode,
    required this.position,
    required this.totalDuration,
    required this.queue,
    required this.currentQueueIndex,
    required this.onTogglePlay,
    required this.onNext,
    required this.onPrev,
    required this.onToggleShuffle,
    required this.onToggleLoop,
    required this.onAddToPlaylist,
    required this.onDownload,
    required this.onPlayVideoBackground,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Sırada şarkı var mı kontrol et
    final hasNextSong = queue.isNotEmpty && currentQueueIndex >= 0 && currentQueueIndex < queue.length - 1;
    final nextSong = hasNextSong ? queue[currentQueueIndex + 1] : null;

    final screenWidth = MediaQuery.of(context).size.width;
    // Masaüstü ve mobilde orantılı, dengeli albüm kapağı boyutu
    final coverSize = screenWidth > 600 ? 240.0 : (screenWidth * 0.58).clamp(180.0, 260.0);

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E2822),
            Color(0xFF121217),
            Color(0xFF0F0F13),
          ],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Column(
                    children: [
                      Text(
                        'ŞU AN ÇALINIYOR',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 10.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'AuraStream Hi-Fi Media',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.playlist_add, color: Colors.white, size: 24),
                    onPressed: onAddToPlaylist,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Dengeli, ortalanmış albüm kapağı
              Center(
                child: Container(
                  width: coverSize,
                  height: coverSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      song.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.grey.shade900,
                        child: const Icon(Icons.music_note,
                            size: 60, color: Colors.white24),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.video_library_rounded,
                        color: Color(0xFF00E5FF), size: 24),
                    tooltip: 'Videoyu Arkada Oynat',
                    onPressed: onPlayVideoBackground,
                  ),
                  IconButton(
                    icon: const Icon(Icons.offline_pin,
                        color: Color(0xFFFF2A55), size: 24),
                    tooltip: 'Önbelleğe Al',
                    onPressed: () => onDownload(true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download,
                        color: Color(0xFF1DB954), size: 24),
                    tooltip: 'Telefona İndir',
                    onPressed: () => onDownload(false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: const Color(0xFF1DB954),
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: position.inMilliseconds
                      .toDouble()
                      .clamp(0.0, totalDuration.inMilliseconds.toDouble()),
                  max: totalDuration.inMilliseconds > 0
                      ? totalDuration.inMilliseconds.toDouble()
                      : 1.0,
                  onChanged: (val) {
                    audioPlayer.seek(Duration(milliseconds: val.toInt()));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(position),
                        style:
                            const TextStyle(color: Colors.white54, fontSize: 11.5)),
                    Text(_formatDuration(totalDuration),
                        style:
                            const TextStyle(color: Colors.white54, fontSize: 11.5)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Oynatma Kontrolleri (Orantılı, ortalanmış)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: isShuffle ? const Color(0xFF1DB954) : Colors.white38,
                      size: 22,
                    ),
                    onPressed: onToggleShuffle,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded,
                        color: Colors.white, size: 34),
                    onPressed: onPrev,
                  ),
                  Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: IconButton(
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 34,
                      ),
                      onPressed: onTogglePlay,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded,
                        color: Colors.white, size: 34),
                    onPressed: onNext,
                  ),
                  IconButton(
                    icon: Icon(
                      loopMode == LoopMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: loopMode != LoopMode.off
                          ? const Color(0xFF1DB954)
                          : Colors.white38,
                      size: 22,
                    ),
                    onPressed: onToggleLoop,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // SIRADAKİ PARÇA BİLGİSİ (Playlist / Sıra Varsa Gösterilir)
              if (nextSong != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.queue_music, color: Color(0xFF1DB954), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SIRADAKİ',
                              style: TextStyle(
                                color: Color(0xFF1DB954),
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              '${nextSong.title} • ${nextSong.artist}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: Colors.white70, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Sıradakine Geç',
                        onPressed: onNext,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
