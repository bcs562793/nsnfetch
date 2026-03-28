// elapsed_sync.dart
// GitHub Actions'dan çalışır — her 1 dakikada bir
// Canlı maçların elapsed_time'ını Bilyoner live-score HTTP'den çekip Supabase'e yazar
// Bilyoner'a Koyeb'den erişilemiyor ama GitHub Actions'dan erişiliyor

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

final _sbUrl = Platform.environment['SUPABASE_URL'] ?? '';
final _sbKey = Platform.environment['SUPABASE_KEY'] ?? '';

const _bilyonerBase           = 'https://www.bilyoner.com';
const _bilyonerPlatformToken  = '40CAB7292CD83F7EE0631FC35A0AFC75';
const _bilyonerDeviceId       = 'C1A34687-8F75-47E8-9FF9-1D231F05782E';
const _bilyonerAppVersion     = '3.95.2';
const _bilyonerChromeVersion  = '146';
const _bilyonerBrowserVersion = 'Chrome / v146.0.0.0';

Map<String, String> _bilyonerHeaders() => {
  'accept':                   'application/json, text/plain, */*',
  'accept-language':          'tr',
  'accept-encoding':          'gzip, deflate, br, zstd',
  'cache-control':            'no-cache',
  'pragma':                   'no-cache',
  'referer':                  '$_bilyonerBase/canli-iddaa',
  'sec-ch-ua':                '"Chromium";v="$_bilyonerChromeVersion", "Not-A.Brand";v="24", "Google Chrome";v="$_bilyonerChromeVersion"',
  'sec-ch-ua-mobile':         '?0',
  'sec-ch-ua-platform':       '"macOS"',
  'sec-fetch-dest':           'empty',
  'sec-fetch-mode':           'cors',
  'sec-fetch-site':           'same-origin',
  'user-agent':               'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$_bilyonerChromeVersion.0.0.0 Safari/537.36',
  'platform-token':           _bilyonerPlatformToken,
  'x-client-app-version':     _bilyonerAppVersion,
  'x-client-browser-version': _bilyonerBrowserVersion,
  'x-client-channel':         'WEB',
  'x-device-id':              _bilyonerDeviceId,
};

Map<String, String> _sbHeaders() => {
  'apikey':        _sbKey,
  'Authorization': 'Bearer $_sbKey',
  'Content-Type':  'application/json',
  'Prefer':        'return=minimal',
};

const _liveStatuses = ['1H', '2H', 'ET', 'LIVE'];
const int _chunkSize = 50;

/// Bilyoner live-score endpoint'inden elapsed çek
/// "33'" → 33, "45+2'" → 45
int? _parseTime(String timeRaw) {
  if (timeRaw.isEmpty || timeRaw == '-') return null;
  final cleaned = timeRaw.replaceAll("'", '').trim();
  final base    = cleaned.split('+').first.trim();
  return int.tryParse(base);
}

/// Sabit elapsed değerler (HTTP'ye gerek yok)
int? _fixedElapsed(String status) => switch (status) {
  'HT' => 45,
  'BT' => 105,
  'P'  => 120,
  _    => null,
};

