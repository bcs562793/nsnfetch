// bilyoner_sync.dart — GitHub Actions cron ile calisir
// Bilyoner canli + yaklasan mac listesi -> live_matches + future_matches bilyoner_id gunceller
//
// HAR ANALiZi BULGULARI (05.05.2026):
// CALISMIYOR (401/400):
//   /api/v3/mobile/aggregator/gamelist/sport/1/v1
//   /api/v3/mobile/aggregator/live/sport/1/v1
//   /api/mobile/live-score/event/v2/sport-list?sportType=SOCCER
//   /api/v3/mobile/aggregator/gamelist/auth/events/recommended/markets (POST)
//
// CALISIYOR (200, auth gerektirmez):
//   GET /api/v3/mobile/aggregator/gamelist/events/{id}  -> htn, atn, id
//   GET /api/v3/mobile/aggregator/match-card/{id}/league-events
//       -> liveGameList.events[].{id,htn,atn}  (TUM canli futbol maclari)
//       -> preGameList.events[].{id,htn,atn}   (yaklasan maclar)
//
// STRATEJI:
//  1. canli-iddaa HTML'inden seed event ID topla (cesitli pattern'ler)
//  2. gamelist/events/{id} ile seed ID dogrula (200 + htn = gecerli)
//  3. Gecerli seed -> league-events -> tum live + pre-game listesi
//  4. HTML'den ID bulunamazsa son bilinen ID araligini tara

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

final _sbUrl = Platform.environment['SUPABASE_URL'] ?? '';
final _sbKey = Platform.environment['SUPABASE_KEY'] ?? '';

const _bilyonerBase  = 'https://www.bilyoner.com';
const _platformToken = '40CAB7292CD83F7EE0631FC35A0AFC75';

// HAR'dan son bilinen event ID (05.05.2026). Aralik taramasi icin baslangic.
const _lastKnownEventId = 2935198;

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
  return '\${hex.substring(0,8)}-\${hex.substring(8,12)}-\${hex.substring(12,16)}-\${hex.substring(16,20)}-\${hex.substring(20)}';
}

// HAR dogrulamali token formati: {uuid_no_dashes}{timestamp_ms}
String _getAuthToken() {
  _cachedAuthToken ??= () {
    final uuid = _generateUuidV4().replaceAll('-', '');
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '\$uuid\$ts';
  }();
  return _cachedAuthToken!;
}

String _getDeviceId() {
  _cachedDeviceId ??= _generateUuidV4().toUpperCase();
  return _cachedDeviceId!;
}

Map<String, String> _bilyonerHeaders({String? referer}) => {
  'accept':                   'application/json, text/plain, */*',
  'accept-language':          'tr,en-US;q=0.9,en;q=0.8',
  'cache-control':            'no-cache',
  'pragma':                   'no-cache',
  'referer':                  referer ?? '\$_bilyonerBase/canli-iddaa',
  'user-agent':               'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
  'platform-token':           _platformToken,
  'x-auth-token':             _getAuthToken(),
  'x-client-app-version':     '3.98.1',
  'x-client-browser-version': 'Chrome / v147.0.0.0',
  'x-client-channel':         'WEB',
  'x-device-id':              _getDeviceId(),
};

Map<String, String> _sbHeaders() => {
  'apikey':        _sbKey,
  'Authorization': 'Bearer \$_sbKey',
  'Prefer':        'return=minimal',
};

String _todayTR() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 3));
  final p   = (int n) => n.toString().padLeft(2, '0');
  return '\${now.year}-\${p(now.month)}-\${p(now.day)}';
}

