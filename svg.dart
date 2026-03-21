import 'dart:io';
import 'package:puppeteer/puppeteer.dart';

Future<void> main() async {
  const bid = 2046227;

  print('═══════════════════════════════════════');
  print('🚀 [1/6] Browser başlatılıyor...');
  print('═══════════════════════════════════════');

  final browser = await puppeteer.launch(
    headless: true,
    executablePath: Platform.environment['CHROME_PATH'], // Actions'daki chrome
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
    ],
  );
  print('   ✅ Browser açık');

  Page? page;
  try {
    page = await browser.newPage();
    print('\n[2/6] User-agent ayarlanıyor...');

    await page.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/122.0.0.0 Safari/537.36',
    );

    // Gereksiz istekleri engelle
    await page.setRequestInterception(true);
    page.onRequest.listen((req) {
      final url = req.url;
      if (url.contains('bam.nr-data') ||
          url.contains('google-analytics') ||
          url.endsWith('.woff2') ||
          url.endsWith('.woff')) {
        req.abort();
      } else {
        req.continueRequest();
      }
    });

    // Tüm network isteklerini logla
    page.onResponse.listen((res) {
      final url = res.url;
      if (url.contains('sportradar') || url.contains('betradar') || url.contains('nesine')) {
        final status = res.status;
        final icon = status == 200 ? '✅' : status == 304 ? '♻️' : '❌';
        print('   $icon [${res.status}] $url');
      }
    });

    // Console loglarını yakala
    page.onConsole.listen((msg) {
      print('   🖥️  CONSOLE [${msg.type}]: ${msg.text}');
    });

    // JS hatalarını yakala
    page.onPageError.listen((err) {
      print('   💥 PAGE ERROR: $err');
    });

    print('\n[3/6] Sayfa açılıyor: bid=$bid');
    final sw = Stopwatch()..start();

    await page.goto(
      'https://www.nesine.com/canli-sonuclar/mac-detay/$bid',
      wait: Until.networkIdle,
      timeout: const Duration(seconds: 30),
    );
    print('   ✅ Sayfa yüklendi (${sw.elapsedMilliseconds}ms)');

    print('\n[4/6] .sr-lmt-1-pitchbox__container bekleniyor...');
    try {
      await page.waitForSelector(
        '.sr-lmt-1-pitchbox__container',
        timeout: const Duration(seconds: 20),
      );
      print('   ✅ Container bulundu (${sw.elapsedMilliseconds}ms)');
    } catch (e) {
      print('   ❌ Container gelmedi: $e');
      print('\n--- Sayfadaki class\'lar ---');
      final classes = await page.evaluate<List>('''() => {
        return [...document.querySelectorAll('[class]')]
          .map(el => el.className)
          .filter(c => c.includes('sr-') || c.includes('srm-') || c.includes('lmt'))
          .slice(0, 20);
      }''');
      for (final c in classes) print('   · $c');
      print('---');

      // Body snapshot
      final body = await page.evaluate<String>('() => document.body.innerHTML');
      print('\n--- BODY snapshot (ilk 800 char) ---');
      print(body.substring(0, body.length.clamp(0, 800)));
      print('---');
      return;
    }

    print('\n[5/6] SVG render bekleniyor (3s)...');
    await Future.delayed(const Duration(seconds: 3));

    print('\n[6/6] SVG çekiliyor...');
    final result = await page.evaluate<Map>('''() => {
      const container = document.querySelector('.sr-lmt-1-pitchbox__container');
      if (!container) return {found: false, reason: "container kayboldu"};

      const svg = container.querySelector("svg");
      if (!svg) {
        return {
          found: false,
          reason: "svg yok",
          containerHtml: container.innerHTML.substring(0, 300),
          containerClasses: container.className,
        };
      }

      return {
        found: true,
        svgLength: svg.outerHTML.length,
        svgPreview: svg.outerHTML.substring(0, 400),
        viewBox: svg.getAttribute("viewBox"),
        width: svg.getAttribute("width"),
        height: svg.getAttribute("height"),
        childCount: svg.children.length,
      };
    }''');

    print('\n══════════ SONUÇ ══════════');
    if (result['found'] == true) {
      print('✅ SVG başarıyla alındı!');
      print('   viewBox    : ${result['viewBox']}');
      print('   width      : ${result['width']}');
      print('   height     : ${result['height']}');
      print('   childCount : ${result['childCount']}');
      print('   svgLength  : ${result['svgLength']} char');
      print('\n--- SVG Preview (ilk 400 char) ---');
      print(result['svgPreview']);
      print('──────────────────────────────────');

      final fullSvg = await page.evaluate<String>('''() =>
        document.querySelector(".sr-lmt-1-pitchbox__container svg").outerHTML
      ''');
      final file = File('pitch_$bid.svg');
      await file.writeAsString(fullSvg);
      print('\n💾 Dosya kaydedildi: pitch_$bid.svg (${fullSvg.length} char)');
    } else {
      print('❌ SVG alınamadı!');
      print('   Sebep: ${result['reason']}');
      if (result['containerClasses'] != null) {
        print('   Container classes: ${result['containerClasses']}');
      }
      if (result['containerHtml'] != null) {
        print('   Container HTML: ${result['containerHtml']}');
      }
    }

    sw.stop();
    print('\n⏱️  Toplam süre: ${sw.elapsedMilliseconds}ms');

  } finally {
    await page?.close();
    await browser.close();
    print('🔒 Browser kapatıldı');
  }
}
