import 'dart:io';
import 'package:puppeteer/puppeteer.dart';

Future<void> main() async {
  final workspace = Platform.environment['GITHUB_WORKSPACE'] ?? '.';
  final outPath = '$workspace/pitch.svg';

  print('🚀 Browser başlatılıyor...');
  final browser = await puppeteer.launch(
    headless: true,
    executablePath: Platform.environment['CHROME_PATH'],
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
  );

  try {
    // ── 1. Canlı maç listesinden URL al ──────────────────────────
    print('\n📡 Canlı maç listesi açılıyor...');
    final matchUrl = await _getLiveMatchUrl(browser);
    if (matchUrl == null) {
      print('❌ Canlı futbol maçı bulunamadı');
      await File(outPath).writeAsString('<svg xmlns="http://www.w3.org/2000/svg"><text y="20">Canli mac yok</text></svg>');
      exit(1);
    }
    print('🎯 Maç URL: $matchUrl');

    // ── 2. Maç sayfasından SVG al ─────────────────────────────────
    final svg = await _fetchPitchSvg(browser, matchUrl);
    if (svg == null) {
      await File(outPath).writeAsString('<svg xmlns="http://www.w3.org/2000/svg"><text y="20">SVG alinamadi</text></svg>');
      exit(1);
    }

    await File(outPath).writeAsString(svg);
    print('💾 Kaydedildi: $outPath (${svg.length} char)');

  } catch (e, s) {
    print('💥 $e\n$s');
    await File(outPath).writeAsString('<svg xmlns="http://www.w3.org/2000/svg"><text y="20">Hata</text></svg>');
    exit(1);
  } finally {
    await browser.close();
  }
}

// ── Canlı maç listesini puppeteer ile aç, ilk maç linkini al ────
Future<String?> _getLiveMatchUrl(Browser browser) async {
  Page? page;
  try {
    page = await browser.newPage();
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36');

    await page.setRequestInterception(true);
    page.onRequest.listen((req) {
      // Sadece HTML ve JS geçsin, rest engellensin
      if (req.url.contains('bam.nr-data') || req.url.contains('google-analytics') ||
          req.url.endsWith('.png') || req.url.endsWith('.jpg') ||
          req.url.endsWith('.woff2') || req.url.endsWith('.woff')) {
        req.abort();
      } else {
        req.continueRequest();
      }
    });

    await page.goto(
      'https://www.nesine.com/iddaa/canli-iddaa-canli-bahis?et=0&le=2',
      wait: Until.networkIdle,
      timeout: const Duration(seconds: 30),
    );

    // Maç linklerinin yüklenmesini bekle
    await Future.delayed(const Duration(seconds: 3));

    // ?code=xxx&let=1 formatındaki linkleri bul
    final links = await page.evaluate<List>('''() => {
      const anchors = [...document.querySelectorAll('a[href*="code="][href*="let="]')];
      return anchors.map(a => a.href).filter(h => h.includes('canli-iddaa'));
    }''');

    print('   Bulunan link sayısı: ${links.length}');

    if (links.isEmpty) {
      // Alternatif: Mac-Merkezi linkleri
      final links2 = await page.evaluate<List>('''() => {
        return [...document.querySelectorAll('a[href*="Mac-Merkezi"]')]
          .map(a => a.href);
      }''');
      print('   Mac-Merkezi link sayısı: ${links2.length}');
      if (links2.isNotEmpty) {
        print('   ✅ ${links2.first}');
        return links2.first as String;
      }

      // Debug: ne var sayfada
      final sample = await page.evaluate<String>('''() => {
        return [...document.querySelectorAll('a')].slice(0, 10).map(a => a.href).join('\\n');
      }''');
      print('   İlk 10 link:\n$sample');
      return null;
    }

    // ?code=xxx&let=1 linkini Mac-Merkezi URL'sine dönüştür
    // Önce bu linki aç, yönlendirme yapıyor mu bak
    final liveLink = links.first as String;
    print('   ✅ Canlı link: $liveLink');
    return liveLink;

  } finally {
    await page?.close();
  }
}

// ── Maç sayfasından pitch SVG'yi al ─────────────────────────────
Future<String?> _fetchPitchSvg(Browser browser, String matchUrl) async {
  Page? page;
  try {
    page = await browser.newPage();
    await page.setViewport(DeviceViewport(width: 1280, height: 900));
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36');

    await page.setRequestInterception(true);
    page.onRequest.listen((req) {
      if (req.url.contains('bam.nr-data') || req.url.contains('google-analytics')) {
        req.abort();
      } else {
        req.continueRequest();
      }
    });
    page.onResponse.listen((res) {
      if (res.url.contains('pitch-noise')) print('   🎯 pitch-noise yüklendi');
    });

    print('🔍 Maç sayfası açılıyor...');
    final sw = Stopwatch()..start();
    await page.goto(matchUrl, wait: Until.networkIdle, timeout: const Duration(seconds: 40));
    print('   ✅ Yüklendi (${sw.elapsedMilliseconds}ms) → ${page.url}');

    print('⏳ SVG render bekleniyor (8s)...');
    await Future.delayed(const Duration(seconds: 8));

    final result = await page.evaluate<Map>('''() => {
      const container = document.querySelector('.sr-lmt-pitch-soccer-new__svg-container');
      if (!container) {
        const count = document.querySelectorAll('svg').length;
        return {found: false, reason: 'container yok (toplam svg: ' + count + ')'};
      }
      const svgs = [...container.querySelectorAll('svg')];
      if (svgs.length === 0) return {found: false, reason: 'container var svg yok'};

      const ground = svgs[0].cloneNode(true);
      if (svgs.length > 1) {
        svgs.slice(1).forEach(s => {
          [...s.children].forEach(child => ground.appendChild(child.cloneNode(true)));
        });
      }
      return {
        found: true,
        source: svgs.length + ' svg',
        svgLength: ground.outerHTML.length,
        viewBox: ground.getAttribute('viewBox'),
        fullSvg: ground.outerHTML,
      };
    }''');

    if (result['found'] == true) {
      print('✅ SVG alındı: ${result['source']} | ${result['svgLength']} char');
      return result['fullSvg'] as String;
    } else {
      print('❌ ${result['reason']}');
      return null;
    }
  } finally {
    await page?.close();
  }
}
