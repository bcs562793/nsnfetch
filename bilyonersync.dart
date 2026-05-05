// bilyoner_sync.dart — GitHub Actions cron ile çalışır
// Bilyoner canlı maç listesi → live_matches.bilyoner_id + future_matches.bilyoner_id yazar

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

final _sbUrl = Platform.environment['SUPABASE_URL'] ?? '';
final _sbKey = Platform.environment['SUPABASE_KEY'] ?? '';

const _bilyonerBase  = 'https://www.bilyoner.com';
const _platformToken = '40CAB7292CD83F7EE0631FC35A0AFC75';
const _deviceId      = 'C1A34687-8F75-47E8-9FF9-1D231F05782E';

Future<void> main() async {
  print('🔄 Bilyoner Sync başlıyor...');

  if (_sbUrl.isEmpty || _sbKey.isEmpty) {
    print('❌ SUPABASE env eksik'); exit(1);
  }

  // ── 1. Bilyoner'den canlı futbol maçlarını çek ─────────────────
  print('📡 Bilyoner canlı maç listesi çekiliyor...');

  final List<Map<String, dynamic>> bilyonerMatches = [];

  // Yöntem A: live-score event listesi (sbsEventId + takım adları)
  try {
    final res = await http.get(
      Uri.parse('$_bilyonerBase/api/mobile/live-score/event/v2/sport-list?sportType=SOCCER'),
      headers: _bilyonerHeaders(),
    ).timeout(const Duration(seconds: 20));

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final events = body['events'] as List? ?? [];
      for (final ev in events) {
        if (ev is! Map) continue;
        final sbsId = _int(ev['sbsEventId'] ?? ev['id']);
        final htn   = (ev['homeTeamName']  ?? ev['htn'] ?? '').toString();
        final atn   = (ev['awayTeamName']  ?? ev['atn'] ?? '').toString();
        if (sbsId == null || htn.isEmpty) continue;
        bilyonerMatches.add({'id': sbsId, 'home': htn, 'away': atn, 'source': 'live-score'});
      }
      print('   live-score: ${bilyonerMatches.length} maç');
    }
  } catch (e) {
    print('   ⚠️ live-score hatası: $e');
  }

  // Yöntem B: bulletinType=1 (canlı iddaa bülteni) — daha fazla maç içerir
  try {
    final res = await http.get(
      Uri.parse('$_bilyonerBase/api/sportsbetting/sports/1/events?bulletinType=1'),
      headers: _bilyonerHeaders(),
    ).timeout(const Duration(seconds: 20));

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final events = (body is List ? body : (body['events'] ?? body['data'] ?? [])) as List;
      int added = 0;
      for (final ev in events) {
        if (ev is! Map) continue;
        final sbsId = _int(ev['id'] ?? ev['sbsEventId'] ?? ev['eventId']);
        final htn   = (ev['homeTeamName'] ?? ev['home'] ?? ev['htn'] ?? '').toString();
        final atn   = (ev['awayTeamName'] ?? ev['away'] ?? ev['atn'] ?? '').toString();
        if (sbsId == null || htn.isEmpty) continue;
        // Duplicate kontrolü
        if (bilyonerMatches.any((m) => m['id'] == sbsId)) continue;
        bilyonerMatches.add({'id': sbsId, 'home': htn, 'away': atn, 'source': 'bulletin'});
        added++;
      }
      print('   bulletin(1): $added ek maç');
    }
  } catch (e) {
    print('   ⚠️ bulletin(1) hatası: $e');
  }

  // Yöntem C: pre-match bülteni (bulletinType=3) — yaklaşan maçlar için
  try {
    final res = await http.get(
      Uri.parse('$_bilyonerBase/api/sportsbetting/sports/1/events?bulletinType=3'),
      headers: _bilyonerHeaders(),
    ).timeout(const Duration(seconds: 20));

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final events = (body is List ? body : (body['events'] ?? body['data'] ?? [])) as List;
      int added = 0;
      for (final ev in events) {
        if (ev is! Map) continue;
        final sbsId = _int(ev['id'] ?? ev['sbsEventId'] ?? ev['eventId']);
        final htn   = (ev['homeTeamName'] ?? ev['home'] ?? ev['htn'] ?? '').toString();
        final atn   = (ev['awayTeamName'] ?? ev['away'] ?? ev['atn'] ?? '').toString();
        if (sbsId == null || htn.isEmpty) continue;
        if (bilyonerMatches.any((m) => m['id'] == sbsId)) continue;
        bilyonerMatches.add({'id': sbsId, 'home': htn, 'away': atn, 'source': 'prematch'});
        added++;
      }
      print('   bulletin(3): $added ek maç');
    }
  } catch (e) {
    print('   ⚠️ bulletin(3) hatası: $e');
  }

  if (bilyonerMatches.isEmpty) {
    print('❌ Bilyoner\'den hiç maç çekilemedi. Çıkılıyor.');
    exit(1);
  }
  print('   Toplam: ${bilyonerMatches.length} Bilyoner maçı');

  // ── 2. Supabase'den live_matches çek ───────────────────────────
  print('\n📡 Supabase live_matches çekiliyor...');
  final liveRes = await http.get(
    Uri.parse('$_sbUrl/rest/v1/live_matches'
        '?select=fixture_id,home_team,away_team,bilyoner_id'
        '&status_short=in.(1H,2H,HT,ET,BT,P,LIVE,NS)'),
    headers: _sbHeaders(),
  ).timeout(const Duration(seconds: 15));

  if (liveRes.statusCode != 200) {
    print('❌ live_matches HTTP ${liveRes.statusCode}'); exit(1);
  }
  final liveList = (jsonDecode(liveRes.body) as List).cast<Map>();
  print('   ${liveList.length} canlı maç');

  // ── 3. Supabase'den future_matches çek ────────────────────────
  print('📡 Supabase future_matches çekiliyor...');
  final today  = _todayTR();
  final cutoff = _addDays(today, 3);
  final futRes = await http.get(
    Uri.parse('$_sbUrl/rest/v1/future_matches'
        '?select=fixture_id,data,bilyoner_id'
        '&date=gte.$today&date=lte.$cutoff'),
    headers: _sbHeaders(),
  ).timeout(const Duration(seconds: 15));

  if (futRes.statusCode != 200) {
    print('❌ future_matches HTTP ${futRes.statusCode}'); exit(1);
  }

  // future_matches'ten takım adlarını parse et
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
  print('   ${futList.length} gelecek maç');

  // ── 4. Eşleştir ve yaz ────────────────────────────────────────
  int liveMatched = 0, futMatched = 0, skipped = 0;

  for (final bm in bilyonerMatches) {
    final bid  = bm['id'] as int;
    final bHome = _norm(bm['home'].toString());
    final bAway = _norm(bm['away'].toString());

    // live_matches'te ara
    Map? bestLive; double bestLiveScore = 0;
    for (final sb in liveList) {
      // Zaten yazılmışsa atla
      if (_int(sb['bilyoner_id']) == bid) { bestLive = sb; bestLiveScore = 1.0; break; }
      if (_int(sb['bilyoner_id']) != null) continue; // başka ID yazılmış, atla

      final hs = _sim(bHome, _norm(sb['home_team']?.toString() ?? ''));
      final as_ = _sim(bAway, _norm(sb['away_team']?.toString() ?? ''));
      if (hs < 0.45 || as_ < 0.45) continue;
      final s = (hs + as_) / 2;
      if (s > bestLiveScore) { bestLiveScore = s; bestLive = sb; }
    }

    if (bestLive != null && bestLiveScore >= 0.55) {
      final fid = _int(bestLive['fixture_id'])!;
      if (_int(bestLive['bilyoner_id']) != bid) {
        print('🔗 [LIVE] bid=$bid ↔ fid=$fid (${bestLiveScore.toStringAsFixed(2)}) ${bm["home"]} vs ${bm["away"]}');
        await _patch('live_matches', fid, {'bilyoner_id': bid});
      }
      liveMatched++;
    }

    // future_matches'te ara
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
        print('🔗 [FUT]  bid=$bid ↔ fid=$fid (${bestFutScore.toStringAsFixed(2)}) ${bm["home"]} vs ${bm["away"]}');
        await _patch('future_matches', fid, {'bilyoner_id': bid});
      }
      futMatched++;
    }

    if ((bestLive == null || bestLiveScore < 0.55) &&
        (bestFut  == null || bestFutScore  < 0.55)) {
      print('⚠️  Eşleşme yok: ${bm["home"]} vs ${bm["away"]} (bid=$bid, src=${bm["source"]})');
      skipped++;
    }
  }

  print('\n══════════════════════════════════════');
  print('  ✅ Live eşleşti  : $liveMatched');
  print('  ✅ Fut eşleşti   : $futMatched');
  print('  ⚠️  Eşleşmedi    : $skipped');
  print('  📦 Toplam        : ${bilyonerMatches.length}');
  print('══════════════════════════════════════');
  exit(0);
}

