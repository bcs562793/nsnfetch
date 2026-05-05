// bilyoner_sync.dart - GitHub Actions cron ile calisir
// Bilyoner canli mac listesi -> live_matches.bilyoner_id + future_matches.bilyoner_id yazar
//
// HAR ANALİZİ BULGULARI (05.05.2026):
// ❌ ÇALIŞMAYAN (401/400): /api/v3/mobile/aggregator/gamelist/sport/1/v1
//                          /api/v3/mobile/aggregator/live/sport/1/v1
//                          /api/mobile/live-score/event/v2/sport-list?sportType=SOCCER
// ✅ ÇALIŞAN (200):
//   1. GET /api/v3/mobile/aggregator/gamelist/auth/events/recommended/markets
//      → Parametresiz. eventMarketIds{} içinden seed eventId alınır.
//   2. GET /api/v3/mobile/aggregator/match-card/{seedId}/league-events
//      → liveGameList.events[].{id, htn, atn}  (TÜM canlı futbol maçları, 12+ lig)
//      → preGameList.events[].{id, htn, atn}   (yaklaşan maçlar)
//   3. GET /api/mobile/match-card/{id}/header/v8
//      → homeTeam.teamName, awayTeam.teamName, matchCode  (tekil maç başlık)

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

final _sbUrl = Platform.environment['SUPABASE_URL'] ?? '';
final _sbKey = Platform.environment['SUPABASE_KEY'] ?? '';

const _bilyonerBase  = 'https://www.bilyoner.com';
const _platformToken = '40CAB7292CD83F7EE0631FC35A0AFC75';

// -- Takim Isim Normalizasyon --
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
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
}

// HAR'dan kanıtlanan format: {UUID_no_dashes}{timestamp_ms}
// Örnek: ae3ff5d4e07e42218cfcdb5a3079b2271777987510771
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
      .replaceAll(RegExp(r'[şs]'), 's').replaceAll(RegExp(r'[ğg]'), 'g')
      .replaceAll(RegExp(r'[üu]'), 'u').replaceAll(RegExp(r'[öo]'), 'o')
      .replaceAll(RegExp(r'[çc]'), 'c').replaceAll(RegExp(r'[ıi]'), 'i')
      .replaceAll(RegExp(r'[éèêë]'), 'e').replaceAll(RegExp(r'[àâä]'), 'a')
      .replaceAll(RegExp(r'[ôõ]'), 'o').replaceAll(RegExp(r'[ûù]'), 'u')
      .replaceAll(RegExp(r'[ñn]'), 'n').replaceAll(RegExp(r'[ß]'), 'ss');
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

// ============================================================
// ADIM 1: Seed eventId al (parametresiz, güvenilir 200 döner)
// ============================================================
Future<int?> _fetchSeedEventId() async {
  const url = '$_bilyonerBase/api/v3/mobile/aggregator/gamelist/auth/events/recommended/markets';
  try {
    print('  [LOG] Seed eventId alınıyor: $url');
    final res = await http.get(Uri.parse(url), headers: _bilyonerHeaders())
        .timeout(const Duration(seconds: 12));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final ids = (data['eventMarketIds'] as Map?)?.keys;
      if (ids != null && ids.isNotEmpty) {
        final seedId = _int(ids.first);
        print('  [LOG] Seed eventId bulundu: $seedId');
        return seedId;
      }
    } else {
      print('  [WARN] recommended/markets HTTP ${res.statusCode}');
    }
  } catch (e) {
    print('  [ERROR] recommended/markets: $e');
  }
  return null;
}

