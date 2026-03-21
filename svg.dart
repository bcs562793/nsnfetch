import 'dart:io';
import 'package:puppeteer/puppeteer.dart';

Future<void> main() async {
  final workspace = Platform.environment['GITHUB_WORKSPACE'] ?? '.';

  print('🚀 Browser başlatılıyor...');
  final browser = await puppeteer.launch(
    headless: true,
    executablePath: Platform.environment['CHROME_PATH'],
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
  );

  try {
    final matchUrl = await _getLiveMatchUrl(browser);
    if (matchUrl == null) {
      print('❌ Canlı maç yok');
      exit(1);
    }
    print('🎯 URL: $matchUrl');
    await _screenshot(browser, matchUrl, workspace);
  } catch (e, s) {
    print('💥 $e\n$s');
    exit(1);
  } finally {
    await browser.close();
  }
}

Future<String?> _getLiveMatchUrl(Browser browser) async {
  Page? page;
  try {
    page = await browser.newPage();
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36');
    await page.setRequestInterception(true);
    page.onRequest.listen((req) {
      if (req.url.contains('bam.nr-data') || req.url.endsWith('.woff2')) req.abort();
      else req.continueRequest();
    });
    await page.goto('https://www.nesine.com/iddaa/canli-iddaa-canli-bahis?et=0&le=2',
        wait: Until.networkIdle, timeout: const Duration(seconds: 30));
    await Future.delayed(const Duration(seconds: 3));
    final links = await page.evaluate<List>('''() => {
      return [...document.querySelectorAll('a[href*="code="][href*="let="]')]
        .map(a => a.href).filter(h => h.includes('canli-iddaa'));
    }''');
    print('   Link sayısı: ${links.length}');
    if (links.isEmpty) return null;
    return links.first as String;
  } finally {
    await page?.close();
  }
}

Future<void> _screenshot(Browser browser, String matchUrl, String workspace) async {
  Page? page;
  try {
    page = await browser.newPage();
    await page.setViewport(DeviceViewport(width: 1280, height: 900));
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36');
    await page.setRequestInterception(true);
    page.onRequest.listen((req) {
      if (req.url.contains('bam.nr-data')) req.abort();
      else req.continueRequest();
    });
    page.onResponse.listen((res) {
      if (res.url.contains('pitch-noise')) print('   🎯 pitch-noise yüklendi');
    });

    await page.goto(matchUrl, wait: Until.networkIdle, timeout: const Duration(seconds: 40));
    print('   ✅ Yüklendi → ${page.url}');
    await Future.delayed(const Duration(seconds: 8));

    // Pitch container bounding box
    final box = await page.evaluate<Map>('''() => {
      const el = document.querySelector('.sr-lmt-pitch-soccer-new__svg-container')
               ?? document.querySelector('[class*="lmt-pitch"]');
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return {x: r.x, y: r.y, width: r.width, height: r.height};
    }''');

    if (box == null) {
      print('❌ Container bulunamadı, tam sayfa alınıyor');
      await page.screenshot(output: File('$workspace/pitch_full.png').openWrite(), fullPage: false);
      return;
    }

    print('   📐 Box: ${box['x']},${box['y']} ${box['width']}x${box['height']}');

    final pngPath = '$workspace/pitch.png';
    await page.screenshot(
      output: File(pngPath).openWrite(),
      clip: Rectangle(
        (box['x'] as num).toDouble(),
        (box['y'] as num).toDouble(),
        (box['width'] as num).toDouble(),
        (box['height'] as num).toDouble(),
      ),
    );

    final size = await File(pngPath).length();
    print('💾 Kaydedildi: $pngPath ($size byte)');
  } finally {
    await page?.close();
  }
}
