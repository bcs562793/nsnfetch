// bilyoner_sync.dart - GitHub Actions cron ile calisir
// Bilyoner canli mac listesi -> live_matches.bilyoner_id + future_matches.bilyoner_id yazar

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

final _sbUrl = Platform.environment['SUPABASE_URL'] ?? '';
final _sbKey = Platform.environment['SUPABASE_KEY'] ?? '';

const _bilyonerBase  = 'https://www.bilyoner.com';
const _platformToken = '40CAB7292CD83F7EE0631FC35A0AFC75';

// -- sync_fixtures(3)'ten alinan Takim Isim Normalizasyon Sabitleri --
const _nicknames = <String, String>{
  'spurs': 'tottenham',
  'inter': 'internazionale',
};

const _wordTrToEn = <String, String>{
  'munih': 'munich', 'munchen': 'munich',
  'marsilya': 'marseille', 'kopenhag': 'copenhagen',
  'bruksel': 'brussels', 'prag': 'prague',
  'lizbon': 'lisbon', 'viyana': 'vienna',
};

const _noise = <String>{
  'fc', 'sc', 'cf', 'ac', 'if', 'bk', 'sk', 'fk',
  'afc', 'bfc', 'cfc', 'sfc', 'rfc',
  'cp', 'cd', 'sd', 'ud', 'rc', 'rcd', 'as', 'ss',
};

String? _cachedAuthToken;
String? _cachedDeviceId;

String _generateUuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
}

Map<String, String> _bilyonerHeaders() {
  _cachedDeviceId ??= _generateUuidV4().toUpperCase();
  _cachedAuthToken ??= () {
    final uuid = _generateUuidV4().replaceAll('-', '');
    final ts   = DateTime.now().millisecondsSinceEpoch;
    return '$uuid$ts';
  }();

  return {
    'accept':                   'application/json, text/plain, */*',
    'accept-language':          'tr,en-US;q=0.9,en;q=0.8',
    'cache-control':            'no-cache',
    'pragma':                   'no-cache',
    'referer':                  '$_bilyonerBase/canli-iddaa',
    'user-agent':               'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
    'platform-token':           _platformToken,
    'x-auth-token':             _cachedAuthToken!,
    'x-client-app-version':     '3.98.1',
    'x-client-browser-version': 'Chrome / v147.0.0.0',
    'x-client-channel':         'WEB',
    'x-device-id':              _cachedDeviceId!,
  };
}

Map<String, String> _sbHeaders() => {
  'apikey':        _sbKey,
  'Authorization': 'Bearer $_sbKey',
  'Prefer':        'return=minimal',
};

// -- Tarih yardimcilari --
String _todayTR() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 3));
  final p   = (int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${p(now.month)}-${p(now.day)}';
}

String _addDays(String dateStr, int n) {
  final d = DateTime.parse('${dateStr}T00:00:00').add(Duration(days: n));
  final p = (int x) => x.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)}';
}

// -- Yardimcilar ve Normalizasyon --
int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString());
}

String _norm(String name) {
  var s = name.toLowerCase().trim();
  if (_nicknames.containsKey(s)) s = _nicknames[s]!;

  s = s
      .replaceAll('s', 's').replaceAll('g', 'g').replaceAll('u', 'u')
      .replaceAll('o', 'o').replaceAll('c', 'c').replaceAll('i', 'i')
      .replaceAll(RegExp(r'[ee]'), 'e').replaceAll(RegExp(r'[aa]'), 'a')
      .replaceAll(RegExp(r'[oo]'), 'o').replaceAll(RegExp(r'[uu]'), 'u')
      .replaceAll(RegExp(r'[ii]'), 'i').replaceAll('n', 'n')
      .replaceAll(RegExp(r'[cc]'), 'c').replaceAll('z', 'z')
      .replaceAll('s', 's').replaceAll('y', 'y').replaceAll('r', 'r');

  s = s.replaceAll(RegExp(r"[.\-/'\\()]"), ' ');

  final tokens = s
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !_noise.contains(t))
      .map((t) => _wordTrToEn[t] ?? t)
      .toList();

  return tokens.join(' ').trim();
}