// ============================================================
// ADIM 2: league-events ile tüm maçları çek (live + pre)
// ============================================================
Future<void> _fetchLeagueEvents(int seedId, List<Map<String, dynamic>> target) async {
  final url = '$_bilyonerBase/api/v3/mobile/aggregator/match-card/$seedId/league-events';
  try {
    print('  [LOG] league-events çekiliyor: $url');
    final res = await http.get(Uri.parse(url), headers: _bilyonerHeaders())
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      print('  [WARN] league-events HTTP ${res.statusCode}');
      return;
    }
    final data = jsonDecode(res.body);

    int count = 0;
    // Canlı maçlar
    for (final ev in (data['liveGameList']?['events'] ?? []) as List) {
      final id  = _int(ev['id']);
      final htn = ev['htn']?.toString();
      final atn = ev['atn']?.toString();
      if (id != null && id > 0 && htn != null && htn.isNotEmpty && atn != null && atn.isNotEmpty) {
        target.add({'id': id, 'home': htn, 'away': atn});
        count++;
      }
    }
    // Yaklaşan (pre-game) maçlar
    for (final ev in (data['preGameList']?['events'] ?? []) as List) {
      final id  = _int(ev['id']);
      final htn = ev['htn']?.toString();
      final atn = ev['atn']?.toString();
      if (id != null && id > 0 && htn != null && htn.isNotEmpty && atn != null && atn.isNotEmpty) {
        target.add({'id': id, 'home': htn, 'away': atn});
        count++;
      }
    }
    print('  [LOG] league-events: $count maç alındı (seed=$seedId)');
  } catch (e) {
    print('  [ERROR] league-events: $e');
  }
}

// ============================================================
// ADIM 3 (Yedek): Iddaa HTML sayfasından ID regex ile çek
//   - JavaScript render'lı sayfalar için geniş pattern kullanır
//   - Bulunan her ID için match-card/header çağrısı yapar
// ============================================================
Future<void> _scrapeIddaaHtml(List<Map<String, dynamic>> target) async {
  final urls = [
    '$_bilyonerBase/canli-iddaa',
    '$_bilyonerBase/iddaa/futbol',
  ];

  for (final pageUrl in urls) {
    try {
      print('  [LOG] HTML kazıma: $pageUrl');
      final res = await http.get(Uri.parse(pageUrl), headers: {
        'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
        'accept': 'text/html,application/xhtml+xml',
        'accept-language': 'tr,en-US;q=0.9,en;q=0.8',
      }).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        print('  [WARN] HTML HTTP ${res.statusCode}');
        continue;
      }

      final body = res.body;

      // Yöntem A: Next.js __NEXT_DATA__
      final nextMatch = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true)
          .firstMatch(body);
      if (nextMatch != null) {
        _extractMatchesRecursive(jsonDecode(nextMatch.group(1)!), target);
        print('  [LOG] __NEXT_DATA__ parse edildi');
        continue;
      }

      // Yöntem B: window.__INITIAL_STATE__
      final stateMatch = RegExp(r'window\.__INITIAL_STATE__\s*=\s*(\{.*?\});', dotAll: true)
          .firstMatch(body);
      if (stateMatch != null) {
        _extractMatchesRecursive(jsonDecode(stateMatch.group(1)!), target);
        print('  [LOG] __INITIAL_STATE__ parse edildi');
        continue;
      }

      // Yöntem C: Geniş JSON inline regex - "id":XXXXXXX,"htn":"...","atn":"..."
      // HAR'dan öğrenilen yapı: {"id":2930496,...,"htn":"Chongqing","atn":"Henan",...}
      final inlineRegex = RegExp(
        r'"(?:id|sbsEventId|matchCode)"\s*:\s*(\d{7,})(?:[^}]{1,500}?)"htn"\s*:\s*"([^"]+)"(?:[^}]{1,200}?)"atn"\s*:\s*"([^"]+)"',
        dotAll: true,
      );
      final matches = inlineRegex.allMatches(body);
      int found = 0;
      for (final m in matches) {
        final id = _int(m.group(1));
        final htn = m.group(2);
        final atn = m.group(3);
        if (id != null && id > 0 && htn != null && htn.isNotEmpty && atn != null && atn.isNotEmpty) {
          target.add({'id': id, 'home': htn, 'away': atn});
          found++;
        }
      }

      // Yöntem D: Sadece mac-karti URL pattern'i - ID topla, header API'si çağır
      if (found == 0) {
        final urlRegex = RegExp(r'/mac-karti/futbol/(\d{6,})/');
        final idsFromUrls = urlRegex.allMatches(body)
            .map((m) => _int(m.group(1)))
            .where((id) => id != null)
            .cast<int>()
            .toSet();

        if (idsFromUrls.isNotEmpty) {
          print('  [LOG] HTML URL regex: ${idsFromUrls.length} ID bulundu, header API çağrılıyor...');
          for (final id in idsFromUrls) {
            await _fetchMatchHeader(id, target);
            await Future.delayed(const Duration(milliseconds: 80));
          }
        } else {
          print('  [LOG] HTML\'de eşleşme bulunamadı: $pageUrl');
        }
      } else {
        print('  [LOG] HTML inline JSON: $found maç bulundu');
      }
    } catch (e) {
      print('  [ERROR] HTML kazıma ($pageUrl): $e');
    }
  }
}

