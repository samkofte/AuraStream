# 🎵 AuraStream — High Performance Music Streaming & Offline Engine

> **AuraStream**, harici API anahtarlarına ve ağır FFmpeg kütüphanelerine ihtiyaç duymadan, doğrudan en optimize ses akışlarını (M4A/AAC/Opus) yakalayan, anlık arama önerileri sunan ve cihaz işlemcisini yormayan yeni nesil açık kaynaklı müzik oynatıcı ve indirme motorudur.

---

## 🚀 Öne Çıkan Özellikler (Key Features)

- ⚡ **Anlık Harf Harf Arama (Live Autocomplete):** Arama kutusuna her harf girildiğinde 200 ms Debounce ile çalışan canlı arama tamamlama motoru.
- 🎛️ **API Anahtarsız ve Kotasız Mimari:** Herhangi bir Google Cloud Console veya üçüncü parti API kotasına bağlı kalmadan doğrudan istemci üzerinden çalışan InnerTube motoru.
- 🚫 **FFmpeg'siz Hafif Mimari:** Ağır harici video/ses dönüştürücüleri kullanmaz. YouTube ve açık platformların sunduğu saf **AAC/M4A** ses akışlarını doğrudan işler; bataryayı tüketmez, cihazı ısıtmaz.
- ⏩ **Kesintisiz Oynatma ve İleri/Geri Sarma:** HTTP 206 Partial Content desteği ile saniye bazında anında sarma (`seek`) ve dijital canlı sayaç.
- 📦 **Çoklu İndirme Desteği:**
  - **Turbo M4A:** Sıfır yeniden kodlama, maksimum hat hızıyla anında indirme.
  - **Evrensel MP3:** Eski teypler ve araç içi medya sistemleri için yerleşik kodlama desteği.
- 📑 **Dahili İndirme Yöneticisi (Downloads Tab):** İndirilen parçaları tek dokunuşla çevrimdışı dinleme, silme ve yönetme.

---

## 🛠️ Mimari ve Teknolojiler

| Katman | Kullanılan Teknoloji | Açıklama |
| :--- | :--- | :--- |
| **Ön Yüz (Mobile/Web)** | **Flutter 3.x (Dart)** | Koyu mod (Spotify/LMR tarzı) modern UI |
| **Oynatıcı Motoru** | `just_audio` / `media3` | Düşük gecikmeli yerel ses akışı |
| **Arama Motoru** | `youtube_explode_dart` & InnerTube | Kotasız canlı arama motoru |
| **Yerel Proxy (Web İçin)** | `Python (Flask-CORS)` | Web tarayıcılarında CORS engelini aşan hafif köprü |

---

## 📂 Proje Dizin Yapısı

```text
lfm_music_app/
│
├── lib/
│   └── main.dart            # Flutter ön yüzü (Canlı Arama, Player Bar, İndirme Listesi)
├── server.py                # Web ortamı için hafif CORS & Turbo ses akış proxy'si
├── pubspec.yaml             # Flutter bağımlılıkları
└── README.md                # Proje dokümantasyonu
```

---

## 💻 Kurulum ve Çalıştırma

### 1. Web Ortamında Çalıştırma

Önce web tarayıcısının CORS kısıtlamasına takılmaması için yerel köprüyü başlatın:

```bash
# Gerekli Python kütüphanelerini yükleyin
pip install flask flask-cors yt-dlp requests

# Yerel akış servisini başlatın
python server.py
```

Ardından yeni bir terminalde Flutter Web uygulamasını çalıştırın:

```bash
cd lfm_music_app
flutter run -d web-server --web-port 8085 --web-hostname 127.0.0.1
```

Tarayıcınızdan **`http://127.0.0.1:8085`** adresine giderek kullanmaya başlayabilirsiniz.

---

### 2. Android APK Olarak Derleme (Mobil Kurulum)

Mobil cihazlarda harici bir proxy sunucusuna (`server.py`) **ihtiyaç duyulmaz**. Uygulama doğrudan telefonun Wi-Fi / Hücresel verisi üzerinden NewPipe / YouTubeExplode motoruyla çalışır:

```bash
cd lfm_music_app
flutter build apk --release
```

Çıkan APK dosyası: `build/app/outputs/flutter-apk/app-release.apk`

---

## ⚖️ Yasal Uyarı (Disclaimer)

Bu proje eğitim ve tersine mühendislik araştırma amaçlarıyla geliştirilmiştir. Kullanıcıların telif hakkı sahiplerinin haklarına saygı göstermesi ve yalnızca telifsiz (Creative Commons / Royalty-Free) içeriklerde kullanması tavsiye edilir.

---

## 📄 Lisans

Bu proje [MIT Lisansı](LICENSE) kapsamında açık kaynak olarak sunulmuştur.
