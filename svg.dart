import 'dart:io';
import 'package:puppeteer/puppeteer.dart';

// dart pub add puppeteer
// dart run pitch_svg_test.dart

Future<void> main() async {
  const bid = 2046227;

  print('🚀 Browser başlatılıyor...');
  final browser = await puppeteer.launch(
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
    ],
  );

  Page? page;
  try {
    page = await browser.newPage();

    await page.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/122.0.0.0 Safari/537.36',
    );

    // Gereksiz istekleri engelle → daha hızlı yüklensin
    await page.setRequestInterception(true);
    page.onRequest.listen((req) {
      final url = req.url;
      if (url.contains('bam.nr-data') ||
          url.contains('google') ||
          url.contains('.gif') ||
          url.endsWith('.woff2') ||
          url.endsWith('.woff')) {
        req.abort();
      } else {
        req.continueRequest();
      }
    });

    // Her isteği logla — hangi domain'ler çağrılıyor görelim
    page.onResponse.listen((res) {
      final url = res.url;
      if (url.contains('sportradar') || url.contains('betradar')) {
        print('   📡 ${res.status} $url');
      }
    });

    print('🔍 Sayfa açılıyor: bid=$bid');
    final stopwatch = Stopwatch()..start();

    await page.goto(
      'https://www.nesine.com/canli-sonuclar/mac-detay/$bid',
      wait: Until.networkIdle,
      timeout: const Duration(seconds: 30),
    );

    print('   ✅ Sayfa yüklendi (${stopwatch.elapsedMilliseconds}ms)');

    // Container'ı bekle
    print('⏳ .sr-lmt-1-pitchbox__container bekleniyor...');
    try {
      await page.waitForSelector(
        '.sr-lmt-1-pitchbox__container',
        timeout: const Duration(seconds: 20),
      );
      print('   ✅ Container bulundu (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      print('   ❌ Container gelmedi: $e');

      // Ne geldi görelim
      final body = await page.evaluate<String>('() => document.body.innerHTML');
      print('\n--- BODY (ilk 500 char) ---');
      print(body.substring(0, body.length.clamp(0, 500)));
      print('---\n');
      return;
    }

    // Render için bekle
    await Future.delayed(const Duration(seconds: 3));

    // SVG'yi çek
    final result = await page.evaluate<Map>('''() => {
      const container = document.querySelector('.sr-lmt-1-pitchbox__container');
      if (!container) return {found: false, reason: 'container yok'};

      const svg = container.querySelector('svg');
      if (!svg) {
        return {
          found: false,
          reason: 'svg yok',
          containerHtml: container.innerHTML.substring(0, 200)
        };
      }

      return {
        found: true,
        svgLength: svg.outerHTML.length,
        svgPreview: svg.outerHTML.substring(0, 300),
        viewBox: svg.getAttribute('viewBox'),
        childCount: svg.children.length,
      };
    }''');

    print('\n══════════ SONUÇ ══════════');
    if (result['found'] == true) {
      print('✅ SVG bulundu!');
      print('   viewBox   : ${result['viewBox']}');
      print('   childCount: ${result['childCount']}');
      print('   svgLength : ${result['svgLength']} char');
      print('\n--- SVG Preview ---');
      print(result['svgPreview']);
      print('───────────────────');

      // Dosyaya kaydet
      final file = File('pitch_$bid.svg');
      final fullSvg = await page.evaluate<String>('''() => {
        return document.querySelector('.sr-lmt-1-pitchbox__container svg').outerHTML;
      }''');
      await file.writeAsString(fullSvg);
      print('\n💾 Kaydedildi: pitch_$bid.svg');
    } else {
      print('❌ SVG alınamadı: ${result['reason']}');
      if (result['containerHtml'] != null) {
        print('   Container içeriği: ${result['containerHtml']}');
      }
    }

    stopwatch.stop();
    print('\n⏱️  Toplam süre: ${stopwatch.elapsedMilliseconds}ms');

  } finally {
    await page?.close();
    await browser.close();
  }
}