double _sim(String a, String b) {
  if (a == b) return 1.0;
  if (a.contains(b) || b.contains(a)) return 0.9;
  final w1 = a.split(' ').where((t) => t.length > 1).toSet();
  final w2 = b.split(' ').where((t) => t.length > 1).toSet();
  if (w1.isEmpty || w2.isEmpty) return 0.0;
  final j = w1.intersection(w2).length / w1.union(w2).length;
  if (j >= 0.5) return 0.7 + j * 0.2;
  if (a.length >= 3 && b.length >= 3 && a.substring(0,3) == b.substring(0,3)) return 0.6;
  return j * 0.5;
}

// -- HTML Gomulu State Kaziyici (401/400 API Engellerini Asar) --
Future<void> _scrapeHtml(String url, List<Map<String, dynamic>> target) async {
  try {
    print('  [LOG] HTML Web Scraper Kaziyor: $url');
    final res = await http.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/122.0.0.0 Safari/537.36',
    }).timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      // 1. window.__INITIAL_STATE__ yapısını bul (Modern JS Framework)
      final stateRegex = RegExp(r'window\.__INITIAL_STATE__\s*=\s*(\{.*?\});', dotAll: true);
      final match = stateRegex.firstMatch(res.body);

      if (match != null) {
        final data = jsonDecode(match.group(1)!);
        int initialCount = target.length;
        _extractMatchesRecursive(data, target);
        print('  [LOG] HTML State (${target.length - initialCount} mac) basariyla cekildi.');
      } else {
        // 2. Yedek: Next.js formatı (__NEXT_DATA__)
        final nextRegex = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true);
        final nextMatch = nextRegex.firstMatch(res.body);
        if (nextMatch != null) {
          final data = jsonDecode(nextMatch.group(1)!);
          _extractMatchesRecursive(data, target);
          print('  [LOG] HTML Next.js State basariyla cekildi.');
        } else {
          print('  [LOG] HTML icinde eslesen JSON blogu bulunamadi.');
        }
      }
    } else {
      print('  [LOG] HTML Kazima Hatası. HTTP Kodu: ${res.statusCode}');
    }
  } catch (e) {
    print('  [LOG] HTML Kazima Istisnasi ($url): $e');
  }
}

// -- Dinamik Rekurrsif JSON Ayristirici (Her Yerden Ceker) --
void _extractMatchesRecursive(dynamic node, List<Map<String, dynamic>> target) {
  if (node is List) {
    for (final item in node) {
      _extractMatchesRecursive(item, target);
    }
  } else if (node is Map) {
    final htn = node['htn']?.toString();
    final atn = node['atn']?.toString();
    final id = _int(node['id'] ?? node['sbsEventId'] ?? node['eventId']);

    if (id != null && id > 0 && htn != null && htn.isNotEmpty && atn != null && atn.isNotEmpty) {
      target.add({
        'id': id,
        'home': htn,
        'away': atn,
      });
    }
    // Alt dugumlere girmeye devam et
    for (final value in node.values) {
      _extractMatchesRecursive(value, target);
    }
  }
}

