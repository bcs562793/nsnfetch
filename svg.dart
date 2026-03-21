import 'dart:io';
import 'dart:convert';
import 'package:puppeteer/puppeteer.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final workspace = Platform.environment['GITHUB_WORKSPACE'] ?? '.';
  final outPath = '$workspace/pitch.svg';

  print('📡 Canlı maçlar alınıyor...');
  final matchUrl = await _getLiveMatchUrl();
  if (matchUrl == null) {
    print('❌ Canlı futbol maçı bulunamadı');
    await File(outPath).writeAsString('<svg xmlns="http://www.w3.org/2000/svg"><text y="20">Canli mac yok</text></svg>');
    exit(1);
  }
  print('🎯 Maç URL: $matchUrl');

  print('🚀 Browser başlatılıyor...');
  final browser = await puppeteer.launch(
    headless: true,
    executablePath: Platform.environment['CHROME_PATH'],
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
  );

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

    print('🔍 Sayfa açılıyor...');
    final sw = Stopwatch()..start();
    await page.goto(matchUrl, wait: Until.networkIdle, timeout: const Duration(seconds: 40));
    print('   ✅ Yüklendi (${sw.elapsedMilliseconds}ms)');

    print('⏳ Render bekleniyor (8s)...');
    await Future.delayed(const Duration(seconds: 8));

    final result = await page.evaluate<Map>('''() => {
      const container = document.querySelector('.sr-lmt-pitch-soccer-new__svg-container');
      if (!container) {
        const count = document.querySelectorAll('svg').length;
        return {found: false, reason: 'container yok (toplam svg: ' + count + ')'};
      }
      const svgs = [...container.querySelectorAll('svg')];
      if (svgs.length === 0) return {found: false, reason: 'container var svg yok'};

      const ground = svgs[0];
      const combined = ground.cloneNode(true);
      if (svgs.length > 1) {
        svgs.slice(1).forEach(s => {
          [...s.children].forEach(child => combined.appendChild(child.cloneNode(true)));
        });
      }
      return {
        found: true,
        source: svgs.length + ' svg birlestirildi',
        svgLength: combined.outerHTML.length,
        viewBox: combined.getAttribute('viewBox'),
        fullSvg: combined.outerHTML,
      };
    }''');

    if (result['found'] == true) {
      print('✅ SVG: ${result['source']} | ${result['svgLength']} char');
      final file = File(outPath);
      await file.writeAsString(result['fullSvg'] as String);
      print('💾 Kaydedildi: $outPath');
    } else {
      print('❌ ${result['reason']}');
      await File(outPath).writeAsString('<svg xmlns="http://www.w3.org/2000/svg"><text y="20">${result['reason']}</text></svg>');
      exit(1);
    }
  } catch (e, s) {
    print('💥 $e\n$s');
    await File(outPath).writeAsString('<svg xmlns="http://www.w3.org/2000/svg"><text y="20">Hata</text></svg>');
    exit(1);
  } finally {
    await page?.close();
    await browser.close();
  }
}

// Canlı iddaa sayfasından ilk maçın detay URL'sini çek
Future<String?> _getLiveMatchUrl() async {
  try {
    final res = await http.get(
      Uri.parse('https://www.nesine.com/iddaa/canli-iddaa-canli-bahis?et=0&le=2'),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36',
        'Referer': 'https://www.nesine.com/',
        'Accept': 'text/html,application/xhtml+xml',
      },
    ).timeout(const Duration(seconds: 15));

    print('   HTTP: ${res.statusCode}');
    if (res.statusCode != 200) return null;

    final body = res.body;

    // Mac-Merkezi linklerini bul
    // Örnek: /Iddaa/Mac-Merkezi/20260322/1234567/1/9876543
    final regex = RegExp(r'/Iddaa/Mac-Merkezi/(\d{8})/(\d+)/1/(\d+)');
    final matches = regex.allMatches(body).toList();

    print('   Bulunan link sayısı: ${matches.length}');

    if (matches.isEmpty) {
      // Debug: body'nin bir kısmını yaz
      print('   Body snippet: ${body.substring(0, body.length.clamp(0, 500))}');
      return null;
    }

    // İlk maçı al
    final m = matches.first;
    final url = 'https://www.nesine.com${m.group(0)}';
    print('   ✅ URL: $url');
    return url;

  } catch (e) {
    print('   ❌ Hata: $e');
    return null;
  }
}
