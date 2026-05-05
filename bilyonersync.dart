// bilyoner_id_sync.dart
// /api/v3/mobile/aggregator/gamelist/all/v1 endpoint'inden
// events{id:{htn,atn}} yapisiyla mac listesi ceker,
// future_matches tablosuna bilyoner_id yazar.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

final _sbUrl = Platform.environment['SUPABASE_URL'] ?? '';
final _sbKey = Platform.environment['SUPABASE_KEY'] ?? '';

const _bilyonerBase = 'https://www.bilyoner.com';
const _platformToken = '40CAB7292CD83F7EE0631FC35A0AFC75';

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

String _norm(String name) {
  var s = name.toLowerCase().trim();
  if (_nicknames.containsKey(s)) s = _nicknames[s]!;
  s = s
      .replaceAll('\u015f', 's').replaceAll('\u011f', 'g')
      .replaceAll('\xfc', 'u').replaceAll('\xf6', 'o')
      .replaceAll('\xe7', 'c').replaceAll('\u0131', 'i')
      .replaceAll(RegExp(r'[\xe9\xe8\xea]'), 'e')
      .replaceAll(RegExp(r'[\xe0\xe2\xe4]'), 'a')
      .replaceAll('\xf1', 'n');
  s = s.replaceAll(RegExp(r"[.\-/'()]"), ' ');
  return s
      .split(RegExp(r'\s+'))
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

Map<String, String> _apiHeaders() => {
  'accept':               'application/json, text/plain, */*',
  'accept-language':      'tr,en-US;q=0.9,en;q=0.8',
  'cache-control':        'no-cache',
  'pragma':               'no-cache',
  'platform-token':       _platformToken,
  'x-client-channel':     'WEB',
  'x-client-app-version': '3.98.1',
  'referer':              '$_bilyonerBase/iddaa',
  'user-agent':           'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
};

// ADIM 1: Bilyoner gamelist API'den mac listesi cek
// events objesi: {"ID": {"htn": "Home", "atn": "Away", ...}}
// tabType=1 -> normal iddaa (190 mac, 4 gun)
Future<Map<int, Map<String, String>>> _fetchBilyonerMatches() async {
  final result = <int, Map<String, String>>{};
  final tabTypes = [1, 137]; // 1=normal, 137=diger tab
  for (final tab in tabTypes) {
    final url = '$_bilyonerBase/api/v3/mobile/aggregator/gamelist/all/v1'
        '?tabType=$tab&bulletinType=2';
    try {
      print('  [LOG] API: tabType=$tab');
      final res = await http.get(Uri.parse(url), headers: _apiHeaders())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        print('  [WARN] HTTP ${res.statusCode} tabType=$tab'); continue;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final events = data['events'] as Map<String, dynamic>?;
      if (events == null) { print('  [WARN] events null tabType=$tab'); continue; }
      int count = 0;
      for (final entry in events.entries) {
        final id  = int.tryParse(entry.key);
        final ev  = entry.value as Map<String, dynamic>?;
        final htn = ev?['htn']?.toString();
        final atn = ev?['atn']?.toString();
        if (id == null || htn == null || htn.isEmpty || atn == null || atn.isEmpty) continue;
        result.putIfAbsent(id, () => {'home': htn, 'away': atn});
        count++;
      }
      print('  [LOG] tabType=$tab: $count mac');
    } catch (e) {
      print('  [ERROR] tabType=$tab: $e');
    }
    await Future.delayed(const Duration(milliseconds: 200));
  }
  return result;
}

// ADIM 2: future_matches'den bilyoner_id bos olan kayitlari cek (pagination)
Future<List<Map<String, dynamic>>> _fetchFutureMatches() async {
  final now    = DateTime.now().toUtc().add(const Duration(hours: 3));
  final pad    = (int n) => n.toString().padLeft(2, '0');
  final today  = '${now.year}-${pad(now.month)}-${pad(now.day)}';
  final end    = now.add(const Duration(days: 5));
  final cutoff = '${end.year}-${pad(end.month)}-${pad(end.day)}';

  final rows = <Map<String, dynamic>>[];
  const pageSize = 1000;
  int offset = 0;

  while (true) {
    final res = await http.get(
      Uri.parse('$_sbUrl/rest/v1/future_matches'
          '?select=fixture_id,data'
          '&bilyoner_id=is.null'
          '&date=gte.$today'
          '&date=lte.$cutoff'
          '&limit=$pageSize'
          '&offset=$offset'),
      headers: {
        'apikey':        _sbKey,
        'Authorization': 'Bearer $_sbKey',
        'Prefer':        'count=exact',
      },
    ).timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      print('[ERROR] future_matches: ${res.statusCode}'); break;
    }

    final page = (jsonDecode(res.body) as List).cast<Map>();
    for (final row in page) {
      final fid = row['fixture_id'] as int?; if (fid == null) continue;
      String home = '', away = '';
      try {
        final d = row['data'] is String
            ? jsonDecode(row['data'] as String) as Map
            : row['data'] as Map;
        home = d['teams']?['home']?['name']?.toString() ?? '';
        away = d['teams']?['away']?['name']?.toString() ?? '';
      } catch (_) {}
      if (home.isEmpty && away.isEmpty) continue;
      rows.add({'fixture_id': fid, 'home': home, 'away': away});
    }

    print('  [LOG] Sayfa offset=$offset: ${page.length} satir alindi');
    if (page.length < pageSize) break; // son sayfa
    offset += pageSize;
    await Future.delayed(const Duration(milliseconds: 100));
  }

  print('[INFO] future_matches: ${rows.length} kayit (bilyoner_id bos)');
  return rows;
}

