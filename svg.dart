import 'dart:io';
import 'package:puppeteer/puppeteer.dart';

Future<void> main() async {
  const fullUrl = 'https://www.nesine.com/Iddaa/Mac-Merkezi/20260321/2745678/1/2045680#matchId=61624508';

  print('🚀 Browser başlatılıyor...');
  final browser = await puppeteer.launch(
    headless: true,
    executablePath: Platform.environment['CHROME_PATH'],
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
    await page.setViewport(DeviceViewport(width: 1280, height: 900));
    await page.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/122.0.0.0 Safari/537.36',
    );

    await page.setRequestInterception(true);
    page.onRequest.listen((req) {
      final url = req.url;
      if (url.contains('bam.nr-data') || url.contains('google-analytics')) {
        req.abort();
      } else {
        req.continueRequest();
      }
    });

    // pitch-noise yüklendiğinde logla — SVG'nin yakın olduğunu gösterir
    page.onResponse.listen((res) {
      if (res.url.contains('pitch-noise')) {
        print('   🎯 pitch-noise yüklendi → SVG render başlıyor');
      }
    });

    print('🔍 Sayfa açılıyor...');
    final sw = Stopwatch()..start();
    await page.goto(fullUrl, wait: Until.networkIdle, timeout: const Duration(seconds: 40));
    print('   ✅ Sayfa yüklendi (${sw.elapsedMilliseconds}ms)');

    // pitch-noise geldikten sonra SVG DOM'a yazılıyor, biraz bekle
    print('⏳ SVG render bekleniyor (6s)...');
    await Future.delayed(const Duration(seconds: 6));

    // DOM'daki tüm SVG'leri tara
    print('\n🔎 DOM SVG taraması...');
    final svgInfo = await page.evaluate<List>('''() => {
      return [...document.querySelectorAll('svg')].map(svg => ({
        id: svg.id,
        classes: svg.className?.toString() ?? '',
        parentClasses: svg.parentElement?.className?.toString() ?? '',
        width: svg.getAttribute('width'),
        height: svg.getAttribute('height'),
        viewBox: svg.getAttribute('viewBox'),
        childCount: svg.children.length,
        outerLength: svg.outerHTML.length,
        // Pitch SVG'sini tespit et: büyük viewBox veya çok child içeriyorsa
        likelyPitch: svg.children.length > 5 && svg.outerHTML.length > 1000,
      }));
    }''');

    print('   Bulunan SVG sayısı: ${svgInfo.length}');
    for (var i = 0; i < svgInfo.length; i++) {
      final s = svgInfo[i];
      print('   [$i] viewBox=${s['viewBox']} children=${s['childCount']} len=${s['outerLength']} pitch=${s['likelyPitch']}');
      print('       parentClass=${s['parentClasses']}');
    }

    // En büyük SVG'yi al (pitch en büyük olacak)
    print('\n📥 En büyük SVG çekiliyor...');
    final result = await page.evaluate<Map>('''() => {
      const svgs = [...document.querySelectorAll('svg')];
      if (svgs.length === 0) return {found: false, reason: 'hiç svg yok'};

      // En uzun outerHTML'e sahip SVG = pitch
      const biggest = svgs.reduce((a, b) =>
        a.outerHTML.length > b.outerHTML.length ? a : b
      );

      return {
        found: true,
        svgLength: biggest.outerHTML.length,
        svgPreview: biggest.outerHTML.substring(0, 300),
        viewBox: biggest.getAttribute('viewBox'),
        childCount: biggest.children.length,
        parentClass: biggest.parentElement?.className ?? '',
        fullSvg: biggest.outerHTML,
      };
    }''');

    print('\n══════════ SONUÇ ══════════');
    if (result['found'] == true) {
      print('✅ SVG alındı!');
      print('   viewBox    : ${result['viewBox']}');
      print('   childCount : ${result['childCount']}');
      print('   svgLength  : ${result['svgLength']} char');
      print('   parentClass: ${result['parentClass']}');
      print('\n--- Preview ---');
      print(result['svgPreview']);
      print('───────────────');

      await File('pitch.svg').writeAsString(result['fullSvg'] as String);
      print('\n💾 Kaydedildi: pitch.svg (${(result['svgLength'] as int)} char)');
    } else {
      print('❌ ${result['reason']}');
      // Tüm body'yi dump et
      final body = await page.evaluate<String>('() => document.body.innerHTML');
      await File('body_dump.html').writeAsString(body);
      print('📄 body_dump.html kaydedildi (${body.length} char)');
    }

    sw.stop();
    print('\n⏱️  Toplam: ${sw.elapsedMilliseconds}ms');

  } finally {
    await page?.close();
    await browser.close();
    print('🔒 Kapatıldı');
  }
}
