import json
import subprocess
import requests
from flask import Flask, request, jsonify, Response, stream_with_context
from flask_cors import CORS
import yt_dlp

app = Flask(__name__)
CORS(app)

FFMPEG_PATH = r"C:\Users\pc\Downloads\LosslessCut-win-x64\resources\ffmpeg.exe"

YDL_BASE_OPTS = {
    'quiet': True,
    'no_warnings': True,
    'format': 'bestaudio/best',
    'extractor_args': {'youtube': {'player_client': ['android', 'ios']}}
}

# 1. CANLI ARAMA ÖNERİLERİ
@app.route('/suggest')
def suggest():
    q = request.args.get('q', '')
    if not q:
        return jsonify([])
    try:
        url = f"https://suggestqueries-clients6.youtube.com/complete/search?client=youtube&ds=yt&q={q}"
        headers = {'User-Agent': 'Mozilla/5.0'}
        r = requests.get(url, headers=headers, timeout=5)
        text = r.text
        start = text.find('[')
        end = text.rfind(']')
        if start != -1 and end != -1:
            data = json.loads(text[start:end+1])
            if len(data) > 1 and isinstance(data[1], list):
                return jsonify([item[0] for item in data[1]])
    except Exception as e:
        print("Suggest error:", e)
    return jsonify([])

# 2. MÜZİK ARAMASI
@app.route('/search')
def search():
    q = request.args.get('q', '')
    if not q:
        return jsonify([])
    try:
        opts = dict(YDL_BASE_OPTS)
        opts['extract_flat'] = True
        opts['skip_download'] = True
        with yt_dlp.YoutubeDL(opts) as ydl:
            res = ydl.extract_info(f"ytsearch25:{q}", download=False)
            results = []
            if 'entries' in res:
                for entry in res['entries']:
                    duration_sec = entry.get('duration') or 0
                    mins = int(duration_sec // 60)
                    secs = int(duration_sec % 60)
                    results.append({
                        'id': entry.get('id', ''),
                        'title': entry.get('title', ''),
                        'artist': entry.get('uploader', '') or entry.get('channel', ''),
                        'duration': f"{mins}:{secs:02d}",
                        'thumbnailUrl': f"https://i.ytimg.com/vi/{entry.get('id')}/hqdefault.jpg"
                    })
            return jsonify(results)
    except Exception as e:
        print("Search error:", e)
        return jsonify([])

# 3. İLERİ / GERİ SARILABİLİR SES OYNATICI
@app.route('/audio/<video_id>')
def audio_stream(video_id):
    try:
        opts = dict(YDL_BASE_OPTS)
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
            stream_url = info.get('url')
            http_headers = info.get('http_headers', {'User-Agent': 'Mozilla/5.0'})

        req_range = request.headers.get('Range', None)
        if req_range:
            http_headers['Range'] = req_range

        req = requests.get(stream_url, headers=http_headers, stream=True, allow_redirects=True, timeout=20)
        
        resp_headers = {
            'Content-Type': req.headers.get('Content-Type', 'audio/mp4'),
            'Accept-Ranges': 'bytes',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Expose-Headers': 'Content-Range, Content-Length, Accept-Ranges'
        }
        if 'Content-Range' in req.headers:
            resp_headers['Content-Range'] = req.headers['Content-Range']
        if 'Content-Length' in req.headers:
            resp_headers['Content-Length'] = req.headers['Content-Length']

        return Response(
            stream_with_context(req.iter_content(chunk_size=65536)),
            status=req.status_code,
            headers=resp_headers
        )
    except Exception as e:
        print("Audio stream error:", e)
        return jsonify({'error': str(e)}), 500

# 4. HIZLI ORİJİNAL M4A İNDİRME
@app.route('/download/<video_id>')
def download_m4a(video_id):
    try:
        opts = dict(YDL_BASE_OPTS)
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
            stream_url = info.get('url')
            http_headers = info.get('http_headers', {'User-Agent': 'Mozilla/5.0'})
            title = info.get('title', 'music').replace('/', '_').replace('\\', '_').replace('"', '')
            ext = info.get('ext', 'm4a')

        req = requests.get(stream_url, headers=http_headers, stream=True, allow_redirects=True, timeout=20)
        resp_headers = {
            'Content-Type': 'application/octet-stream',
            'Content-Disposition': f'attachment; filename="{title}.{ext}"',
            'Access-Control-Allow-Origin': '*',
        }
        return Response(
            stream_with_context(req.iter_content(chunk_size=131072)),
            headers=resp_headers
        )
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# 5. GERÇEK MP3 DÖNÜŞTÜRÜCÜ İNDİRME (FFMPEG LAME MP3 320 KBPS)
@app.route('/download_mp3/<video_id>')
def download_mp3(video_id):
    try:
        opts = dict(YDL_BASE_OPTS)
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
            stream_url = info.get('url')
            http_headers = info.get('http_headers', {'User-Agent': 'Mozilla/5.0'})
            title = info.get('title', 'music').replace('/', '_').replace('\\', '_').replace('"', '')

        # YouTube ses akışını alıp doğrudan FFmpeg'e boruluyoruz
        req = requests.get(stream_url, headers=http_headers, stream=True, allow_redirects=True, timeout=20)
        
        # FFmpeg ile anlık saf MP3 çıktısı alıyoruz (pipe:0 -> pipe:1)
        ffmpeg_cmd = [
            FFMPEG_PATH,
            '-hide_banner',
            '-loglevel', 'error',
            '-i', 'pipe:0',
            '-vn',
            '-c:a', 'libmp3lame',
            '-b:a', '320k',
            '-f', 'mp3',
            'pipe:1'
        ]
        proc = subprocess.Popen(
            ffmpeg_cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=65536
        )

        def generate_mp3():
            import threading
            def feed_input():
                try:
                    for chunk in req.iter_content(chunk_size=65536):
                        if chunk:
                            proc.stdin.write(chunk)
                    proc.stdin.close()
                except Exception as e:
                    print("Feed input error:", e)

            # Giriş beslemesini ayrı thread'de çalıştırıp çıkışı eşzamanlı aktar
            t = threading.Thread(target=feed_input)
            t.start()

            while True:
                data = proc.stdout.read(65536)
                if not data:
                    break
                yield data
            proc.stdout.close()
            t.join()

        resp_headers = {
            'Content-Type': 'audio/mpeg',
            'Content-Disposition': f'attachment; filename="{title}.mp3"',
            'Access-Control-Allow-Origin': '*',
        }
        return Response(stream_with_context(generate_mp3()), headers=resp_headers)
    except Exception as e:
        print("MP3 conversion error:", e)
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    print("MP3 Pro Music Proxy Server running on port 5050...")
    app.run(host='127.0.0.1', port=5050, debug=False, threaded=True)
