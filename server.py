import json
import subprocess
import requests
import urllib.parse
from flask import Flask, request, jsonify, Response, stream_with_context
from flask_cors import CORS
import yt_dlp

app = Flask(__name__)
CORS(app)

FFMPEG_PATH = r"C:\Users\pc\Downloads\LosslessCut-win-x64\resources\ffmpeg.exe"

YDL_BASE_OPTS = {
    'quiet': True,
    'no_warnings': True,
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

# 2. MÜZİK VE VİDEO ARAMASI (InnerTube)
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

# 3. MAKSİMUM KALİTEDE SES AKIŞI (Oynatma - 160 kbps / En Yüksek Kalite)
@app.route('/audio/<video_id>')
def audio_stream(video_id):
    try:
        opts = dict(YDL_BASE_OPTS)
        opts['format'] = 'bestaudio/best'
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

# 4. MAKSİMUM SES İNDİRME (160 kbps Doğrudan En Yüksek Kalite)
@app.route('/download_audio_max/<video_id>')
def download_audio_max(video_id):
    try:
        opts = dict(YDL_BASE_OPTS)
        opts['format'] = 'bestaudio/best'
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
            stream_url = info.get('url')
            http_headers = info.get('http_headers', {'User-Agent': 'Mozilla/5.0'})
            title = info.get('title', 'music').replace('/', '_').replace('\\', '_').replace('"', '')
            ext = info.get('ext', 'm4a')

        req = requests.get(stream_url, headers=http_headers, stream=True, allow_redirects=True, timeout=20)
        encoded_title = urllib.parse.quote(f"{title}.{ext}")
        resp_headers = {
            'Content-Type': 'application/octet-stream',
            'Content-Disposition': f"attachment; filename*=UTF-8''{encoded_title}",
            'Access-Control-Allow-Origin': '*',
        }
        return Response(
            stream_with_context(req.iter_content(chunk_size=131072)),
            headers=resp_headers
        )
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# 5. MAKSİMUM VİDEO İNDİRME (720p HD Sesli MP4)
@app.route('/download_video_max/<video_id>')
def download_video_max(video_id):
    try:
        opts = dict(YDL_BASE_OPTS)
        # Ekstra işlem gerektirmeden en yüksek sesli video (720p HD MP4)
        opts['format'] = 'best[ext=mp4]/best'
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
            stream_url = info.get('url')
            http_headers = info.get('http_headers', {'User-Agent': 'Mozilla/5.0'})
            title = info.get('title', 'video').replace('/', '_').replace('\\', '_').replace('"', '')

        req = requests.get(stream_url, headers=http_headers, stream=True, allow_redirects=True, timeout=25)
        encoded_title = urllib.parse.quote(f"{title} [720p HD].mp4")
        resp_headers = {
            'Content-Type': 'video/mp4',
            'Content-Disposition': f"attachment; filename*=UTF-8''{encoded_title}",
            'Access-Control-Allow-Origin': '*',
        }
        return Response(
            stream_with_context(req.iter_content(chunk_size=262144)),
            headers=resp_headers
        )
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# 6. GERÇEK 320 KBPS MP3 İNDİRME
@app.route('/download_mp3/<video_id>')
def download_mp3(video_id):
    try:
        opts = dict(YDL_BASE_OPTS)
        opts['format'] = 'bestaudio/best'
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
            stream_url = info.get('url')
            http_headers = info.get('http_headers', {'User-Agent': 'Mozilla/5.0'})
            title = info.get('title', 'music').replace('/', '_').replace('\\', '_').replace('"', '')

        req = requests.get(stream_url, headers=http_headers, stream=True, allow_redirects=True, timeout=20)
        
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

            t = threading.Thread(target=feed_input)
            t.start()

            while True:
                data = proc.stdout.read(65536)
                if not data:
                    break
                yield data
            proc.stdout.close()
            t.join()

        encoded_title = urllib.parse.quote(f"{title}.mp3")
        resp_headers = {
            'Content-Type': 'audio/mpeg',
            'Content-Disposition': f"attachment; filename*=UTF-8''{encoded_title}",
            'Access-Control-Allow-Origin': '*',
        }
        return Response(stream_with_context(generate_mp3()), headers=resp_headers)
    except Exception as e:
        print("MP3 conversion error:", e)
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    print("AuraStream Max Quality Proxy Server running on port 5050...")
    app.run(host='127.0.0.1', port=5050, debug=False, threaded=True)
