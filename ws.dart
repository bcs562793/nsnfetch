import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _wsUrl = 'wss://rt.nesine.com/socket.io/'
    '?platformid=1'
    '&userAgent=Mozilla%2F5.0%20(Windows%20NT%2010.0%3B%20Win64%3B%20x64)%20'
    'AppleWebKit%2F537.36%20(KHTML%2C%20like%20Gecko)%20'
    'Chrome%2F122.0.0.0%20Safari%2F537.36'
    '&EIO=4&transport=websocket';

// ─── Bağlantı durumu ───────────────────────────────────────────────────────
enum ConnState { disconnected, connecting, connected }

class _Conn {
  final String name;
  ConnState state = ConnState.disconnected;
  WebSocketChannel? ws;
  Timer? ping;

  // İstatistik
  int totalEvents     = 0;
  int totalSessions   = 0;
  DateTime? connectedAt;
  final List<double> sessionDurations = [];   // her oturumun süresi (sn)
  final List<double> gapDurations     = [];   // her kopma arasındaki boşluk (sn)
  DateTime? lastDropAt;

  // Rakip bağlantı kopukken bu bağlantı kaç event aldı (= rakibin kaybı)
  int eventsWhileOtherDown = 0;

  _Conn(this.name);
}

final _a = _Conn('A');
final _b = _Conn('B');

void main() async {
  print('╔══════════════════════════════════════════════════╗');
  print('║  🔬 Dual-WS Diagnostic  (A vs B paralel bağlantı) ║');
  print('╚══════════════════════════════════════════════════╝');
  print('Her iki bağlantı da aynı room\'a girer.');
  print('Biri kopunca, diğeri o sırada kaç event almış → ölçülür.\n');

  // A hemen, B 2 saniye sonra bağlanır
  unawaited(_runLoop(_a, _b));
  await Future.delayed(const Duration(seconds: 2));
  unawaited(_runLoop(_b, _a));

  // Her 20 saniyede özet
  Timer.periodic(const Duration(seconds: 20), (_) => _printSummary());

  // Sonsuza kadar bekle
  await Completer<void>().future;
}

Future<void> _runLoop(_Conn self, _Conn other) async {
  while (true) {
    // Reconnect boşluğunu ölç
    if (self.lastDropAt != null) {
      final gap =
          DateTime.now().difference(self.lastDropAt!).inMilliseconds / 1000.0;
      self.gapDurations.add(gap);
      print('[${self.name}] 🔁 Reconnect — boşluk: ${gap.toStringAsFixed(2)}s '
            '(bu sürede B aldı: ${other.eventsWhileOtherDown} evt)');
      // sıfırla
      other.eventsWhileOtherDown = 0;
    }

    self.state = ConnState.connecting;
    self.connectedAt = DateTime.now();
    self.totalSessions++;

    try {
      await _session(self, other);
    } catch (e) {
      print('[${self.name}] ❌ $e');
    }

    // Oturum bitti
    if (self.connectedAt != null) {
      final dur =
          DateTime.now().difference(self.connectedAt!).inMilliseconds / 1000.0;
      self.sessionDurations.add(dur);
      print('[${self.name}] ⛔ Oturum #${self.totalSessions} bitti '
            '– süre: ${dur.toStringAsFixed(1)}s');
    }
    self.state = ConnState.disconnected;
    self.lastDropAt = DateTime.now();

    await Future.delayed(const Duration(milliseconds: 500));
  }
}

Future<void> _session(_Conn self, _Conn other) async {
  self.ws = IOWebSocketChannel.connect(Uri.parse(_wsUrl), headers: {
    'Origin':        'https://www.nesine.com',
    'User-Agent':    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/122.0.0.0',
    'Cache-Control': 'no-cache',
  });

  await for (final raw in self.ws!.stream) {
    _onRaw(self, other, raw.toString());
  }

  self.ping?.cancel();
  self.ws = null;
}

void _onRaw(_Conn self, _Conn other, String s) {
  if (s == '2') { self.ws?.sink.add('3'); return; }
  if (s == '3') return;

  if (s.startsWith('0')) {
    try { self.ws?.sink.add('40'); } catch (_) {}
    return;
  }

  if (s.startsWith('40')) {
    final handshake = self.connectedAt != null
        ? DateTime.now().difference(self.connectedAt!).inMilliseconds / 1000.0
        : 0.0;
    print('[${self.name}] ✅ Bağlandı (+${handshake.toStringAsFixed(2)}s)');
    self.state = ConnState.connected;
    self.ws?.sink.add('42["joinroom","LiveBets_V3"]');
    self.ping?.cancel();
    self.ping = Timer.periodic(const Duration(seconds: 20), (_) {
      try { self.ws?.sink.add('2'); } catch (_) {}
    });
    return;
  }

  if (s.startsWith('42')) _onEvent(self, other, s.substring(2));
}

void _onEvent(_Conn self, _Conn other, String payload) {
  try {
    final list = jsonDecode(payload) as List;
    if (list[0] != 'LiveBets' || list[1] is! List) return;

    int footballCount = 0;
    for (final item in list[1] as List) {
      if (item is! Map) continue;
      if ((item['sportype'] ?? '').toString().toLowerCase() == 'football') {
        footballCount++;
      }
    }
    if (footballCount == 0) return;

    self.totalEvents += footballCount;

    // Rakip bağlantı şu an kopuk → bu event'ler rakip için kaybedildi
    if (other.state != ConnState.connected) {
      self.eventsWhileOtherDown += footballCount;
    }
  } catch (_) {}
}

void _printSummary() {
  _printConn(_a, _b);
  _printConn(_b, _a);

  // Kaçırılan tahmini
  final aGapTotal = _a.gapDurations.fold(0.0, (s, v) => s + v);
  final bGapTotal = _b.gapDurations.fold(0.0, (s, v) => s + v);
  final aEvtRate  = _a.totalSessions > 0
      ? _a.totalEvents /
        (_a.sessionDurations.fold(0.0, (s, v) => s + v).clamp(1, 999999))
      : 0.0;
  final bEvtRate  = _b.totalSessions > 0
      ? _b.totalEvents /
        (_b.sessionDurations.fold(0.0, (s, v) => s + v).clamp(1, 999999))
      : 0.0;

  print('─' * 52);
  print('💀 A\'nın toplam boşta süresi: ${aGapTotal.toStringAsFixed(1)}s'
        ' → tahmini kayıp: ~${(bEvtRate * aGapTotal).toStringAsFixed(0)} evt');
  print('💀 B\'nin toplam boşta süresi: ${bGapTotal.toStringAsFixed(1)}s'
        ' → tahmini kayıp: ~${(aEvtRate * bGapTotal).toStringAsFixed(0)} evt');
  print('═' * 52);
}

void _printConn(_Conn c, _Conn other) {
  final avgSession = c.sessionDurations.isNotEmpty
      ? c.sessionDurations.reduce((a, b) => a + b) / c.sessionDurations.length
      : 0.0;
  final avgGap = c.gapDurations.isNotEmpty
      ? c.gapDurations.reduce((a, b) => a + b) / c.gapDurations.length
      : 0.0;
  print('\n[${c.name}] Durum: ${c.state.name.toUpperCase()} '
        '| Oturum: ${c.totalSessions} '
        '| Ort.süre: ${avgSession.toStringAsFixed(1)}s '
        '| Ort.gap: ${avgGap.toStringAsFixed(2)}s '
        '| Toplam evt: ${c.totalEvents}');
}
