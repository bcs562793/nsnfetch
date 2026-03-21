import 'dart:io';
import 'package:puppeteer/puppeteer.dart';

// URL formatı: /Iddaa/Mac-Merkezi/{tarih}/{bultinId}/{tip}/{bid}#matchId={sportradarId}
// Bizim için sadece bid yeterli — sayfayı açınca widget render oluyor
// Ama URL'yi tam bilmiyoruz, canli-sonuclar üzerinden deneyelim

Future<void> main() async {
  // Screenshot'taki URL'den aldık
  const fullUrl = 'https://www.nesine.com/Iddaa/Mac-Merkezi/20260321/2745678/1/2045680#matchId=61624508';

  print('═══════════════════════════════════════');
  print('🚀 [1/6] Browser başlatılıyor...');

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
  print('   ✅ Browser açık');

  Page? page;
  try {
    page = await browser.newPage();

    // Ekran boyutu — widget responsive olabilir
    await page.setViewport(DeviceViewport(width: 1280, height: 900));

    await page.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/122.0.0.0 Safari/537.36',
    );

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

    // Sportradar isteklerini logla
    page.onResponse.listen((res) {
      final url = res.url;
      if (url.contains('sportradar') || url.contains('betradar')) {
        final icon = res.status == 200 ? '✅' : res.status == 304 ? '♻️' : '❌';
        print('   $icon [${res.status}] $url');
      }
    });

    page.onConsole.listen((msg) {
      if (msg.type == 'error') {
        print('   🖥️  CONSOLE ERROR: ${msg.text}');
      }
    });

    print('\n[2/6] Sayfa açılıyor...');
    print('   URL: $fullUrl');
    final sw = Stopwatch()..start();

    await page.goto(
      fullUrl,
      wait: Until.networkIdle,
      timeout: const Duration(seconds: 30),
    );
    print('   ✅ Sayfa yüklendi (${sw.elapsedMilliseconds}ms)');

    // DOM'daki tüm srl-* class'larını logla
    print('\n[3/6] DOM\'daki widget class\'ları taranıyor...');
    final classes = await page.evaluate<List>('''() => {
      return [...document.querySelectorAll('[class]')]
        .flatMap(el => el.className.toString().split(' '))
        .filter(c => c.startsWith('srl-') || c.startsWith('sr-') || c.startsWith('srm-') || c.startsWith('lmt'))
        .filter((v, i, a) => a.indexOf(v) === i)
        .slice(0, 30);
    }''');
    print('   Bulunan class\'lar:');
    for (final c in classes) print('     · $c');

    // Yeni selector'ları dene
    final selectors = [
      '.srl-lmt-live-container',
      '.srl-lmt-wrapper',
      '.sr-lmt-1-pitchbox__container',
      '.srm-pitchview',
    ];

    String? foundSelector;
    print('\n[4/6] Selector deneniyor...');
    for (final sel in selectors) {
      try {
        await page.waitForSelector(sel, timeout: const Duration(seconds: 15));
        print('   ✅ Bulundu: $sel');
        foundSelector = sel;
        break;
      } catch (_) {
        print('   ❌ Bulunamadı: $sel');
      }
    }

    if (foundSelector == null) {
      print('\n❌ Hiçbir selector çalışmadı!');
      final body = await page.evaluate<String>('() => document.body.innerHTML');
      print('--- BODY snapshot (ilk 1000 char) ---');
      print(body.substring(0, body.length.clamp(0, 1000)));
      return;
    }

    print('\n[5/6] SVG render bekleniyor (3s)...');
    await Future.delayed(const Duration(seconds: 3));

    print('\n[6/6] SVG çekiliyor...');
    final result = await page.evaluate<Map>('''() => {
      const selectors = [
        '.srl-lmt-live-container',
        '.srl-lmt-wrapper',
        '.sr-lmt-1-pitchbox__container',
      ];

      let container = null;
      let usedSel = '';
      for (const sel of selectors) {
        container = document.querySelector(sel);
        if (container) { usedSel = sel; break; }
      }

      if (!container) return {found: false, reason: 'container yok'};

      const svg = container.querySelector('svg');
      if (!svg) {
        return {
          found: false,
          reason: 'svg yok (' + usedSel + ')',
          containerHtml: container.innerHTML.substring(0, 500),
        };
      }

      return {
        found: true,
        selector: usedSel,
        svgLength: svg.outerHTML.length,
        svgPreview: svg.outerHTML.substring(0, 400),
        viewBox: svg.getAttribute('viewBox'),
        width: svg.getAttribute('width'),
        height: svg.getAttribute('height'),
        childCount: svg.children.length,
        fullSvg: svg.outerHTML,
      };
    }''');

    print('\n══════════ SONUÇ ══════════');
    if (result['found'] == true) {
      print('✅ SVG başarıyla alındı!');
      print('   selector   : ${result['selector']}');
      print('   viewBox    : ${result['viewBox']}');
      print('   width      : ${result['width']}');
      print('   height     : ${result['height']}');
      print('   childCount : ${result['childCount']}');
      print('   svgLength  : ${result['svgLength']} char');
      print('\n--- SVG Preview ---');
      print(result['svgPreview']);
      print('───────────────────');

      final file = File('pitch.svg');
      await file.writeAsString(result['fullSvg'] as String);
      print('\n💾 Kaydedildi: pitch.svg');
    } else {
      print('❌ SVG alınamadı: ${result['reason']}');
      if (result['containerHtml'] != null) {
        print('Container HTML: ${result['containerHtml']}');
      }
    }

    sw.stop();
    print('\n⏱️  Toplam: ${sw.elapsedMilliseconds}ms');

  } finally {
    await page?.close();
    await browser.close();
    print('🔒 Browser kapatıldı');
  }
}
