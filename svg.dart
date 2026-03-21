import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:puppeteer/puppeteer.dart';

const _pollInterval = Duration(seconds: 3);

String? _token;
DateTime? _tokenFetchedAt;
int? _currentMatchId;
String? _currentMatchUrl;
List<Map> _coordinates = [];
String _matchStatus = '';
String _homeTeam = '';
String _awayTeam = '';
int _homeScore = 0;
int _awayScore = 0;

Future<void> main() async {
  final workspace = Platform.environment['GITHUB_WORKSPACE'] ?? '.';
  print('⚡ Başlatılıyor...');

  await _initMatch();
  if (_token == null || _currentMatchId == null) {
    print('❌ Maç veya token alınamadı');
    await File('$workspace/pitch.svg').writeAsString('<svg xmlns="http://www.w3.org/2000/svg"><text y="20">Token alinamadi</text></svg>');
    exit(1);
  }

  print('✅ matchId=$_currentMatchId');
  await _pollAndRender(workspace);

  final stopAt = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(stopAt)) {
    await Future.delayed(_pollInterval);
    await _pollAndRender(workspace);
  }

  print('✅ Bitti: $workspace/pitch.svg');
}

Future<void> _initMatch() async {
  Browser? browser;
  try {
    browser = await puppeteer.launch(
      headless: true,
      executablePath: Platform.environment['CHROME_PATH'],
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
    );

    final page = await browser.newPage();
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36');
    await page.setRequestInterception(true);
    final completer = Completer<void>();

    page.onRequest.listen((req) {
      if (req.url.contains('lmt.fn.sportradar.com') && _token == null) {
        final tMatch = RegExp(r'\?T=(exp=\d+~acl=[^&\s]+)').firstMatch(req.url);
        if (tMatch != null) {
          _token = tMatch.group(1);
          _tokenFetchedAt = DateTime.now();
          print('   🔑 Token: ${_token!.substring(0, 40)}...');
        }
        final midMatch = RegExp(r'/gismo/\w+/(\d+)').firstMatch(req.url);
        if (midMatch != null && _currentMatchId == null) {
          _currentMatchId = int.tryParse(midMatch.group(1)!);
          print('   🎯 matchId: $_currentMatchId');
        }
        if (_token != null && _currentMatchId != null && !completer.isCompleted) {
          completer.complete();
        }
      }
      if (req.url.contains('bam.nr-data') || req.url.endsWith('.woff2')) req.abort();
      else req.continueRequest();
    });

    final listPage = await browser.newPage();
    await listPage.setUserAgent('Mozilla/5.0 Chrome/122.0.0.0 Safari/537.36');
    await listPage.setRequestInterception(true);
    listPage.onRequest.listen((req) {
      if (req.url.contains('bam.nr-data')) req.abort();
      else req.continueRequest();
    });
    await listPage.goto('https://www.nesine.com/iddaa/canli-iddaa-canli-bahis?et=0&le=2',
        wait: Until.networkIdle, timeout: const Duration(seconds: 30));
    await Future.delayed(const Duration(seconds: 2));

    final links = await listPage.evaluate<List>('''() => {
      return [...document.querySelectorAll('a[href*="code="][href*="let="]')]
        .map(a => a.href).filter(h => h.includes('canli-iddaa'));
    }''');
    await listPage.close();

    if (links.isEmpty) { print('❌ Canlı maç yok'); return; }
    _currentMatchUrl = links.first as String;
    print('   📍 URL: $_currentMatchUrl');

    await page.goto(_currentMatchUrl!, wait: Until.networkIdle, timeout: const Duration(seconds: 40));
    await Future.any([completer.future, Future.delayed(const Duration(seconds: 15))]);
    await page.close();
  } finally {
    await browser?.close();
  }
}

