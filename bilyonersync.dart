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

// ── sync_fixtures(3)'ten alınan Takım İsim Normalizasyon Sabitleri ──
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

Future<void> main() async {
  print('🔄 Bilyoner Sync başlıyor...');

  if (_sbUrl.isEmpty || _sbKey.isEmpty) {
    print('❌ SUPABASE env eksik. Lütfen SUPABASE_URL ve SUPABASE_KEY ortam değişkenlerini ayarlayın.'); 
    exit(1);
  }

  // ── 1. Bilyoner'den canlı futbol maçlarını çek ─────────────────
  print('📡 Bilyoner maç listesi çekiliyor...');

  final List<Map<String, dynamic>> bilyonerMatches = [];

  // Yöntem A: live-score event listesi (sbsEventId + takım adları)
  try {
    print('  [LOG] İstek atılıyor: live-score (SOCCER)...');
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
      print('  ✅ live-score: ${events.length} event bulundu, ${bilyonerMatches.where((e) => e['source'] == 'live-score').length} maç eklendi.');
    } else {
      print('  ⚠️ live-score HTTP Hata Kodu: ${res.statusCode}');
      print('  ⚠️ Yanıt: ${res.body.length > 200 ? res.body.substring(0, 200) + '...' : res.body}');
    }
  } catch (e) {
    print('  ❌ live-score istisna (exception) hatası: $e');
  }

  // Yöntem B: bulletinType=1 (canlı iddaa bülteni)
  try {
    print('  [LOG] İstek atılıyor: bulletinType=1...');
    final res = await http.get(
      Uri.parse('$_bilyonerBase/api/sportsbetting/sports/1/events?bulletinType=1'),
      headers: _bilyonerHeaders(),
    ).timeout(const Duration(seconds: 20));

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final events = _extractEvents(body);
      int added = 0;
      for (final ev in events) {
        if (ev is! Map) continue;
        final sbsId = _int(ev['id'] ?? ev['sbsEventId'] ?? ev['eventId']);
        final htn   = (ev['homeTeamName'] ?? ev['home'] ?? ev['htn'] ?? '').toString();
        final atn   = (ev['awayTeamName'] ?? ev['away'] ?? ev['atn'] ?? '').toString();
        if (sbsId == null || htn.isEmpty) continue;
        
        if (bilyonerMatches.any((m) => m['id'] == sbsId)) continue; // Duplicate kontrolü
        bilyonerMatches.add({'id': sbsId, 'home': htn, 'away': atn, 'source': 'bulletin(1)'});
        added++;
      }
      print('  ✅ bulletin(1): $added ek maç eklendi.');
    } else {
      print('  ⚠️ bulletin(1) HTTP Hata Kodu: ${res.statusCode}');
    }
  } catch (e) {
    print('  ❌ bulletin(1) istisna (exception) hatası: $e');
  }

  // Yöntem C: pre-match bülteni (bulletinType=3) — yaklaşan maçlar için
  try {
    print('  [LOG] İstek atılıyor: bulletinType=3...');
    final res = await http.get(
      Uri.parse('$_bilyonerBase/api/sportsbetting/sports/1/events?bulletinType=3'),
      headers: _bilyonerHeaders(),
    ).timeout(const Duration(seconds: 20));

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final events = _extractEvents(body);
      int added = 0;
      for (final ev in events) {
        if (ev is! Map) continue;
        final sbsId = _int(ev['id'] ?? ev['sbsEventId'] ?? ev['eventId']);
        final htn   = (ev['homeTeamName'] ?? ev['home'] ?? ev['htn'] ?? '').toString();
        final atn   = (ev['awayTeamName'] ?? ev['away'] ?? ev['atn'] ?? '').toString();
        if (sbsId == null || htn.isEmpty) continue;
        
        if (bilyonerMatches.any((m) => m['id'] == sbsId)) continue;
        bilyonerMatches.add({'id': sbsId, 'home': htn, 'away': atn, 'source': 'bulletin(3)'});
        added++;
      }
      print('  ✅ bulletin(3): $added ek maç eklendi.');
    } else {
      print('  ⚠️ bulletin(3) HTTP Hata Kodu: ${res.statusCode}');
    }
  } catch (e) {
    print('  ❌ bulletin(3) istisna (exception) hatası: $e');
  }

  if (bilyonerMatches.isEmpty) {
    print('❌ Bilyoner\'den hiç maç çekilemedi. Sonlandırılıyor.');
    exit(1);
  }
  print('  📦 Toplam Çekilen Benzersiz Bilyoner Maçı: ${bilyonerMatches.length}');

  // ── 2. Supabase'den live_matches çek ───────────────────────────
  print('\n📡 Supabase live_matches çekiliyor...');
  final liveRes = await http.get(
    Uri.parse('$_sbUrl/rest/v1/live_matches'
        '?select=fixture_id,home_team,away_team,bilyoner_id'
        '&status_short=in.(1H,2H,HT,ET,BT,P,LIVE,NS)'),
    headers: _sbHeaders(),
  ).timeout(const Duration(seconds: 15));

  if (liveRes.statusCode != 200) {
    print('❌ live_matches HTTP ${liveRes.statusCode}: ${liveRes.body}'); exit(1);
  }
  final liveList = (jsonDecode(liveRes.body) as List).cast<Map>();
  print('  ✅ Supabase: ${liveList.length} canlı/NS maç.');

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
    print('❌ future_matches HTTP ${futRes.statusCode}: ${futRes.body}'); exit(1);
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
      // future_matches -> data içindeki takımları çıkartma
      home = payload?['teams']?['home']?['name']?.toString() ?? '';
      away = payload?['teams']?['away']?['name']?.toString() ?? '';
    } catch (e) {
      print('  ⚠️ [LOG] JSON Data Parse Hatası: (fixture_id: $fid) -> $e');
    }
    futList.add({
      'fixture_id': fid,
      'home': home,
      'away': away,
      'bilyoner_id': row['bilyoner_id'],
    });
  }
  print('  ✅ Supabase: ${futList.length} gelecek maç.');

  // ── 4. Eşleştir ve yaz ────────────────────────────────────────
  print('\n⚙️ Eşleştirme Algoritması Başlıyor...');
  int liveMatched = 0, futMatched = 0, skipped = 0;

  for (final bm in bilyonerMatches) {
    final bid  = bm['id'] as int;
    final bHome = _norm(bm['home'].toString());
    final bAway = _norm(bm['away'].toString());

    // 1. Önce live_matches içinde eşleşme ara
    Map? bestLive; double bestLiveScore = 0;
    for (final sb in liveList) {
      if (_int(sb['bilyoner_id']) == bid) { bestLive = sb; bestLiveScore = 1.0; break; }
      if (_int(sb['bilyoner_id']) != null) continue; // başka ID atanmışsa atla

      final hs = _sim(bHome, _norm(sb['home_team']?.toString() ?? ''));
      final as_ = _sim(bAway, _norm(sb['away_team']?.toString() ?? ''));
      if (hs < 0.45 || as_ < 0.45) continue;
      final s = (hs + as_) / 2;
      if (s > bestLiveScore) { bestLiveScore = s; bestLive = sb; }
    }

    if (bestLive != null && bestLiveScore >= 0.55) {
      final fid = _int(bestLive['fixture_id'])!;
      if (_int(bestLive['bilyoner_id']) != bid) {
        print('  🔗 [LIVE PATCH] Bilyoner:$bid ↔ Supabase:$fid (Skor: ${bestLiveScore.toStringAsFixed(2)}) | ${bm["home"]} vs ${bm["away"]}');
        await _patch('live_matches', fid, {'bilyoner_id': bid});
      }
      liveMatched++;
      continue; // Live'da bulduysak future'a bakmaya gerek yok
    }

    // 2. future_matches içinde eşleşme ara (Live'da bulunamadıysa)
    Map<String, dynamic>? bestFut; double bestFutScore = 0;
    for (final fb in futList) {
      if (_int(fb['bilyoner_id']) == bid) { bestFut = fb; bestFutScore = 1.0; break; }
      if (_int(fb['bilyoner_id']) != null) continue; // Başka id yazılmış, geç.

      final hs  = _sim(bHome, _norm(fb['home'].toString()));
      final as_ = _sim(bAway, _norm(fb['away'].toString()));
      
      if (hs < 0.45 || as_ < 0.45) continue;
      final s = (hs + as_) / 2;
      if (s > bestFutScore) { bestFutScore = s; bestFut = fb; }
    }

    if (bestFut != null && bestFutScore >= 0.55) {
      final fid = _int(bestFut['fixture_id'])!;
      if (_int(bestFut['bilyoner_id']) != bid) {
        print('  🔗 [FUTURE PATCH] Bilyoner:$bid ↔ Supabase:$fid (Skor: ${bestFutScore.toStringAsFixed(2)}) | ${bm["home"]} vs ${bm["away"]}');
        await _patch('future_matches', fid, {'bilyoner_id': bid});
      }
      futMatched++;
    } else {
      // Sadece eşleşmeyenler için debug log yazılır, çok gürültü yapmaması için yorum satırında bırakıldı, gerekirse açılabilir.
      // print('  ⚠️ Eşleşme yok: ${bm["home"]} vs ${bm["away"]} (bid=$bid, kaynak=${bm["source"]})');
      skipped++;
    }
  }

  print('\n══════════════════════════════════════');
  print('  ✅ Live tablosu eşleşti  : $liveMatched');
  print('  ✅ Future tablosu eşleşti: $futMatched');
  print('  ⚠️ Eşleşmedi             : $skipped');
  print('  📦 Toplam Bilyoner Maçı  : ${bilyonerMatches.length}');
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
      print('    ❌ $table patch hatası: ${res.statusCode} ${res.body}');
    }
  } catch (e) {
    print('    ❌ $table patch exception: $e');
  }
}

