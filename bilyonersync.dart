// bilyoner_id_sync.dart
// Bilyoner /iddaa HTML'inden mac ID + takim adi ceker,
// future_matches tablosundaki eslesen maclara bilyoner_id yazar.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

final _sbUrl = Platform.environment['SUPABASE_URL'] ?? '';
final _sbKey = Platform.environment['SUPABASE_KEY'] ?? '';

const _bilyonerBase = 'https://www.bilyoner.com';

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

// ── ADIM 1: Bilyoner /iddaa HTML'inden mac listesi cek ─────────────
// HTML'de: <a title="Home - Away" href="/mac-karti/futbol/ID/oranlar...
// Bu sekilde hem ID hem takim adi tek satirda geliyor.
Future<Map<int, Map<String,String>>> _fetchBilyonerFromHtml() async {
  final result = <int, Map<String,String>>{};
  // Bugun + sonraki gunler icin URL listesi
  final today = DateTime.now().toUtc().add(const Duration(hours: 3));
  final urls = <String>[];
  for (int i = 0; i < 5; i++) {
    final d = today.add(Duration(days: i));
    final ds = '${d.year}-${d.month.toString().padLeft(2,"0")}-${d.day.toString().padLeft(2,"0")}';
    urls.add('$_bilyonerBase/iddaa/futbol?date=$ds');
  }
  urls.insert(0, '$_bilyonerBase/iddaa');        // varsayilan sayfa
  urls.insert(1, '$_bilyonerBase/iddaa/futbol'); // futbol filtresi

  // Regex: title="Home - Away" href="/mac-karti/futbol/ID/
  final re = RegExp(
    r'title="([^"]+)" href="/mac-karti/futbol/(\d+)/oranlar',
  );

  for (final url in urls) {
    try {
      print('  [LOG] HTML cekiliyor: $url');
      final res = await http.get(Uri.parse(url), headers: {
        'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
        'accept': 'text/html,application/xhtml+xml',
        'accept-language': 'tr-TR,tr;q=0.9',
        'referer': '$_bilyonerBase/',
      }).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        print('  [WARN] HTTP ${res.statusCode}: $url'); continue;
      }

      int found = 0;
      for (final m in re.allMatches(res.body)) {
        final title = m.group(1) ?? '';   // 'Home - Away'
        final id    = int.tryParse(m.group(2) ?? '');
        if (id == null || title.isEmpty) continue;
        // title'i ' - ' ile bol -> home / away
        final sep = title.indexOf(' - ');
        if (sep < 0) continue;
        final home = title.substring(0, sep).trim();
        final away = title.substring(sep + 3).trim();
        if (home.isEmpty || away.isEmpty) continue;
        result.putIfAbsent(id, () => {'home': home, 'away': away});
        found++;
      }
      print('  [LOG] $url -> $found mac ID bulundu');
    } catch (e) {
      print('  [WARN] $url hata: $e');
    }
    await Future.delayed(const Duration(milliseconds: 300));
  }
  return result;
}

// ── ADIM 2: future_matches'den bilyoner_id bos olanlari cek ────────
Future<List<Map<String,dynamic>>> _fetchFutureMatches() async {
  final now = DateTime.now().toUtc().add(const Duration(hours: 3));
  final today  = '${now.year}-${now.month.toString().padLeft(2,"0")}-${now.day.toString().padLeft(2,"0")}';
  final cutoff = () {
    final d = now.add(const Duration(days: 5));
    return '${d.year}-${d.month.toString().padLeft(2,"0")}-${d.day.toString().padLeft(2,"0")}';
  }();
  final res = await http.get(
    Uri.parse('$_sbUrl/rest/v1/future_matches'
        '?select=fixture_id,data'
        '&bilyoner_id=is.null'
        '&date=gte.$today'
        '&date=lte.$cutoff'
        '&limit=2000'),
    headers: {'apikey': _sbKey, 'Authorization': 'Bearer $_sbKey'},
  ).timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) {
    print('[ERROR] future_matches cekme: ${res.statusCode}'); return [];
  }
  final rows = <Map<String,dynamic>>[];
  for (final row in (jsonDecode(res.body) as List).cast<Map>()) {
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
  print('[INFO] future_matches: ${rows.length} kayit (bilyoner_id bos)');
  return rows;
}

// ── ADIM 3: PATCH bilyoner_id ───────────────────────────────────────
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

  // 1. Bilyoner HTML'den mac listesi
  final bilyonerMap = await _fetchBilyonerFromHtml();
  if (bilyonerMap.isEmpty) {
    print('[ERROR] Bilyoner HTML parse edilemedi'); exit(1);
  }
  print('[INFO] Bilyoner toplam: ${bilyonerMap.length} benzersiz mac');

  // 2. future_matches bilyoner_id bos kayitlar
  final futureRows = await _fetchFutureMatches();
  if (futureRows.isEmpty) {
    print('[INFO] Esleme yapilacak kayit yok'); exit(0);
  }

  // 3. Eslestir ve yaz
  int matched = 0, skipped = 0;
  for (final entry in bilyonerMap.entries) {
    final bid   = entry.key;
    final bHome = _norm(entry.value['home']!);
    final bAway = _norm(entry.value['away']!);

    Map<String,dynamic>? best; double bestScore = 0;
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
  print('  [OK]  Eslenen  : $matched');
  print('  [SKIP] Eslesmeyen: $skipped');
  print('  [INFO] Bilyoner : ${bilyonerMap.length} mac');
  print('  [INFO] Supabase : ${futureRows.length} kayit');
  print('========================================');
  exit(0);
}
