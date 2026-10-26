import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:web/web.dart' as web;

void main() {
  runApp(const AuraStreamApp());
}

class AuraStreamApp extends StatelessWidget {
  const AuraStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AuraStream - Music Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F13),
        primaryColor: const Color(0xFFFF2A55),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF2A55),
          secondary: Color(0xFF00E5FF),
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
  final DateTime? downloadDate;

  SongItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.thumbnailUrl,
    this.format = 'MP3',
    this.downloadDate,
  });

  factory SongItem.fromJson(Map<String, dynamic> json) {
    return SongItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      duration: json['duration'] ?? '--:--',
      thumbnailUrl: json['thumbnailUrl'] ?? '',
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentTabIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();
  static const String _apiBase = "http://127.0.0.1:5050";

  final List<SongItem> _downloadedSongs = [];
  SongItem? _currentSong;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  void _initAudio() {
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing &&
              state.processingState != ProcessingState.completed;
        });
      }
    });

    _audioPlayer.positionStream.listen((pos) {
      if (mounted) {
        setState(() => _position = pos);
      }
    });

    _audioPlayer.durationStream.listen((dur) {
      if (mounted && dur != null) {
        setState(() => _totalDuration = dur);
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // Şarkı Çalma
  Future<void> _playSong(SongItem song) async {
    setState(() {
      _currentSong = song;
      _position = Duration.zero;
    });

    try {
      final streamUrl = "$_apiBase/audio/${song.id}";
      await _audioPlayer.stop();
      await _audioPlayer.setUrl(streamUrl);
      await _audioPlayer.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Oynatma hatası: $e")),
        );
      }
    }
  }

  // 10 Saniye İleri/Geri Sarma
  void _seekRelative(int seconds) {
    final target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) {
      _audioPlayer.seek(Duration.zero);
    } else if (target > _totalDuration) {
      _audioPlayer.seek(_totalDuration);
    } else {
      _audioPlayer.seek(target);
    }
  }

  // MP3 veya M4A İndirme Motoru
  void _downloadSong(SongItem song, {bool asMp3 = true}) {
    final endpoint = asMp3 ? "download_mp3" : "download";
    final ext = asMp3 ? "mp3" : "m4a";
    final downloadUrl = "$_apiBase/$endpoint/${song.id}";

    if (kIsWeb) {
      final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
      anchor.href = downloadUrl;
      anchor.download = "${song.title}.$ext";
      web.document.body?.appendChild(anchor);
      anchor.click();
      anchor.remove();
    }

    setState(() {
      _downloadedSongs.insert(
        0,
        SongItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
          duration: song.duration,
          thumbnailUrl: song.thumbnailUrl,
          format: ext.toUpperCase(),
          downloadDate: DateTime.now(),
        ),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: asMp3 ? const Color(0xFFFF2A55) : const Color(0xFF00E5FF),
        content: Text(
          "⚡ ${song.title} (${ext.toUpperCase()}) olarak indiriliyor! İndirme listesine eklendi.",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF14141C),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7928CA), Color(0xFFFF0080), Color(0xFF00DFD8)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF0080).withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'AuraStream',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          // SEKME 1: CANLI ARAMA VE KEŞFET
          ExploreSearchTab(
            apiBase: _apiBase,
            currentSong: _currentSong,
            isPlaying: _isPlaying,
            onPlay: _playSong,
            onDownload: _downloadSong,
          ),

          // SEKME 2: İNDİRME LİSTESİ
          DownloadsTab(
            downloadedSongs: _downloadedSongs,
            currentSong: _currentSong,
            isPlaying: _isPlaying,
            onPlay: _playSong,
            onDelete: (song) {
              setState(() {
                _downloadedSongs.remove(song);
              });
            },
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // GELİŞMİŞ İLERİ/GERİ SARILABİLİR OYNATICI
          if (_currentSong != null) _buildEnhancedPlayerBar(),

          // ALT GEZİNME ÇUBUĞU
          NavigationBar(
            selectedIndex: _currentTabIndex,
            onDestinationSelected: (idx) => setState(() => _currentTabIndex = idx),
            backgroundColor: const Color(0xFF14141C),
            indicatorColor: const Color(0xFFFF2A55).withOpacity(0.2),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore, color: Color(0xFFFF2A55)),
                label: 'Keşfet & Ara',
              ),
              NavigationDestination(
                icon: Badge(
                  label: Text("${_downloadedSongs.length}"),
                  isLabelVisible: _downloadedSongs.isNotEmpty,
                  child: const Icon(Icons.download_for_offline_outlined),
                ),
                selectedIcon: const Icon(Icons.download_for_offline, color: Color(0xFFFF2A55)),
                label: 'İndirme Listesi',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // GELİŞMİŞ PLAYER BAR
  Widget _buildEnhancedPlayerBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181824),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // SÜRE KAYDIRICI (SEEK BAR)
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              trackHeight: 3,
              activeTrackColor: const Color(0xFFFF2A55),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFFFF2A55),
            ),
            child: Slider(
              value: _position.inMilliseconds
                  .clamp(0, _totalDuration.inMilliseconds)
                  .toDouble(),
              max: _totalDuration.inMilliseconds.toDouble() > 0
                  ? _totalDuration.inMilliseconds.toDouble()
                  : 1.0,
              onChanged: (val) {
                _audioPlayer.seek(Duration(milliseconds: val.toInt()));
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _currentSong!.thumbnailUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentSong!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            _currentSong!.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const Spacer(),
                          Text(
                            "${_formatDuration(_position)} / ${_formatDuration(_totalDuration)}",
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                IconButton(
                  icon: const Icon(Icons.replay_10_rounded, color: Colors.white70, size: 26),
                  tooltip: '10 Saniye Geri',
                  onPressed: () => _seekRelative(-10),
                ),
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                    color: const Color(0xFFFF2A55),
                    size: 40,
                  ),
                  onPressed: () {
                    if (_isPlaying) {
                      _audioPlayer.pause();
                    } else {
                      _audioPlayer.play();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.forward_10_rounded, color: Colors.white70, size: 26),
                  tooltip: '10 Saniye İleri',
                  onPressed: () => _seekRelative(10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------
// SEKME 1: KEŞFET & ANLIK CANLI ARAMA
// ----------------------------------------------------
class ExploreSearchTab extends StatefulWidget {
  final String apiBase;
  final SongItem? currentSong;
  final bool isPlaying;
  final Function(SongItem) onPlay;
  final Function(SongItem, {bool asMp3}) onDownload;

  const ExploreSearchTab({
    super.key,
    required this.apiBase,
    required this.currentSong,
    required this.isPlaying,
    required this.onPlay,
    required this.onDownload,
  });

  @override
  State<ExploreSearchTab> createState() => _ExploreSearchTabState();
}

class _ExploreSearchTabState extends State<ExploreSearchTab> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _suggestions = [];
  List<SongItem> _songs = [];
  Timer? _debounceTimer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _performSearch("Trend Şarkılar 2026");
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 200), () async {
      try {
        final url = Uri.parse("${widget.apiBase}/suggest?q=${Uri.encodeComponent(query.trim())}");
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final List list = jsonDecode(response.body);
          if (mounted) {
            setState(() => _suggestions = list.map((e) => e.toString()).toList());
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isLoading = true;
      _suggestions = [];
    });

    try {
      final url = Uri.parse("${widget.apiBase}/search?q=${Uri.encodeComponent(query)}");
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body);
        setState(() {
          _songs = list.map((e) => SongItem.fromJson(e)).toList();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ARAMA ALANI
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E28),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white10),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onSubmitted: _performSearch,
              decoration: InputDecoration(
                hintText: 'Şarkı, sanatçı veya müzik ara...',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFFF2A55)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _suggestions = []);
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                border: InputBorder.none,
              ),
            ),
          ),
        ),

        // CANLI ÖNERİLER
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF222230),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _suggestions.length > 5 ? 5 : _suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
              itemBuilder: (context, index) {
                final sug = _suggestions[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.north_west_rounded, color: Color(0xFF00E5FF), size: 18),
                  title: Text(sug, style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    _searchController.text = sug;
                    _performSearch(sug);
                  },
                );
              },
            ),
          ),

        // ŞARKI LİSTESİ
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF2A55)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: _songs.length,
                  itemBuilder: (context, index) {
                    final song = _songs[index];
                    final isCurrent = widget.currentSong?.id == song.id;

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? const Color(0xFFFF2A55).withOpacity(0.12)
                            : const Color(0xFF161622),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isCurrent
                              ? const Color(0xFFFF2A55).withOpacity(0.4)
                              : Colors.transparent,
                        ),
                      ),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            song.thumbnailUrl,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              width: 52,
                              height: 52,
                              color: Colors.grey[850],
                              child: const Icon(Icons.music_note, color: Colors.grey),
                            ),
                          ),
                        ),
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isCurrent ? const Color(0xFFFF2A55) : Colors.white,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            children: [
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  song.duration,
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ÖZEL MP3 İNDİRME BUTONU (320 KBPS)
                            ElevatedButton.icon(
                              icon: const Icon(Icons.file_download_rounded, size: 16),
                              label: const Text('MP3', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF2A55),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => widget.onDownload(song, asMp3: true),
                            ),
                            const SizedBox(width: 6),
                            // HIZLI M4A İNDİRME BUTONU
                            IconButton(
                              icon: const Icon(Icons.download_rounded, color: Color(0xFF00E5FF), size: 22),
                              tooltip: 'Hızlı M4A İndir',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => widget.onDownload(song, asMp3: false),
                            ),
                            const SizedBox(width: 8),
                            // OYNAT BUTONU
                            IconButton(
                              icon: Icon(
                                isCurrent && widget.isPlaying
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                color: const Color(0xFFFF2A55),
                                size: 36,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => widget.onPlay(song),
                            ),
                          ],
                        ),
                        onTap: () => widget.onPlay(song),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------
