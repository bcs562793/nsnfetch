// bilyoner_id_sync.dart
// future_matches tablosundaki maclarda bilyoner_id kolonunu doldurur.
// Baska hicbir sey yapmaz.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

final _sbUrl = Platform.environment['SUPABASE_URL'] ?? '';
final _sbKey = Platform.environment['SUPABASE_KEY'] ?? '';

const _bilyonerBase  = 'https://www.bilyoner.com';
const _platformToken = '40CAB7292CD83F7EE0631FC35A0AFC75';
const _lastKnownEventId = 2935198;

// Normalizasyon
const _nicknames = <String, String>{
  'spurs': 'tottenham', 'inter': 'internazionale',
};
const _wordTrToEn = <String, String>{
  'munih': 'munich', 'munchen': 'munich',
  'marsilya': 'marseille', 'kopenhag': 'copenhagen',
  'bruksel': 'brussels', 'prag': 'prague',
  'lizbon': 'lisbon', 'viyana': 'vienna',
};
const _noise = <String>{
  'fc','sc','cf','ac','if','bk','sk','fk',
  'afc','bfc','cfc','sfc','rfc',
  'cp','cd','sd','ud','rc','rcd','as','ss',
};

String? _cachedToken;
String? _cachedDevice;

String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2,'0')).join();
  return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
}

Map<String,String> _bHeaders() => {
  'accept':                   'application/json, text/plain, */*',
  'accept-language':          'tr,en-US;q=0.9,en;q=0.8',
  'cache-control':            'no-cache',
  'pragma':                   'no-cache',
  'referer':                  '$_bilyonerBase/canli-iddaa',
  'user-agent':               'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
  'platform-token':           _platformToken,
  'x-auth-token':             (_cachedToken ??= '${_uuid().replaceAll("-","")}${DateTime.now().millisecondsSinceEpoch}'),
  'x-client-app-version':     '3.98.1',
  'x-client-browser-version': 'Chrome / v147.0.0.0',
  'x-client-channel':         'WEB',
  'x-device-id':              (_cachedDevice ??= _uuid().toUpperCase()),
};

Map<String,String> _sbHeaders() => {
  'apikey':        _sbKey,
  'Authorization': 'Bearer $_sbKey',
};

String _norm(String name) {
  var s = name.toLowerCase().trim();
  if (_nicknames.containsKey(s)) s = _nicknames[s]!;
  s = s
      .replaceAll('\u015f','s').replaceAll('\u011f','g')
      .replaceAll('\xfc','u').replaceAll('\xf6','o')
      .replaceAll('\xe7','c').replaceAll('\u0131','i')
      .replaceAll(RegExp(r'[\xe9\xe8\xea]'),'e')
      .replaceAll(RegExp(r'[\xe0\xe2\xe4]'),'a')
      .replaceAll(RegExp(r'[\xf1n]'),'n');
  s = s.replaceAll(RegExp(r"[.\-/'()]"),' ');
  return s.split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !_noise.contains(t))
      .map((t) => _wordTrToEn[t] ?? t)
      .join(' ').trim();
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