// Tekil maç başlık bilgisi çek (HAR'da 200 döndüğü kanıtlı)
Future<void> _fetchMatchHeader(int id, List<Map<String, dynamic>> target) async {
  final url = '$_bilyonerBase/api/mobile/match-card/$id/header/v8';
  try {
    final res = await http.get(Uri.parse(url), headers: _bilyonerHeaders())
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final homeTeam = data['homeTeam']?['teamName']?.toString();
      final awayTeam = data['awayTeam']?['teamName']?.toString();
      final matchCode = _int(data['matchCode']);
      if (matchCode != null && homeTeam != null && awayTeam != null) {
        target.add({'id': matchCode, 'home': homeTeam, 'away': awayTeam});
      }
    }
  } catch (_) {}
}

// Rekürsif JSON parse - ham veri içinden htn/atn/id çıkart
void _extractMatchesRecursive(dynamic node, List<Map<String, dynamic>> target) {
  if (node is List) {
    for (final item in node) _extractMatchesRecursive(item, target);
  } else if (node is Map) {
    final htn = node['htn']?.toString();
    final atn = node['atn']?.toString();
    final id  = _int(node['id'] ?? node['sbsEventId'] ?? node['eventId'] ?? node['matchCode']);
    if (id != null && id > 0 && htn != null && htn.isNotEmpty && atn != null && atn.isNotEmpty) {
      target.add({'id': id, 'home': htn, 'away': atn});
    }
    for (final value in node.values) _extractMatchesRecursive(value, target);
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
    print('[ERROR] SUPABASE env eksik.');
    exit(1);
  }

  // ================================================================
  // 1. BİLYONER'DEN MAÇ LİSTESİ ÇEK
  //    Strateji (HAR'dan kanıtlı):
  //    A) recommended/markets → seed ID → league-events (ana yol)
  //    B) HTML kazıma (yedek)
  // ================================================================
  print('[INFO] Bilyoner maç listesi çekiliyor...');
  final List<Map<String, dynamic>> rawEvents = [];

  // A: Ana yol - seed ID ile league-events
  final seedId = await _fetchSeedEventId();
  if (seedId != null) {
    await _fetchLeagueEvents(seedId, rawEvents);
  } else {
    print('  [WARN] Seed ID alınamadı, HTML kazımaya geçiliyor...');
  }

  // B: Eğer yeterli maç gelmediyse HTML yedek
  if (rawEvents.length < 5) {
    print('  [INFO] Yetersiz maç (${rawEvents.length}), HTML kazıma başlatılıyor...');
    await _scrapeIddaaHtml(rawEvents);
  }

  // Benzersizleştir
  final uniqueMatches = <int, Map<String, dynamic>>{};
  for (final m in rawEvents) {
    uniqueMatches[m['id'] as int] = m;
  }
  final bilyonerMatches = uniqueMatches.values.toList();

  if (bilyonerMatches.isEmpty) {
    print('[ERROR] Bilyoner\'den hiç maç çekilemedi. Sonlandırılıyor.');
    exit(1);
  }
  print('  [INFO] Toplam benzersiz Bilyoner maçı: ${bilyonerMatches.length}');

  // ================================================================
  // 2. SUPABASE live_matches
  // ================================================================
  print('[INFO] Supabase live_matches çekiliyor...');
  final liveRes = await http.get(
    Uri.parse('$_sbUrl/rest/v1/live_matches'
        '?select=fixture_id,home_team,away_team,bilyoner_id'
        '&status_short=in.(1H,2H,HT,ET,BT,P,LIVE,NS)'),
    headers: _sbHeaders(),
  ).timeout(const Duration(seconds: 15));
  if (liveRes.statusCode != 200) {
    print('[ERROR] live_matches HTTP ${liveRes.statusCode}: ${liveRes.body}');
    exit(1);
  }
  final liveList = (jsonDecode(liveRes.body) as List).cast<Map>();
  print('  [INFO] Supabase: ${liveList.length} canlı/NS maç.');

  // ================================================================
  // 3. SUPABASE future_matches
  // ================================================================
  print('[INFO] Supabase future_matches çekiliyor...');
  final today  = _todayTR();
  final cutoff = _addDays(today, 3);
  final futRes = await http.get(
    Uri.parse('$_sbUrl/rest/v1/future_matches'
        '?select=fixture_id,data,bilyoner_id'
        '&date=gte.$today&date=lte.$cutoff'),
    headers: _sbHeaders(),
  ).timeout(const Duration(seconds: 15));
  if (futRes.statusCode != 200) {
    print('[ERROR] future_matches HTTP ${futRes.statusCode}: ${futRes.body}');
    exit(1);
  }
  final futList = <Map<String, dynamic>>[];
  for (final row in (jsonDecode(futRes.body) as List).cast<Map>()) {
    final fid = _int(row['fixture_id']);
    if (fid == null) continue;
    String home = '', away = '';
    try {
      final d = row['data'] is String ? jsonDecode(row['data'] as String) : row['data'];
      final payload = d is List ? d[0] : d;
      home = payload?['teams']?['home']?['name']?.toString() ?? '';
      away = payload?['teams']?['away']?['name']?.toString() ?? '';
    } catch (_) {}
    futList.add({
      'fixture_id': fid,
      'home': home,
      'away': away,
      'bilyoner_id': row['bilyoner_id'],
    });
  }
  print('  [INFO] Supabase: ${futList.length} gelecek maç.');

  // ================================================================
  // 4. EŞLEŞTİR ve YAZ
  // ================================================================
  print('[INFO] Eşleştirme başlıyor...');
  int liveMatched = 0, futMatched = 0, skipped = 0;

  for (final bm in bilyonerMatches) {
    final bid   = bm['id'] as int;
    final bHome = _norm(bm['home'].toString());
    final bAway = _norm(bm['away'].toString());

    // -- live_matches --
    Map? bestLive; double bestLiveScore = 0;
    for (final sb in liveList) {
      if (_int(sb['bilyoner_id']) == bid) { bestLive = sb; bestLiveScore = 1.0; break; }
      if (_int(sb['bilyoner_id']) != null) continue;
      final hs = _sim(bHome, _norm(sb['home_team']?.toString() ?? ''));
      final as_ = _sim(bAway, _norm(sb['away_team']?.toString() ?? ''));
      if (hs < 0.45 || as_ < 0.45) continue;
      final s = (hs + as_) / 2;
      if (s > bestLiveScore) { bestLiveScore = s; bestLive = sb; }
    }
    if (bestLive != null && bestLiveScore >= 0.55) {
      final fid = _int(bestLive['fixture_id'])!;
      if (_int(bestLive['bilyoner_id']) != bid) {
        print('  [LINK] [LIVE] Bilyoner:$bid <-> Supabase:$fid (${bestLiveScore.toStringAsFixed(2)}) | ${bm["home"]} vs ${bm["away"]}');
        await _patch('live_matches', fid, {'bilyoner_id': bid});
      }
      liveMatched++;
      continue;
    }

    // -- future_matches --
    Map<String, dynamic>? bestFut; double bestFutScore = 0;
    for (final fb in futList) {
      if (_int(fb['bilyoner_id']) == bid) { bestFut = fb; bestFutScore = 1.0; break; }
      if (_int(fb['bilyoner_id']) != null) continue;
      final hs  = _sim(bHome, _norm(fb['home'].toString()));
      final as_ = _sim(bAway, _norm(fb['away'].toString()));
      if (hs < 0.45 || as_ < 0.45) continue;
      final s = (hs + as_) / 2;
      if (s > bestFutScore) { bestFutScore = s; bestFut = fb; }
    }
    if (bestFut != null && bestFutScore >= 0.55) {
      final fid = _int(bestFut['fixture_id'])!;
      if (_int(bestFut['bilyoner_id']) != bid) {
        print('  [LINK] [FUTURE] Bilyoner:$bid <-> Supabase:$fid (${bestFutScore.toStringAsFixed(2)}) | ${bm["home"]} vs ${bm["away"]}');
        await _patch('future_matches', fid, {'bilyoner_id': bid});
      }
      futMatched++;
    } else {
      skipped++;
    }
  }

  print('========================================');
  print('  [OK]   Live eşlendi  : $liveMatched');
  print('  [OK]   Future eşlendi: $futMatched');
  print('  [WARN] Eşleşmedi     : $skipped');
  print('  [INFO] Toplam Bilyoner: ${bilyonerMatches.length}');
  print('========================================');
  exit(0);
}