String _addDays(String dateStr, int n) {
  final d = DateTime.parse('\${dateStr}T00:00:00').add(Duration(days: n));
  final p = (int x) => x.toString().padLeft(2, '0');
  return '\${d.year}-\${p(d.month)}-\${p(d.day)}';
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
      .replaceAll(RegExp(r'[ss]'), 's').replaceAll(RegExp(r'[gg]'), 'g')
      .replaceAll(RegExp(r'[uu]'), 'u').replaceAll(RegExp(r'[oo]'), 'o')
      .replaceAll(RegExp(r'[cc]'), 'c').replaceAll(RegExp(r'[ii]'), 'i')
      .replaceAll(RegExp(r'[eeee]'), 'e').replaceAll(RegExp(r'[aaaa]'), 'a')
      .replaceAll(RegExp(r'[nn]'), 'n');
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

// ADIM 1: HTML sayfalarindan seed event ID adaylarini topla
Future<Set<int>> _collectSeedIdsFromHtml() async {
  final candidates = <int>{};
  final pages = [
    '\$_bilyonerBase/canli-iddaa',
    '\$_bilyonerBase/iddaa/futbol',
    '\$_bilyonerBase/iddaa',
  ];

  for (final pageUrl in pages) {
    try {
      final res = await http.get(Uri.parse(pageUrl), headers: {
        'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
        'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'accept-language': 'tr,en-US;q=0.9,en;q=0.8',
      }).timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) continue;
      final body = res.body;
      print('  [LOG] HTML cekildi: \$pageUrl (\${body.length} char)');

      // Pattern A: /mac-karti/futbol/{ID}/ linkleri
      for (final m in RegExp(r'/mac-karti/futbol/(\d{6,8})/').allMatches(body)) {
        final id = _int(m.group(1)); if (id != null) candidates.add(id);
      }
      // Pattern B: data-event-id attribute
      for (final m in RegExp(r'data-event-id="(\d{6,8})"').allMatches(body)) {
        final id = _int(m.group(1)); if (id != null) candidates.add(id);
      }
      // Pattern C: eventId= (query string veya JSON)
      for (final m in RegExp(r'(?:"eventId"|eventId=)(\d{6,8})').allMatches(body)) {
        final id = _int(m.group(1)); if (id != null) candidates.add(id);
      }
      // Pattern D: window.INITIAL_STATE veya __NEXT_DATA__ icindeki buyuk sayilar
      final stateIdx = body.indexOf('INITIAL_STATE');
      final nextIdx  = body.indexOf('__NEXT_DATA__');
      for (final idx in [stateIdx, nextIdx].where((i) => i >= 0)) {
        final win = body.substring(idx, (idx + 60000).clamp(0, body.length));
        for (final m in RegExp(r'\b(\d{7,8})\b').allMatches(win)) {
          final id = _int(m.group(1));
          if (id != null && id > 2000000) candidates.add(id);
        }
      }

      if (candidates.isNotEmpty) {
        print('  [LOG] HTML kaynagli \${candidates.length} aday ID');
        break;
      }
    } catch (e) {
      print('  [WARN] HTML hatasi (\$pageUrl): \$e');
    }
  }
  return candidates;
}

// ADIM 2: gamelist/events/{id} ile seed ID dogrula
// HAR kaniti: 200 doner, htn+atn icerir, auth gerektirmez
Future<int?> _findValidSeedId(Set<int> candidates) async {
  final toTry = candidates.toList()..sort((a, b) => b.compareTo(a));
  for (final id in toTry.take(30)) {
    try {
      final url = '\$_bilyonerBase/api/v3/mobile/aggregator/gamelist/events/\$id';
      final res = await http.get(Uri.parse(url), headers: _bilyonerHeaders())
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['htn'] != null) {
          print('  [LOG] Gecerli seed ID: \$id (\${data["htn"]} vs \${data["atn"]})');
          return id;
        }
      }
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 60));
  }
  return null;
}