// ADIM 3: PATCH - sadece bilyoner_id kolonunu guncelle
Future<void> _patch(int fixtureId, int bilyonerId) async {
  final res = await http.patch(
    Uri.parse('$_sbUrl/rest/v1/future_matches?fixture_id=eq.$fixtureId'),
    headers: {
      'apikey':        _sbKey,
      'Authorization': 'Bearer $_sbKey',
      'Content-Type':  'application/json',
      'Prefer':        'return=minimal',
    },
    body: jsonEncode({'bilyoner_id': bilyonerId}),
  ).timeout(const Duration(seconds: 8));
  if (res.statusCode >= 300)
    print('  [ERROR] PATCH fixture=$fixtureId: ${res.statusCode}');
}

Future<void> main() async {
  print('[INFO] Bilyoner ID Sync basliyor...');
  if (_sbUrl.isEmpty || _sbKey.isEmpty) {
    print('[ERROR] SUPABASE_URL / SUPABASE_KEY eksik'); exit(1);
  }

  // 1. Bilyoner API'den mac listesi
  final bilyonerMap = await _fetchBilyonerMatches();
  if (bilyonerMap.isEmpty) {
    print('[ERROR] Bilyoner mac listesi bos'); exit(1);
  }
  print('[INFO] Bilyoner toplam: ${bilyonerMap.length} benzersiz mac');

  // 2. Supabase'den eslenecek kayitlar
  final futureRows = await _fetchFutureMatches();
  if (futureRows.isEmpty) {
    print('[INFO] Eslenecek kayit yok'); exit(0);
  }

  // 3. Eslestir ve bilyoner_id yaz
  int matched = 0, skipped = 0;
  for (final entry in bilyonerMap.entries) {
    final bid   = entry.key;
    final bHome = _norm(entry.value['home']!);
    final bAway = _norm(entry.value['away']!);

    Map<String, dynamic>? best; double bestScore = 0;
    for (final row in futureRows) {
      final hs  = _sim(bHome, _norm(row['home']));
      final as_ = _sim(bAway, _norm(row['away']));
      if (hs < 0.45 || as_ < 0.45) continue;
      final s = (hs + as_) / 2;
      if (s > bestScore) { bestScore = s; best = row; }
    }

    if (best != null && bestScore >= 0.55) {
      final fid = best['fixture_id'] as int;
      print('  [MATCH] $bid -> fixture:$fid (${bestScore.toStringAsFixed(2)}) | ${entry.value["home"]} - ${entry.value["away"]}');
      await _patch(fid, bid);
      matched++;
    } else {
      skipped++;
    }
  }

  print('========================================');
  print('  [OK]   Eslenen    : $matched');
  print('  [SKIP] Eslesmeyen : $skipped');
  print('  [INFO] Bilyoner   : ${bilyonerMap.length} mac');
  print('  [INFO] Supabase   : ${futureRows.length} kayit');
  print('========================================');
  exit(0);
}