// ── Güvenli JSON Ayrıştırıcı ───────────────────────────────────
List _extractEvents(dynamic body) {
  if (body is List) return body;
  if (body is Map) {
    if (body['events'] is List) return body['events'];
    if (body['data'] is List) return body['data'];
    if (body['data'] is Map && body['data']['events'] is List) return body['data']['events'];
  }
  return [];
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

// ── Yardımcılar ve sync_fixtures(3) tabanlı Normalizasyon ──────
int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString());
}

String _norm(String name) {
  var s = name.toLowerCase().trim();
  if (_nicknames.containsKey(s)) s = _nicknames[s]!;
  
  // Basit harf ve boşluk karakteri çevirisi
  s = s
      .replaceAll('ş', 's').replaceAll('ğ', 'g').replaceAll('ü', 'u')
      .replaceAll('ö', 'o').replaceAll('ç', 'c').replaceAll('ı', 'i')
      .replaceAll(RegExp(r'[éèêë]'), 'e').replaceAll(RegExp(r'[áàâãäå]'), 'a')
      .replaceAll(RegExp(r'[óòôõø]'), 'o').replaceAll(RegExp(r'[úùûů]'), 'u')
      .replaceAll(RegExp(r'[íìî]'), 'i').replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[ćč]'), 'c').replaceAll('ž', 'z')
      .replaceAll('š', 's').replaceAll('ý', 'y').replaceAll('ř', 'r');
  
  s = s.replaceAll(RegExp(r"[.\-_/'\\()]"), ' ');
  
  // İngilizce eşleşmeleri iyileştirmek için çevirmen kullanımı (_wordTrToEn)
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