// ADIM 3: league-events ile tum canli + yaklasan maclari cek
// HAR kaniti: liveGameList + preGameList, htn+atn icinde
Future<void> _fetchLeagueEvents(int seedId, List<Map<String, dynamic>> target) async {
  final url = '\$_bilyonerBase/api/v3/mobile/aggregator/match-card/\$seedId/league-events';
  try {
    print('  [LOG] league-events cekiliyor (seed=\$seedId)');
    final res = await http.get(
      Uri.parse(url),
      headers: _bilyonerHeaders(referer: '\$_bilyonerBase/mac-karti/futbol/\$seedId/oranlar/1'),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      print('  [WARN] league-events HTTP \${res.statusCode}');
      return;
    }
    final data = jsonDecode(res.body);
    int count = 0;

    void extract(dynamic list) {
      for (final ev in (list ?? []) as List) {
        final id  = _int(ev['id']);
        final htn = ev['htn']?.toString();
        final atn = ev['atn']?.toString();
        if (id != null && id > 0 && htn != null && htn.isNotEmpty && atn != null && atn.isNotEmpty) {
          target.add({'id': id, 'home': htn, 'away': atn});
          count++;
        }
      }
    }

    extract(data['liveGameList']?['events']);
    extract(data['preGameList']?['events']);
    print('  [LOG] league-events: \$count mac (live+pre)');
  } catch (e) {
    print('  [ERROR] league-events: \$e');
  }
}

// ADIM 4: Son bilinen ID araligini tara (son care)
Future<int?> _scanIdRange() async {
  print('  [WARN] Aralik taramasi basladi...');
  // ID'ler zaman icerisinde artarak gidiyor (~gunde 100-300 yeni event)
  // Son bilinen'den ileri de dene
  final startHigh = _lastKnownEventId + 2000;
  final startLow  = _lastKnownEventId - 500;

  for (int id = startHigh; id >= startLow; id -= 15) {
    try {
      final url = '\$_bilyonerBase/api/v3/mobile/aggregator/gamelist/events/\$id';
      final res = await http.get(Uri.parse(url), headers: _bilyonerHeaders())
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['htn'] != null) {
          print('  [LOG] Aralik taramasinda seed: \$id');
          return id;
        }
      }
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 40));
  }
  return null;
}