Future<void> main() async {
  print('⏱  elapsed_sync başlıyor — ${DateTime.now().toIso8601String()}');

  if (_sbUrl.isEmpty || _sbKey.isEmpty) {
    print('❌ SUPABASE env eksik'); exit(1);
  }

  // 1) Canlı maçları Supabase'den çek
  final sbRes = await http.get(
    Uri.parse('$_sbUrl/rest/v1/live_matches'
        '?select=fixture_id,status_short,raw_data'
        '&status_short=in.(1H,2H,HT,ET,BT,P,LIVE)'),
    headers: _sbHeaders(),
  ).timeout(const Duration(seconds: 15));

  if (sbRes.statusCode != 200) {
    print('❌ Supabase HTTP ${sbRes.statusCode}'); exit(1);
  }

  final rows = (jsonDecode(sbRes.body) as List).cast<Map>();
  print('📋 ${rows.length} canlı maç bulundu');
  if (rows.isEmpty) { print('✅ İşlenecek maç yok'); exit(0); }

  // 2) Sabit elapsed olanları ayır, HTTP gerektirenleri topla
  final fixedUpdates  = <int, int>{};   // fid → elapsed
  final needHttpFids  = <int>[];        // Bilyoner HTTP'den çekilecekler

  for (final row in rows) {
    final fid    = row['fixture_id'] as int;
    final status = row['status_short'] as String? ?? '';
    final fixed  = _fixedElapsed(status);
    if (fixed != null) {
      fixedUpdates[fid] = fixed;
    } else if (_liveStatuses.contains(status)) {
      needHttpFids.add(fid);
    }
  }

  print('📌 Sabit elapsed: ${fixedUpdates.length} maç (HT/BT/P)');
  print('🌐 HTTP gerekli: ${needHttpFids.length} maç');

  // 3) Bilyoner live-score HTTP — chunk'lar halinde çek
  final httpElapsed = <int, int>{}; // fid → elapsed

  for (int i = 0; i < needHttpFids.length; i += _chunkSize) {
    final chunk = needHttpFids.sublist(
      i, (i + _chunkSize) > needHttpFids.length ? needHttpFids.length : i + _chunkSize,
    );
    final eventListParam = '1:${chunk.join(';')}';
    final uri = Uri.parse(
      '$_bilyonerBase/api/mobile/live-score/event/v2/sport-list'
      '?eventList=$eventListParam',
    );

    try {
      final res = await http
          .get(uri, headers: _bilyonerHeaders())
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        print('⚠️ Bilyoner HTTP ${res.statusCode} (chunk $i)');
        continue;
      }

      final body   = jsonDecode(res.body) as Map<String, dynamic>;
      final events = body['events'] as List? ?? [];

      for (final ev in events) {
        if (ev is! Map) continue;
        final fid     = _int(ev['sbsEventId']); if (fid == null) continue;
        final cs      = ev['currentScore'] as Map? ?? {};
        final timeRaw = cs['time'] as String? ?? '';
        final elapsed = _parseTime(timeRaw);
        if (elapsed != null && elapsed > 0) {
          httpElapsed[fid] = elapsed;
          print('   ✅ fid=$fid time="$timeRaw" → $elapsed\'');
        } else {
          print('   ⚠️ fid=$fid time="$timeRaw" → parse edilemedi');
        }
      }

      // chunk'lar arası küçük bekleme — rate-limit önlemi
      if (i + _chunkSize < needHttpFids.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      print('⚠️ Bilyoner chunk hatası (chunk $i): $e');
    }
  }

  // 4) Tüm güncellemeleri Supabase'e yaz
  final allUpdates = <int, int>{...fixedUpdates, ...httpElapsed};
  print('\n📝 ${allUpdates.length} maç güncelleniyor...');

  // raw_data map'i hazırla: fid → mevcut raw_data
  final rawDataMap = <int, Map<String, dynamic>>{};
  for (final row in rows) {
    final fid = row['fixture_id'] as int;
    try {
      rawDataMap[fid] = Map<String, dynamic>.from(
        jsonDecode(row['raw_data'] as String? ?? '{}') as Map,
      );
    } catch (_) {}
  }

  int ok = 0, err = 0;
  for (final entry in allUpdates.entries) {
    final fid     = entry.key;
    final elapsed = entry.value;

    // raw_data içindeki elapsed'ı da güncelle
    Map<String, dynamic>? updatedRaw;
    final raw = rawDataMap[fid];
    if (raw != null) {
      try {
        final fixtureStatus = (raw['fixture'] as Map?)?['status'] as Map?;
        if (fixtureStatus != null) {
          (raw['fixture'] as Map)['status'] = {
            ...fixtureStatus,
            'elapsed': elapsed,
          };
          updatedRaw = raw;
        }
      } catch (_) {}
    }

    try {
      final patchData = <String, dynamic>{
        'elapsed_time': elapsed,
        'updated_at':   DateTime.now().toIso8601String(),
        if (updatedRaw != null) 'raw_data': jsonEncode(updatedRaw),
      };

      final res = await http.patch(
        Uri.parse('$_sbUrl/rest/v1/live_matches?fixture_id=eq.$fid'),
        headers: _sbHeaders(),
        body: jsonEncode(patchData),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode < 300) {
        ok++;
      } else {
        print('   ❌ fid=$fid: ${res.statusCode}');
        err++;
      }
    } catch (e) {
      print('   ❌ fid=$fid: $e');
      err++;
    }
  }

  print('\n═══════════════════════════════');
  print('  ✅ Güncellendi : $ok maç');
  if (err > 0) print('  ❌ Hatalı     : $err maç');
  print('  ⏱  HTTP elapsed: ${httpElapsed.length} maç');
  print('  📌 Sabit elapsed: ${fixedUpdates.length} maç');
  print('═══════════════════════════════');

  exit(err > 0 ? 1 : 0);
}

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString());
}
