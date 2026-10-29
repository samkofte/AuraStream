import 'dart:convert';
import 'package:http/http.dart' as http;

class FastYTScraper {
  static final http.Client _client = http.Client();

  /// Doğrudan YouTube Web Scraping / Innertube ile arama
  /// YoutubeExplode'un eski getT hatasına takılmadan anında çalışır.
  static Future<List<Map<String, String>>> search(String query) async {
    try {
      final url = Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}&hl=tr&gl=TR');
      final res = await _client.get(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
        },
      );

      if (res.statusCode != 200) return [];

      final html = res.body;
      const key = 'var ytInitialData = ';
      final startIndex = html.indexOf(key);
      if (startIndex == -1) return [];

      final jsonStart = startIndex + key.length;
      final jsonEnd = html.indexOf(';</script>', jsonStart);
      if (jsonEnd == -1) return [];

      final jsonStr = html.substring(jsonStart, jsonEnd);
      final data = jsonDecode(jsonStr);

      final List<Map<String, String>> results = [];

      final contents = data['contents']?['twoColumnSearchResultsRenderer']
          ?['primaryContents']?['sectionListRenderer']?['contents'];

      if (contents is List) {
        for (var section in contents) {
          final itemSection = section?['itemSectionRenderer']?['contents'];
          if (itemSection is List) {
            for (var item in itemSection) {
              final videoRenderer = item?['videoRenderer'];
              if (videoRenderer != null) {
                final videoId = videoRenderer['videoId']?.toString() ?? '';
                if (videoId.isEmpty) continue;

                // Başlık
                String title = '';
                final titleRuns = videoRenderer['title']?['runs'];
                if (titleRuns is List && titleRuns.isNotEmpty) {
                  title = titleRuns.map((r) => r['text'] ?? '').join();
                } else {
                  title = videoRenderer['title']?['simpleText']?.toString() ?? 'Bilinmeyen Başlık';
                }

                // Sanatçı / Kanal
                String artist = '';
                final ownerRuns = videoRenderer['ownerText']?['runs'];
                if (ownerRuns is List && ownerRuns.isNotEmpty) {
                  artist = ownerRuns[0]['text']?.toString() ?? '';
                }

                // Süre
                String duration = videoRenderer['lengthText']?['simpleText']?.toString() ?? '--:--';

                // Küçük Resim
                String thumb = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
                final thumbnails = videoRenderer['thumbnail']?['thumbnails'];
                if (thumbnails is List && thumbnails.isNotEmpty) {
                  thumb = thumbnails.last['url']?.toString() ?? thumb;
                }

                results.add({
                  'id': videoId,
                  'title': title.isNotEmpty ? title : 'Bilinmeyen Müzik',
                  'artist': artist.isNotEmpty ? artist : 'Bilinmeyen Sanatçı',
                  'duration': duration,
                  'thumbnailUrl': thumb,
                });
              }
            }
          }
        }
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  /// YouTube Arama Tamamlama (Öneriler)
  static Future<List<String>> getSuggestions(String query) async {
    try {
      final url = Uri.parse(
          'https://suggestqueries-clients6.youtube.com/complete/search?client=youtube&ds=yt&hl=tr&gl=TR&q=${Uri.encodeComponent(query)}');
      final res = await _client.get(url);
      if (res.statusCode == 200) {
        final body = res.body;
        final start = body.indexOf('([');
        final end = body.lastIndexOf('])');
        if (start != -1 && end != -1) {
          final jsonStr = body.substring(start + 1, end + 1);
          final dynamic parsed = jsonDecode(jsonStr);
          if (parsed is List && parsed.length > 1 && parsed[1] is List) {
            return (parsed[1] as List)
                .map((item) => item is List && item.isNotEmpty ? item[0].toString() : '')
                .where((s) => s.isNotEmpty)
                .take(12)
                .toList();
          }
        }
      }
    } catch (_) {}
    return [];
  }
}