Future<void> _pollAndRender(String workspace) async {
  if (_token == null || _currentMatchId == null) return;
  try {
    final url = 'https://lmt.fn.sportradar.com/common/tr/Etc:UTC/gismo'
        '/match_timelinedelta/$_currentMatchId?T=$_token';
    final res = await http.get(Uri.parse(url), headers: {
      'Origin': 'https://www.nesine.com',
      'Referer': 'https://www.nesine.com/',
      'User-Agent': 'Mozilla/5.0 Chrome/122.0.0.0',
    }).timeout(const Duration(seconds: 8));

    if (res.statusCode == 401 || res.statusCode == 403) {
      print('❌ Token geçersiz'); return;
    }
    if (res.statusCode != 200) { print('⚠️ HTTP ${res.statusCode}'); return; }

    final data = jsonDecode(res.body);
    final docData = data['doc']?[0]?['data'];
    if (docData == null) return;

    final match = docData['match'];
    if (match != null) {
      _homeTeam  = match['teams']?['home']?['name'] ?? _homeTeam;
      _awayTeam  = match['teams']?['away']?['name'] ?? _awayTeam;
      _homeScore = match['result']?['home']  ?? _homeScore;
      _awayScore = match['result']?['away']  ?? _awayScore;
      _matchStatus = match['status']?['shortName'] ?? _matchStatus;
    }

    final events = docData['events'] as List? ?? [];
    for (final ev in events) {
      if (ev['type'] == 'ballcoordinates') {
        final coords = ev['coordinates'] as List?;
        if (coords != null) {
          _coordinates = coords.cast<Map>();
          print('📍 ${_coordinates.length} nokta | $_homeTeam $_homeScore-$_awayScore $_awayTeam ($_matchStatus)');
        }
      }
    }

    await File('$workspace/pitch.svg').writeAsString(_renderSvg());
  } catch (e) {
    print('⚠️ $e');
  }
}

String _renderSvg() {
  const w = 520.0, h = 292.0, padX = 19.0, padY = 11.0;
  const fieldW = w - padX * 2;
  const fieldH = h - padY * 2;
  final b = StringBuffer();

  b.write('''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" style="background:#1a5c18;">
  <rect x="$padX" y="$padY" width="$fieldW" height="$fieldH" fill="#2d7a27" stroke="white" stroke-width="2"/>
  <line x1="${w/2}" y1="$padY" x2="${w/2}" y2="${h-padY}" stroke="white" stroke-width="2"/>
  <circle cx="${w/2}" cy="${h/2}" r="41" fill="none" stroke="white" stroke-width="2"/>
  <circle cx="${w/2}" cy="${h/2}" r="2" fill="white"/>
  <rect x="$padX" y="${h/2-39.5}" width="72" height="79" fill="none" stroke="white" stroke-width="2"/>
  <rect x="$padX" y="${h/2-19.5}" width="27" height="39" fill="none" stroke="white" stroke-width="2"/>
  <rect x="${w-padX-72}" y="${h/2-39.5}" width="72" height="79" fill="none" stroke="white" stroke-width="2"/>
  <rect x="${w-padX-27}" y="${h/2-19.5}" width="27" height="39" fill="none" stroke="white" stroke-width="2"/>
  <rect x="${padX-8}" y="${h/2-12}" width="8" height="24" fill="none" stroke="white" stroke-width="2"/>
  <rect x="${w-padX}" y="${h/2-12}" width="8" height="24" fill="none" stroke="white" stroke-width="2"/>''');

  for (final c in _coordinates) {
    final svgX = padX + ((c['X'] as num) / 100) * fieldW;
    final svgY = padY + ((c['Y'] as num) / 100) * fieldH;
    final color = c['team'] == 'home' ? '#ff4444' : '#4488ff';
    b.write('\n  <circle cx="${svgX.toStringAsFixed(1)}" cy="${svgY.toStringAsFixed(1)}" r="7" fill="$color" stroke="white" stroke-width="1.5"/>');
  }

  b.write('''
  <rect x="${w/2-65}" y="4" width="130" height="20" rx="3" fill="rgba(0,0,0,0.65)"/>
  <text x="${w/2}" y="18" text-anchor="middle" fill="white" font-size="10" font-family="Arial" font-weight="bold">$_homeTeam $_homeScore - $_awayScore $_awayTeam  $_matchStatus</text>
</svg>''');

  return b.toString();
}