// Supabase patch
Future<void> _patch(String table, int fid, Map<String, dynamic> data) async {
  try {
    final res = await http.patch(
      Uri.parse('\$_sbUrl/rest/v1/\$table?fixture_id=eq.\$fid'),
      headers: {..._sbHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode >= 300) {
      print('    [ERROR] \$table patch: \${res.statusCode} \${res.body}');
    }
  } catch (e) {
    print('    [ERROR] \$table patch exception: \$e');
  }
}

Future<void> main() async {
  print('[INFO] Bilyoner Sync basliyor...');
  if (_sbUrl.isEmpty || _sbKey.isEmpty) {
    print('[ERROR] SUPABASE env eksik.');
    exit(1);
  }

  // 1. BILYONER MAC LiSTESi
  print('[INFO] Bilyoner mac listesi cekiliyor...');
  final List<Map<String, dynamic>> rawEvents = [];

  final seedCandidates = await _collectSeedIdsFromHtml();
  int? seedId = await _findValidSeedId(seedCandidates);
  seedId ??= await _scanIdRange();

  if (seedId != null) {
    await _fetchLeagueEvents(seedId, rawEvents);
  }

  if (rawEvents.isEmpty) {
    print('[ERROR] Bilyoner'den hic mac cekilemedi.');
    exit(1);
  }

  final unique = <int, Map<String, dynamic>>{};
  for (final m in rawEvents) unique[m['id'] as int] = m;
  final bilyonerMatches = unique.values.toList();
  print('  [INFO] Toplam benzersiz mac: \${bilyonerMatches.length}');

  // 2. SUPABASE live_matches
  final liveRes = await http.get(
    Uri.parse('\$_sbUrl/rest/v1/live_matches'
        '?select=fixture_id,home_team,away_team,bilyoner_id'
        '&status_short=in.(1H,2H,HT,ET,BT,P,LIVE,NS)'),
    headers: _sbHeaders(),
  ).timeout(const Duration(seconds: 15));
  if (liveRes.statusCode != 200) { print('[ERROR] live_matches: \${liveRes.statusCode}'); exit(1); }
  final liveList = (jsonDecode(liveRes.body) as List).cast<Map>();
  print('  [INFO] Supabase: \${liveList.length} canli/NS mac.');

  // 3. SUPABASE future_matches
  final today = _todayTR();
  final cutoff = _addDays(today, 3);
  final futRes = await http.get(
    Uri.parse('\$_sbUrl/rest/v1/future_matches'
        '?select=fixture_id,data,bilyoner_id'
        '&date=gte.\$today&date=lte.\$cutoff'),
    headers: _sbHeaders(),
  ).timeout(const Duration(seconds: 15));
  if (futRes.statusCode != 200) { print('[ERROR] future_matches: \${futRes.statusCode}'); exit(1); }
  final futList = <Map<String, dynamic>>[];
  for (final row in (jsonDecode(futRes.body) as List).cast<Map>()) {
    final fid = _int(row['fixture_id']); if (fid == null) continue;
    String home = '', away = '';
    try {
      final d = row['data'] is String ? jsonDecode(row['data'] as String) : row['data'];
      final p = d is List ? d[0] : d;
      home = p?['teams']?['home']?['name']?.toString() ?? '';
      away = p?['teams']?['away']?['name']?.toString() ?? '';
    } catch (_) {}
    futList.add({'fixture_id': fid, 'home': home, 'away': away, 'bilyoner_id': row['bilyoner_id']});
  }
  print('  [INFO] Supabase: \${futList.length} gelecek mac.');

  // 4. ESLESTIR ve YAZ
  int liveMatched = 0, futMatched = 0, skipped = 0;
  for (final bm in bilyonerMatches) {
    final bid   = bm['id'] as int;
    final bHome = _norm(bm['home'].toString());
    final bAway = _norm(bm['away'].toString());

    Map? bestLive; double bestLiveScore = 0;
    for (final sb in liveList) {
      if (_int(sb['bilyoner_id']) == bid) { bestLive = sb; bestLiveScore = 1.0; break; }
      if (_int(sb['bilyoner_id']) != null) continue;
      final hs  = _sim(bHome, _norm(sb['home_team']?.toString() ?? ''));
      final as_ = _sim(bAway, _norm(sb['away_team']?.toString() ?? ''));
      if (hs < 0.45 || as_ < 0.45) continue;
      final s = (hs + as_) / 2;
      if (s > bestLiveScore) { bestLiveScore = s; bestLive = sb; }
    }
    if (bestLive != null && bestLiveScore >= 0.55) {
      final fid = _int(bestLive['fixture_id'])!;
      if (_int(bestLive['bilyoner_id']) != bid) {
        print('  [LINK] [LIVE] Bilyoner:\$bid <-> Supabase:\$fid (\${bestLiveScore.toStringAsFixed(2)}) | \${bm["home"]} vs \${bm["away"]}');
        await _patch('live_matches', fid, {'bilyoner_id': bid});
      }
      liveMatched++; continue;
    }

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
        print('  [LINK] [FUTURE] Bilyoner:\$bid <-> Supabase:\$fid (\${bestFutScore.toStringAsFixed(2)}) | \${bm["home"]} vs \${bm["away"]}');
        await _patch('future_matches', fid, {'bilyoner_id': bid});
      }
      futMatched++;
    } else {
      skipped++;
    }
  }

  print('========================================');
  print('  [OK]   Live eslendi  : \$liveMatched');
  print('  [OK]   Future eslendi: \$futMatched');
  print('  [WARN] Eslesmedi     : \$skipped');
  print('  [INFO] Toplam Bilyoner: \${bilyonerMatches.length}');
  print('========================================');
  exit(0);
}