// SEKME 2: İNDİRME LİSTESİ
// ----------------------------------------------------
class DownloadsTab extends StatelessWidget {
  final List<SongItem> downloadedSongs;
  final SongItem? currentSong;
  final bool isPlaying;
  final Function(SongItem) onPlay;
  final Function(SongItem) onDelete;

  const DownloadsTab({
    super.key,
    required this.downloadedSongs,
    required this.currentSong,
    required this.isPlaying,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (downloadedSongs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_for_offline_outlined, size: 80, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 16),
            const Text(
              'Henüz İndirilen Parça Yok',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              'Arama sekmesinden "MP3" butonuna basarak dilediğiniz şarkıyı indirin.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: downloadedSongs.length,
      itemBuilder: (context, index) {
        final song = downloadedSongs[index];
        final isCurrent = currentSong?.id == song.id;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF161622),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCurrent ? const Color(0xFFFF2A55).withOpacity(0.5) : Colors.white.withOpacity(0.06),
            ),
          ),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                song.thumbnailUrl,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 52,
                  height: 52,
                  color: Colors.grey[850],
                  child: const Icon(Icons.music_note),
                ),
              ),
            ),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isCurrent ? const Color(0xFFFF2A55) : Colors.white,
              ),
            ),
            subtitle: Row(
              children: [
                Text(
                  "${song.artist} • ${song.duration}",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: song.format == 'MP3'
                        ? const Color(0xFFFF2A55).withOpacity(0.2)
                        : const Color(0xFF00E5FF).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: song.format == 'MP3' ? const Color(0xFFFF2A55) : const Color(0xFF00E5FF),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    song.format,
                    style: TextStyle(
                      color: song.format == 'MP3' ? const Color(0xFFFF2A55) : const Color(0xFF00E5FF),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    isCurrent && isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: const Color(0xFFFF2A55),
                    size: 34,
                  ),
                  onPressed: () => onPlay(song),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                  tooltip: 'Listeden Kaldır',
                  onPressed: () => onDelete(song),
                ),
              ],
            ),
            onTap: () => onPlay(song),
          ),
        );
      },
    );
  }
}