// -- Supabase patch --
Future<void> _patch(String table, int fid, Map<String, dynamic> data) async {
  try {
    final res = await http.patch(
      Uri.parse('$_sbUrl/rest/v1/$table?fixture_id=eq.$fid'),
      headers: {..._sbHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode >= 300) {
      print('    [ERROR] $table patch hatasi: ${res.statusCode} ${res.body}');
    }
  } catch (e) {
    print('    [ERROR] $table patch exception: $e');
  }
}

Future<void> main() async {
  print('[INFO] Bilyoner Sync basliyor...');

  if (_sbUrl.isEmpty || _sbKey.isEmpty) {
    print('[ERROR] SUPABASE env eksik. Lutfen SUPABASE_URL ve SUPABASE_KEY ortam degiskenlerini ayarlayin.');
    exit(1);
  }

  // -- 1. Bilyoner'den canli futbol maclarini cek --
  print('[INFO] Bilyoner mac listesi cekiliyor...');

  final List<Map<String, dynamic>> rawEvents = [];

  // YONTEM A: HTML Kazima (En guvenilir yontem - 401 ve 400 API engellerini asar)
  await _scrapeHtml('$_bilyonerBase/canli-iddaa', rawEvents);
  await _scrapeHtml('$_bilyonerBase/iddaa', rawEvents);

  // YONTEM B: API Uc Noktalari (HTML kazima yetmezse yedek olarak denenır)
  final endpoints = [
    '$_bilyonerBase/api/v3/mobile/aggregator/gamelist/sport/1/v1',
    '$_bilyonerBase/api/v3/mobile/aggregator/live/sport/1/v1',
    '$_bilyonerBase/api/mobile/live-score/event/v2/sport-list?sportType=SOCCER',
  ];

  for (final url in endpoints) {
    try {
      print('  [LOG] API Istek atiliyor: $url');
      final res = await http.get(Uri.parse(url), headers: _bilyonerHeaders()).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        _extractMatchesRecursive(jsonDecode(res.body), rawEvents);
      } else {
        print('  [LOG] API HTTP Hata Kodu: ${res.statusCode}');
      }
    } catch (e) {
      print('  [ERROR] API Istisna hatasi: $e');
    }
  }

  // Benzersizlestirme (Deduplication - Cift cekilenleri sil)
  final uniqueMatches = <int, Map<String, dynamic>>{};
  for (final m in rawEvents) {
    uniqueMatches[m['id'] as int] = m;
  }
  final bilyonerMatches = uniqueMatches.values.toList();

  if (bilyonerMatches.isEmpty) {
    print('[ERROR] Bilyoner\'den hic mac cekilemedi. Sonlandiriliyor.');
    exit(1);
  }
  print('  [INFO] Toplam Cekilen Benzersiz Bilyoner Maci: ${bilyonerMatches.length}');

  // -- 2. Supabase'den live_matches cek --
  print('[INFO] Supabase live_matches cekiliyor...');
  final liveRes = await http.get(
    Uri.parse('$_sbUrl/rest/v1/live_matches'
        '?select=fixture_id,home_team,away_team,bilyoner_id'
        '&status_short=in.(1H,2H,HT,ET,BT,P,LIVE,NS)'),
    headers: _sbHeaders(),
  ).timeout(const Duration(seconds: 15));

  if (liveRes.statusCode != 200) {
    print('[ERROR] live_matches HTTP ${liveRes.statusCode}: ${liveRes.body}'); exit(1);
  }
  final liveList = (jsonDecode(liveRes.body) as List).cast<Map>();
  print('  [INFO] Supabase: ${liveList.length} canli/NS mac.');

  // -- 3. Supabase'den future_matches cek --
  print('[INFO] Supabase future_matches cekiliyor...');
  final today  = _todayTR();
  final cutoff = _addDays(today, 3);
  final futRes = await http.get(
    Uri.parse('$_sbUrl/rest/v1/future_matches'
        '?select=fixture_id,data,bilyoner_id'
        '&date=gte.$today&date=lte.$cutoff'),
    headers: _sbHeaders(),
  ).timeout(const Duration(seconds: 15));

  if (futRes.statusCode != 200) {
    print('[ERROR] future_matches HTTP ${futRes.statusCode}: ${futRes.body}'); exit(1);
  }

  final futList = <Map<String, dynamic>>[];
  for (final row in (jsonDecode(futRes.body) as List).cast<Map>()) {
    final fid = _int(row['fixture_id']);
    if (fid == null) continue;
    String home = '', away = '';
    try {
      final d = row['data'] is String
          ? jsonDecode(row['data'] as String)
          : row['data'];
      final payload = d is List ? d[0] : d;
      // future_matches -> data icindeki takimlari cikartma
      home = payload?['teams']?['home']?['name']?.toString() ?? '';
      away = payload?['teams']?['away']?['name']?.toString() ?? '';
    } catch (e) {}
    futList.add({
      'fixture_id': fid,
      'home': home,
      'away': away,
      'bilyoner_id': row['bilyoner_id'],
    });
  }
  print('  [INFO] Supabase: ${futList.length} gelecek mac.');

  // -- 4. Eslestir ve yaz --
  print('[INFO] Eslestirme Algoritmasi Basliyor...');
  int liveMatched = 0, futMatched = 0, skipped = 0;

  for (final bm in bilyonerMatches) {
    final bid  = bm['id'] as int;
    final bHome = _norm(bm['home'].toString());
    final bAway = _norm(bm['away'].toString());

    // 1. Once live_matches icinde eslesme ara
    Map? bestLive; double bestLiveScore = 0;
    for (final sb in liveList) {
      if (_int(sb['bilyoner_id']) == bid) { bestLive = sb; bestLiveScore = 1.0; break; }
      if (_int(sb['bilyoner_id']) != null) continue; // baska ID atanmissa atla

      final hs = _sim(bHome, _norm(sb['home_team']?.toString() ?? ''));
      final as_ = _sim(bAway, _norm(sb['away_team']?.toString() ?? ''));
      if (hs < 0.45 || as_ < 0.45) continue;
      final s = (hs + as_) / 2;
      if (s > bestLiveScore) { bestLiveScore = s; bestLive = sb; }
    }

    if (bestLive != null && bestLiveScore >= 0.55) {
      final fid = _int(bestLive['fixture_id'])!;
      if (_int(bestLive['bilyoner_id']) != bid) {
        print('  [LINK] [LIVE PATCH] Bilyoner:$bid <-> Supabase:$fid (Skor: ${bestLiveScore.toStringAsFixed(2)}) | ${bm["home"]} vs ${bm["away"]}');
        await _patch('live_matches', fid, {'bilyoner_id': bid});
      }
      liveMatched++;
      continue; // Live'da bulduysak future'a bakmaya gerek yok
    }

    // 2. future_matches icinde eslesme ara (Live'da bulunamadiysa)
    Map<String, dynamic>? bestFut; double bestFutScore = 0;
    for (final fb in futList) {
      if (_int(fb['bilyoner_id']) == bid) { bestFut = fb; bestFutScore = 1.0; break; }
      if (_int(fb['bilyoner_id']) != null) continue; // Baska id yazilmis, gec.

      final hs  = _sim(bHome, _norm(fb['home'].toString()));
      final as_ = _sim(bAway, _norm(fb['away'].toString()));

      if (hs < 0.45 || as_ < 0.45) continue;
      final s = (hs + as_) / 2;
      if (s > bestFutScore) { bestFutScore = s; bestFut = fb; }
    }

    if (bestFut != null && bestFutScore >= 0.55) {
      final fid = _int(bestFut['fixture_id'])!;
      if (_int(bestFut['bilyoner_id']) != bid) {
        print('  [LINK] [FUTURE PATCH] Bilyoner:$bid <-> Supabase:$fid (Skor: ${bestFutScore.toStringAsFixed(2)}) | ${bm["home"]} vs ${bm["away"]}');
        await _patch('future_matches', fid, {'bilyoner_id': bid});
      }
      futMatched++;
    } else {
      skipped++;
    }
  }

  print('========================================');
  print('  [OK] Live tablosu eslesti  : $liveMatched');
  print('  [OK] Future tablosu eslesti: $futMatched');
  print('  [WARN] Eslesmedi             : $skipped');
  print('  [INFO] Toplam Bilyoner Maci  : ${bilyonerMatches.length}');
  print('========================================');
  exit(0);
}
