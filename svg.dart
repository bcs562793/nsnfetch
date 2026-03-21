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
    final matchUrl = await _getLiveMatchUrl(browser);
    if (matchUrl == null) {
      await File(outPath).writeAsString('<svg xmlns="http://www.w3.org/2000/svg"><text y="20">Canli mac yok</text></svg>');
      exit(1);
    }
    print('🎯 URL: $matchUrl');

    final svg = await _fetchPitchSvg(browser, matchUrl, outPath);
    if (svg == null) exit(1);

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

Future<String?> _fetchPitchSvg(Browser browser, String matchUrl, String outPath) async {
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
    print('   ✅ Sayfa yüklendi → ${page.url}');
    await Future.delayed(const Duration(seconds: 8));

    // Her iki SVG'yi ayrı ayrı al, debug için kaydet
    final result = await page.evaluate<Map>('''() => {
      const container = document.querySelector('.sr-lmt-pitch-soccer-new__svg-container');
      if (!container) return {found: false, reason: 'container yok'};

      const svgs = [...container.querySelectorAll('svg')];
      if (svgs.length === 0) return {found: false, reason: 'svg yok'};

      // Debug: her SVG'nin içeriği
      const debug = svgs.map((s, i) => ({
        index: i,
        len: s.outerHTML.length,
        viewBox: s.getAttribute('viewBox'),
        class: s.getAttribute('class'),
        childCount: s.children.length,
        preview: s.outerHTML.substring(0, 100),
      }));

      // SVG'leri tek bir SVG içinde üst üste koy — foreignObject yerine
      // Her SVG'nin içeriğini wrapper SVG'ye ekle
      const wrapper = svgs[0].cloneNode(true);
      // wrapper'daki defs'i koru, diğer svglerin içeriğini ekle
      for (let i = 1; i < svgs.length; i++) {
        const s = svgs[i];
        // defs varsa wrapper defs'e ekle
        const srcDefs = s.querySelector('defs');
        const dstDefs = wrapper.querySelector('defs');
        if (srcDefs && dstDefs) {
          [...srcDefs.children].forEach(c => dstDefs.appendChild(c.cloneNode(true)));
        } else if (srcDefs) {
          wrapper.appendChild(srcDefs.cloneNode(true));
        }
        // defs dışındaki elementleri ekle
        [...s.children].forEach(child => {
          if (child.tagName !== 'defs') {
            wrapper.appendChild(child.cloneNode(true));
          }
        });
      }

      return {
        found: true,
        svgCount: svgs.length,
        debug: debug,
        fullSvg: wrapper.outerHTML,
        svgLength: wrapper.outerHTML.length,
      };
    }''');

    if (result['found'] != true) {
      print('❌ ${result['reason']}');
      return null;
    }

    // Debug bilgisi
    print('   SVG katman sayısı: ${result['svgCount']}');
    final debugList = result['debug'] as List;
    for (final d in debugList) {
      print('   [${d['index']}] class=${d['class']} len=${d['len']} children=${d['childCount']}');
      print('        preview: ${d['preview']}');
    }

    return result['fullSvg'] as String;
  } finally {
    await page?.close();
  }
}