// ── Supabase patch ─────────────────────────────────────────────
Future<void> _patch(String table, int fid, Map<String, dynamic> data) async {
  try {
    final res = await http.patch(
      Uri.parse('$_sbUrl/rest/v1/$table?fixture_id=eq.$fid'),
      headers: {..._sbHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode >= 300) {
      print('   ❌ $table patch hatası: ${res.statusCode} ${res.body}');
    }
  } catch (e) {
    print('   ❌ $table patch exception: $e');
  }
}

// ── Bilyoner headers ───────────────────────────────────────────
Map<String, String> _bilyonerHeaders() => {
  'accept':                   'application/json, text/plain, */*',
  'accept-language':          'tr',
  'cache-control':            'no-cache',
  'pragma':                   'no-cache',
  'referer':                  '$_bilyonerBase/canli-iddaa',
  'user-agent':               'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36',
  'platform-token':           _platformToken,
  'x-client-app-version':     '3.95.2',
  'x-client-browser-version': 'Chrome / v146.0.0.0',
  'x-client-channel':         'WEB',
  'x-device-id':              _deviceId,
};

Map<String, String> _sbHeaders() => {
  'apikey':        _sbKey,
  'Authorization': 'Bearer $_sbKey',
  'Prefer':        'return=minimal',
};

// ── Tarih yardımcıları ─────────────────────────────────────────
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

// ── Yardımcılar ────────────────────────────────────────────────
int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString());
}

String _norm(String s) => s.toLowerCase()
    .replaceAll('ı','i').replaceAll('ğ','g').replaceAll('ü','u')
    .replaceAll('ş','s').replaceAll('ö','o').replaceAll('ç','c')
    .replaceAll('é','e').replaceAll('è','e').replaceAll('ê','e').replaceAll('ë','e')
    .replaceAll('á','a').replaceAll('à','a').replaceAll('â','a').replaceAll('ä','a').replaceAll('ã','a')
    .replaceAll('ó','o').replaceAll('ò','o').replaceAll('ô','o').replaceAll('õ','o')
    .replaceAll('ú','u').replaceAll('ù','u').replaceAll('û','u')
    .replaceAll('í','i').replaceAll('ì','i').replaceAll('î','i')
    .replaceAll('ñ','n').replaceAll('ø','o').replaceAll('å','a')
    .replaceAll('ć','c').replaceAll('č','c').replaceAll('ž','z').replaceAll('š','s')
    .replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

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