// Bilyoner: seed ID bul
Future<int?> _findSeedId() async {
  // 1. HTML'den dene
  for (final url in ['$_bilyonerBase/canli-iddaa','$_bilyonerBase/iddaa/futbol']) {
    try {
      final res = await http.get(Uri.parse(url), headers: {
        'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
        'accept': 'text/html,application/xhtml+xml',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) continue;
      final body = res.body;
      final candidates = <int>{};
      for (final p in [
        RegExp(r'/mac-karti/futbol/(\d{6,8})/'),
        RegExp(r'(?:"eventId"|eventId=)(\d{6,8})'),
        RegExp(r'data-event-id="(\d{6,8})"'),
      ]) {
        for (final m in p.allMatches(body)) {
          final id = int.tryParse(m.group(1) ?? '');
          if (id != null) candidates.add(id);
        }
      }
      for (final kw in ['INITIAL_STATE','__NEXT_DATA__']) {
        final idx = body.indexOf(kw);
        if (idx < 0) continue;
        final win = body.substring(idx, (idx+60000).clamp(0,body.length));
        for (final m in RegExp(r'\b(\d{7,8})\b').allMatches(win)) {
          final id = int.tryParse(m.group(1) ?? '');
          if (id != null && id > 2000000) candidates.add(id);
        }
      }
      if (candidates.isNotEmpty) {
        final sorted = candidates.toList()..sort((a,b) => b.compareTo(a));
        for (final id in sorted.take(20)) {
          final r2 = await http.get(
            Uri.parse('$_bilyonerBase/api/v3/mobile/aggregator/gamelist/events/$id'),
            headers: _bHeaders(),
          ).timeout(const Duration(seconds: 5));
          if (r2.statusCode == 200 && jsonDecode(r2.body)['htn'] != null) {
            print('  [LOG] Seed ID (HTML): $id'); return id;
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    } catch (_) {}
  }
  // 2. Aralik taramasi
  print('  [LOG] Aralik taramasi...');
  for (int id = _lastKnownEventId + 2000; id >= _lastKnownEventId - 500; id -= 15) {
    try {
      final r = await http.get(
        Uri.parse('$_bilyonerBase/api/v3/mobile/aggregator/gamelist/events/$id'),
        headers: _bHeaders(),
      ).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200 && jsonDecode(r.body)['htn'] != null) {
        print('  [LOG] Seed ID (aralik): $id'); return id;
      }
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 40));
  }
  return null;
}

// Bilyoner: league-events ile tum maclari cek
Future<List<Map<String,dynamic>>> _fetchBilyonerMatches(int seedId) async {
  final url = '$_bilyonerBase/api/v3/mobile/aggregator/match-card/$seedId/league-events';
  try {
    final res = await http.get(
      Uri.parse(url),
      headers: _bHeaders()..['referer'] = '$_bilyonerBase/mac-karti/futbol/$seedId/oranlar/1',
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) { print('  [WARN] league-events ${res.statusCode}'); return []; }
    final data = jsonDecode(res.body);
    final result = <Map<String,dynamic>>[];
    void extract(dynamic list) {
      for (final ev in (list ?? []) as List) {
        final id  = (ev['id'] is num) ? (ev['id'] as num).toInt() : int.tryParse(ev['id'].toString());
        final htn = ev['htn']?.toString();
        final atn = ev['atn']?.toString();
        if (id != null && htn != null && htn.isNotEmpty && atn != null && atn.isNotEmpty)
          result.add({'id': id, 'home': htn, 'away': atn});
      }
    }
    extract(data['liveGameList']?['events']);
    extract(data['preGameList']?['events']);
    print('  [LOG] Bilyoner: ${result.length} mac (live+pre)');
    return result;
  } catch (e) { print('  [ERROR] league-events: $e'); return []; }
}

// future_matches: bilyoner_id bos olan kayitlari cek
Future<List<Map<String,dynamic>>> _fetchFutureMatches() async {
  try {
    final today = () {
      final n = DateTime.now().toUtc().add(const Duration(hours:3));
      return '${n.year}-${n.month.toString().padLeft(2,"0")}-${n.day.toString().padLeft(2,"0")}';
    }();
    final cutoff = () {
      final n = DateTime.now().toUtc().add(const Duration(hours:3, days:4));
      return '${n.year}-${n.month.toString().padLeft(2,"0")}-${n.day.toString().padLeft(2,"0")}';
    }();
    final res = await http.get(
      Uri.parse('$_sbUrl/rest/v1/future_matches'
          '?select=fixture_id,data'
          '&bilyoner_id=is.null'
          '&date=gte.$today'
          '&date=lte.$cutoff'),
      headers: _sbHeaders(),
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      print('[ERROR] future_matches: ${res.statusCode}'); return [];
    }
    final rows = <Map<String,dynamic>>[];
    for (final row in (jsonDecode(res.body) as List).cast<Map>()) {
      final fid = row['fixture_id'] as int?; if (fid == null) continue;
      String home = '', away = '';
      try {
        final d = row['data'] is String ? jsonDecode(row['data'] as String) : row['data'];
        final p = d is List ? d[0] : d;
        home = p?['teams']?['home']?['name']?.toString() ?? '';
        away = p?['teams']?['away']?['name']?.toString() ?? '';
      } catch (_) {}
      rows.add({'fixture_id': fid, 'home': home, 'away': away});
    }
    print('[INFO] future_matches: ${rows.length} kayit (bilyoner_id bos)');
    return rows;
  } catch (e) { print('[ERROR] future_matches cekme: $e'); return []; }
}

// PATCH: bilyoner_id yaz
Future<void> _patch(int fixtureId, int bilyonerId) async {
  try {
    final res = await http.patch(
      Uri.parse('$_sbUrl/rest/v1/future_matches?fixture_id=eq.$fixtureId'),
      headers: {..._sbHeaders(), 'Content-Type': 'application/json', 'Prefer': 'return=minimal'},
      body: jsonEncode({'bilyoner_id': bilyonerId}),
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode >= 300)
      print('  [ERROR] PATCH fixture=$fixtureId: ${res.statusCode} ${res.body}');
  } catch (e) { print('  [ERROR] PATCH $fixtureId: $e'); }
}

Future<void> main() async {
  print('[INFO] Bilyoner ID Sync basliyor...');
  if (_sbUrl.isEmpty || _sbKey.isEmpty) {
    print('[ERROR] SUPABASE_URL / SUPABASE_KEY eksik'); exit(1);
  }

  // 1. Bilyoner mac listesini cek
  final seedId = await _findSeedId();
  if (seedId == null) { print('[ERROR] Seed ID bulunamadi'); exit(1); }
  final bilyonerList = await _fetchBilyonerMatches(seedId);
  if (bilyonerList.isEmpty) { print('[ERROR] Bilyoner mac listesi bos'); exit(1); }

  // 2. future_matches'den bilyoner_id bos olanlari cek
  final futureRows = await _fetchFutureMatches();
  if (futureRows.isEmpty) { print('[INFO] Eslestirilecek kayit yok'); exit(0); }

  // 3. Eslestir ve yaz
  int matched = 0, skipped = 0;
  for (final bm in bilyonerList) {
    final bid   = bm['id'] as int;
    final bHome = _norm(bm['home']);
    final bAway = _norm(bm['away']);
    Map<String,dynamic>? best; double bestScore = 0;
    for (final row in futureRows) {
      final hs = _sim(bHome, _norm(row['home']));
      final as_ = _sim(bAway, _norm(row['away']));
      if (hs < 0.45 || as_ < 0.45) continue;
      final s = (hs + as_) / 2;
      if (s > bestScore) { bestScore = s; best = row; }
    }
    if (best != null && bestScore >= 0.55) {
      final fid = best['fixture_id'] as int;
      print('  [MATCH] Bilyoner:$bid <-> fixture:$fid (${bestScore.toStringAsFixed(2)}) | ${bm["home"]} vs ${bm["away"]}');
      await _patch(fid, bid);
      matched++;
    } else {
      skipped++;
    }
  }

  print('========================================');
  print('  [OK]   Eslesen : $matched');
  print('  [WARN] Eslesmeyen: $skipped');
  print('  [INFO] Bilyoner toplam: ${bilyonerList.length}');
  print('  [INFO] future_matches: ${futureRows.length}');
  print('========================================');
  exit(0);
}
