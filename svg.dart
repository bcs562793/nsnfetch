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

    page.onResponse.listen((res) {
      if (res.url.contains('pitch-noise')) {
        print('   🎯 pitch-noise yüklendi');
      }
    });

    print('🔍 Sayfa açılıyor...');
    final sw = Stopwatch()..start();
    await page.goto(fullUrl, wait: Until.networkIdle, timeout: const Duration(seconds: 40));
    print('   ✅ Sayfa yüklendi (${sw.elapsedMilliseconds}ms)');

    print('⏳ Render bekleniyor (6s)...');
    await Future.delayed(const Duration(seconds: 6));

    // Pitch container'ını direkt hedef al
    final result = await page.evaluate<Map>('''() => {
      // İlk pitch SVG container
      const container = document.querySelector('.sr-lmt-pitch-soccer-new__svg-container');
      if (!container) {
        // Fallback: viewBox 520x292 olan SVG'yi bul
        const allSvgs = [...document.querySelectorAll('svg')];
        const pitchSvg = allSvgs.find(s => s.getAttribute('viewBox') === '0 0 520 292');
        if (!pitchSvg) return {found: false, reason: 'ne container ne SVG bulundu'};
        return {
          found: true,
          source: 'viewBox fallback',
          svgLength: pitchSvg.outerHTML.length,
          svgPreview: pitchSvg.outerHTML.substring(0, 300),
          viewBox: pitchSvg.getAttribute('viewBox'),
          childCount: pitchSvg.children.length,
          fullSvg: pitchSvg.outerHTML,
        };
      }

      // Container içindeki ilk SVG (top layer - oyuncu pozisyonları)
      const svgs = [...container.querySelectorAll('svg')];
      if (svgs.length === 0) return {found: false, reason: 'container var ama svg yok'};

      // En büyüğü al (pitch zemini + oyuncular)
      const biggest = svgs.reduce((a, b) =>
        a.outerHTML.length > b.outerHTML.length ? a : b
      );

      return {
        found: true,
        source: 'sr-lmt-pitch-soccer-new__svg-container',
        svgCount: svgs.length,
        svgLength: biggest.outerHTML.length,
        svgPreview: biggest.outerHTML.substring(0, 300),
        viewBox: biggest.getAttribute('viewBox'),
        childCount: biggest.children.length,
        fullSvg: biggest.outerHTML,
      };
    }''');

    print('\n══════════ SONUÇ ══════════');
    if (result['found'] == true) {
      print('✅ Pitch SVG alındı!');
      print('   kaynak     : ${result['source']}');
      print('   viewBox    : ${result['viewBox']}');
      print('   childCount : ${result['childCount']}');
      print('   svgLength  : ${result['svgLength']} char');
      if (result['svgCount'] != null) {
        print('   svgCount   : ${result['svgCount']} (container içinde)');
      }
      print('\n--- Preview ---');
      print(result['svgPreview']);
      print('───────────────');

      await File('pitch.svg').writeAsString(result['fullSvg'] as String);
      print('\n💾 Kaydedildi: pitch.svg');
    } else {
      print('❌ ${result['reason']}');
    }

    sw.stop();
    print('\n⏱️  Toplam: ${sw.elapsedMilliseconds}ms');

  } finally {
    await page?.close();
    await browser.close();
    print('🔒 Kapatıldı');
  }
}
