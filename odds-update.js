/**
 * SCOREPOP — odds-update.js  (v5)
 * Nesine HTML'den tespit edilen TÜM MTID'ler:
 *
 * ── MAÇ SONUCU ──────────────────────────────
 * MTID=1   OCA=3  → Maç Sonucu 1X2
 * MTID=3   OCA=3  → Çifte Şans             ⚠️ önceden 2 diyorduk, YANLIŞ
 * MTID=268 OCA=3  → Handikaplı Maç Sonucu  (SOV=çizgi, örn -1,-2,+1)
 * MTID=5   OCA=9  → İY / Maç Sonucu
 * MTID=342 OCA=6  → MS + 1.5 Alt/Üst
 * MTID=343 OCA=6  → MS + 2.5 Alt/Üst
 * MTID=272 OCA=6  → MS + X.5 Alt/Üst       (SOV=3.5 veya 4.5)
 * MTID=414 OCA=6  → MS + Karşılıklı Gol
 * MTID=588 OCA=7  → Hangi Takım Kaç Farkla Kazanır
 *
 * ── YARI SONUCU ─────────────────────────────
 * MTID=7   OCA=3  → 1. Yarı Sonucu
 * MTID=8   OCA=3  → 1. Yarı Çifte Şans     ⚠️ önceden ht_1x2 diyorduk, YANLIŞ
 * MTID=459 OCA=6  → 1Y Sonucu + 1Y 1.5 Alt/Üst
 * MTID=416 OCA=6  → 1Y Sonucu + 1Y Karşılıklı Gol
 * MTID=9   OCA=3  → 2. Yarı Sonucu
 * MTID=591 OCA=2  → Ev Sahibi Her İki Yarıyı Kazanır
 * MTID=592 OCA=2  → Deplasman Her İki Yarıyı Kazanır
 *
 * ── YARI ALT/ÜST ────────────────────────────
 * MTID=209 OCA=2  → 1Y 0.5 Gol Alt/Üst
 * MTID=14  OCA=2  → 1Y 1.5 Gol Alt/Üst    ⚠️ önceden Maç Alt/Üst diyorduk, YANLIŞ
 * MTID=15  OCA=2  → 1Y 2.5 Gol Alt/Üst
 * MTID=528 OCA=2  → İki Yarı da 1.5 Alt
 * MTID=529 OCA=2  → İki Yarı da 1.5 Üst
 *
 * ── MAÇ SONUCU ALT/ÜST ──────────────────────
 * MTID=11  OCA=2  → 1.5 Gol Alt/Üst
 * MTID=12  OCA=2  → 2.5 Gol Alt/Üst
 * MTID=13  OCA=2  → 3.5 Gol Alt/Üst
 * MTID=155 OCA=2  → 4.5 / 5.5 Gol Alt/Üst (SOV ile ayırt)
 * MTID=446 OCA=4  → 2.5 Alt/Üst + Karşılıklı Gol
 *
 * ── GOL ─────────────────────────────────────
 * MTID=38  OCA=2  → Karşılıklı Gol          ⚠️ önceden 25/49 diyorduk
 * MTID=452 OCA=2  → 1Y Karşılıklı Gol
 * MTID=599 OCA=2  → 2Y Karşılıklı Gol
 * MTID=801 OCA=4  → 1Y/2Y Karşılıklı Gol
 * MTID=291 OCA=3  → İlk Golü Kim Atar
 * MTID=295 OCA=2  → Ev Sahibi İki Yarıda da Gol
 * MTID=296 OCA=2  → Deplasman İki Yarıda da Gol
 * MTID=586 OCA=3  → Ev Sahibi Hangi Yarıda Daha Çok Gol
 * MTID=587 OCA=3  → Deplasman Hangi Yarıda Daha Çok Gol
 *
 * ── TARAF ALT/ÜST ───────────────────────────
 * MTID=212 OCA=2  → Ev Sahibi 0.5 Alt/Üst
 * MTID=20  OCA=2  → Ev Sahibi 1.5 Alt/Üst
 * MTID=326 OCA=2  → Ev Sahibi 2.5 Alt/Üst
 * MTID=256 OCA=2  → Deplasman 0.5 Alt/Üst
 * MTID=29  OCA=2  → Deplasman 1.5 Alt/Üst
 * MTID=328 OCA=2  → Deplasman 2.5 Alt/Üst
 * MTID=455 OCA=2  → Ev Sahibi 1Y 0.5 Alt/Üst
 * MTID=457 OCA=2  → Deplasman 1Y 0.5 Alt/Üst
 *
 * ── TOPLAM GOL ──────────────────────────────
 * MTID=43  OCA=4  → Toplam Gol Aralığı
 * MTID=48  OCA=3  → En Çok Gol Olacak Yarı
 * MTID=49  OCA=2  → Tek/Çift                ⚠️ önceden KG diyorduk, YANLIŞ
 * MTID=450 OCA=2  → 1Y Tek/Çift
 */
'use strict';

const https  = require('https');
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_KEY;
if (!SUPABASE_URL || !SUPABASE_KEY) { console.error('[Odds] SUPABASE_URL ve SUPABASE_KEY gerekli'); process.exit(1); }
const sb = createClient(SUPABASE_URL, SUPABASE_KEY);

/* ── HTTP GET ───────────────────────────────── */
function fetchJSON(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, {
      headers: {
        'Accept': 'application/json',
        'Accept-Encoding': 'identity',
        'Referer': 'https://www.nesine.com/',
        'Origin': 'https://www.nesine.com',
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36',
      }
    }, res => {
      let buf = '';
      res.on('data', d => buf += d);
      res.on('end', () => {
        try { resolve(JSON.parse(buf)); }
        catch (e) { reject(new Error(`JSON parse: ${e.message}`)); }
      });
    });
    req.on('error', reject);
    req.setTimeout(30000, () => { req.destroy(); reject(new Error('Timeout')); });
  });
}

/* ── Normalize + token benzerliği ──────────── */
function norm(s) {
  return (s || '')
    .toLowerCase()
    .replace(/ğ/g,'g').replace(/ü/g,'u').replace(/ş/g,'s')
    .replace(/ı/g,'i').replace(/ö/g,'o').replace(/ç/g,'c')
    .replace(/[^a-z0-9]/g,' ')
    .replace(/\s+/g,' ').trim();
}

function tokenSim(a, b) {
  const ta = new Set(norm(a).split(' ').filter(x => x.length > 1));
  const tb = new Set(norm(b).split(' ').filter(x => x.length > 1));
  if (!ta.size || !tb.size) return 0;
  let hit = 0;
  for (const t of ta) {
    if (tb.has(t)) { hit++; continue; }
    for (const u of tb) {
      if (t.startsWith(u) || u.startsWith(t)) { hit += 0.7; break; }
    }
  }
  return hit / Math.max(ta.size, tb.size);
}

/* ── Market parse ───────────────────────────── */
function parseMarkets(maArr, matchName) {
  const markets = {};
  if (!Array.isArray(maArr)) return markets;

  for (const m of maArr) {
    const mtid = m.MTID;
    const sov  = parseFloat(m.SOV ?? 0);
    const oca  = m.OCA || [];
    const get  = (n) => { const o = oca.find(x => x.N === n); return o ? +o.O : 0; };

    /* ── MAÇ SONUCU ─────────────────────────── */
    if (mtid === 1 && oca.length === 3) {
      markets['1x2'] = { home: get(1), draw: get(2), away: get(3) };
    }
    if (mtid === 3 && oca.length === 3) {
      markets['dc'] = { '1x': get(1), '12': get(2), 'x2': get(3) };
    }
    if (mtid === 268 && oca.length === 3) {
      const sign = sov >= 0
        ? `p${String(sov).replace('.','_')}`
        : `m${String(Math.abs(sov)).replace('.','_')}`;
      markets[`ah_${sign}`] = { home: get(1), draw: get(2), away: get(3), line: sov };
    }
    if (mtid === 5 && oca.length === 9) {
      markets['ht_ft'] = {
        '1/1': get(1), '1/X': get(2), '1/2': get(3),
        'X/1': get(4), 'X/X': get(5), 'X/2': get(6),
        '2/1': get(7), '2/X': get(8), '2/2': get(9),
      };
    }
    if (mtid === 342 && oca.length === 6) {
      markets['ms_ou15'] = {
        'h_u': get(1), 'x_u': get(2), 'a_u': get(3),
        'h_o': get(4), 'x_o': get(5), 'a_o': get(6),
      };
    }
    if (mtid === 343 && oca.length === 6) {
      markets['ms_ou25'] = {
        'h_u': get(1), 'x_u': get(2), 'a_u': get(3),
        'h_o': get(4), 'x_o': get(5), 'a_o': get(6),
      };
    }
    if (mtid === 272 && oca.length === 6) {
      const key = Math.abs(sov - 3.5) < 0.01 ? 'ms_ou35'
                : Math.abs(sov - 4.5) < 0.01 ? 'ms_ou45'
                : `ms_ou_${String(sov).replace('.','_')}`;
      markets[key] = {
        'h_u': get(1), 'x_u': get(2), 'a_u': get(3),
        'h_o': get(4), 'x_o': get(5), 'a_o': get(6),
      };
    }
    if (mtid === 414 && oca.length === 6) {
      markets['ms_kg'] = {
        'h_y': get(1), 'x_y': get(3), 'a_y': get(5),
        'h_n': get(2), 'x_n': get(4), 'a_n': get(6),
      };
    }
    if (mtid === 588 && oca.length >= 6) {
      markets['win_margin'] = {
        'h3p': get(1), 'h2': get(2), 'h1': get(3),
        'a1':  get(4), 'a2': get(5), 'a3p': get(6),
        'draw': get(7),
      };
    }

    /* ── YARI SONUCU ────────────────────────── */
    if (mtid === 7 && oca.length === 3) {
      markets['ht_1x2'] = { home: get(1), draw: get(2), away: get(3) };
    }
    if (mtid === 8 && oca.length === 3) {
      markets['ht_dc'] = { '1x': get(1), '12': get(2), 'x2': get(3) };
    }
    if (mtid === 459 && oca.length === 6) {
      markets['ht_ms_ou15'] = {
        'h_u': get(1), 'x_u': get(2), 'a_u': get(3),
        'h_o': get(4), 'x_o': get(5), 'a_o': get(6),
      };
    }
    if (mtid === 416 && oca.length === 6) {
      markets['ht_ms_kg'] = {
        'h_y': get(1), 'x_y': get(3), 'a_y': get(5),
        'h_n': get(2), 'x_n': get(4), 'a_n': get(6),
      };
    }
    if (mtid === 9 && oca.length === 3) {
      markets['2h_1x2'] = { home: get(1), draw: get(2), away: get(3) };
    }
    if (mtid === 591 && oca.length >= 1) {
      markets['home_win_both'] = { yes: get(1), no: get(2) };
    }
    if (mtid === 592 && oca.length >= 1) {
      markets['away_win_both'] = { yes: get(1), no: get(2) };
    }

    /* ── YARI ALT/ÜST ───────────────────────── */
    if (mtid === 209 && oca.length === 2) {
      markets['ht_ou05'] = { under: get(1), over: get(2) };
    }
    if (mtid === 14 && oca.length === 2) {
      markets['ht_ou15'] = { under: get(1), over: get(2) };
    }
    if (mtid === 15 && oca.length === 2) {
      markets['ht_ou25'] = { under: get(1), over: get(2) };
    }
    if (mtid === 528 && oca.length === 2) {
      markets['both_half_u15'] = { yes: get(1), no: get(2) };
    }
    if (mtid === 529 && oca.length === 2) {
      markets['both_half_o15'] = { yes: get(1), no: get(2) };
    }

    /* ── MAÇ SONUCU ALT/ÜST ─────────────────── */
    if (mtid === 11 && oca.length === 2) {
      markets['ou15'] = { under: get(1), over: get(2) };
    }
    if (mtid === 12 && oca.length === 2) {
      markets['ou25'] = { under: get(1), over: get(2) };
    }
    if (mtid === 13 && oca.length === 2) {
      markets['ou35'] = { under: get(1), over: get(2) };
    }
    if (mtid === 155 && oca.length === 2) {
      if (Math.abs(sov - 4.5) < 0.01) {
        markets['ou45'] = { under: get(1), over: get(2) };
      } else if (Math.abs(sov - 5.5) < 0.01) {
        markets['ou55'] = { under: get(1), over: get(2) };
      } else {
        markets[`ou_${String(sov).replace('.','_')}`] = { under: get(1), over: get(2), line: sov };
      }
    }
    if (mtid === 446 && oca.length === 4) {
      markets['ou25_kg'] = {
        'u_y': get(1), 'o_y': get(2),
        'u_n': get(3), 'o_n': get(4),
      };
    }

    /* ── GOL ────────────────────────────────── */
    if (mtid === 38 && oca.length === 2) {
      markets['btts'] = { yes: get(1), no: get(2) };
    }
    if (mtid === 452 && oca.length === 2) {
      markets['ht_btts'] = { yes: get(1), no: get(2) };
    }
    if (mtid === 599 && oca.length === 2) {
      markets['2h_btts'] = { yes: get(1), no: get(2) };
    }
    if (mtid === 801 && oca.length === 4) {
      markets['halves_btts'] = {
        'yy': get(3), 'yn': get(2),
        'ny': get(4), 'nn': get(1),
      };
    }
    if (mtid === 291 && oca.length === 3) {
      markets['first_goal'] = { home: get(1), none: get(2), away: get(3) };
    }
    if (mtid === 295 && oca.length >= 1) {
      markets['home_score_both'] = { yes: get(1), no: get(2) };
    }
    if (mtid === 296 && oca.length >= 1) {
      markets['away_score_both'] = { yes: get(1), no: get(2) };
    }
    if (mtid === 586 && oca.length === 3) {
      markets['home_more_goals_half'] = { first: get(1), equal: get(2), second: get(3) };
    }
    if (mtid === 587 && oca.length === 3) {
      markets['away_more_goals_half'] = { first: get(1), equal: get(2), second: get(3) };
    }

    /* ── TARAF ALT/ÜST ──────────────────────── */
    if (mtid === 212 && oca.length === 2) {
      markets['h_ou05'] = { under: get(1), over: get(2) };
    }
    if (mtid === 20 && oca.length === 2) {
      markets['h_ou15'] = { under: get(1), over: get(2) };
    }
    if (mtid === 326 && oca.length === 2) {
      markets['h_ou25'] = { under: get(1), over: get(2) };
    }
    if (mtid === 256 && oca.length === 2) {
      markets['a_ou05'] = { under: get(1), over: get(2) };
    }
    if (mtid === 29 && oca.length === 2) {
      markets['a_ou15'] = { under: get(1), over: get(2) };
    }
    if (mtid === 328 && oca.length === 2) {
      markets['a_ou25'] = { under: get(1), over: get(2) };
    }
    if (mtid === 455 && oca.length === 2) {
      markets['h_ht_ou05'] = { under: get(1), over: get(2) };
    }
    if (mtid === 457 && oca.length === 2) {
      markets['a_ht_ou05'] = { under: get(1), over: get(2) };
    }

    /* ── TOPLAM GOL ─────────────────────────── */
    if (mtid === 43 && oca.length === 4) {
      markets['goal_range'] = {
        '0_1': get(1), '2_3': get(2), '4_5': get(3), '6p': get(4),
      };
    }
    if (mtid === 48 && oca.length === 3) {
      markets['more_goals_half'] = { first: get(1), equal: get(2), second: get(3) };
    }
    if (mtid === 49 && oca.length === 2) {
      markets['odd_even'] = { odd: get(1), even: get(2) };
    }
    if (mtid === 450 && oca.length === 2) {
      markets['ht_odd_even'] = { odd: get(1), even: get(2) };
    }
  }

  return markets;
}

/* ── Ana ────────────────────────────────────── */
async function run() {
  /* 1. Supabase'den future_matches çek */
  console.log('[Odds] Supabase maçları çekiliyor...');
  const { data: rawFixtures, error: fErr } = await sb
    .from('future_matches')
    .select('fixture_id, date, data')
    .limit(500);

  if (fErr) { console.error('[Odds] Supabase hata:', fErr.message); process.exit(1); }

  const allFixtures = (rawFixtures || []).map(row => {
    const d = row.data || {};
    return {
      fixture_id: row.fixture_id,
      date: row.date,
      home_team: d.teams?.home?.name || '',
      away_team: d.teams?.away?.name || '',
    };
  }).filter(f => f.home_team && f.away_team);

  console.log(`[Odds] ${allFixtures.length} maç bulundu`);
  if (!allFixtures.length) { console.log('[Odds] Maç yok.'); return; }

  /* 2. Nesine bülten indir */
  console.log('[Odds] Nesine bülten indiriliyor...');
  let nesineData;
  try { nesineData = await fetchJSON('https://cdnbulten.nesine.com/api/bulten/getprebultenfull'); }
  catch (e) { console.error('[Odds] Nesine CDN hatası:', e.message); process.exit(1); }

  /* 3. Sadece futbol (TYPE=1) etkinliklerini al */
  const events = (nesineData?.sg?.EA || []).filter(e => e.TYPE === 1);
  console.log(`[Odds] Nesine'de ${events.length} futbol etkinliği`);

  /* 4. Eşleştir */
  const THRESHOLD = 0.45;
  const upserts   = [];

  // Debug için eşleşmeyen maçları topla
  const debugMissed = [];

  for (const fix of allFixtures) {
    let best = null, bestScore = THRESHOLD - 0.01;

    // Her maç için tüm adayların skorunu hesapla (debug için)
    const allCandidates = events.map(ev => ({
      hn:    ev.HN,
      an:    ev.AN,
      hs:    tokenSim(fix.home_team, ev.HN),
      as_:   tokenSim(fix.away_team, ev.AN),
    }));

    for (const c of allCandidates) {
      if (c.hs < 0.35 || c.as_ < 0.35) continue;
      const score = (c.hs + c.as_) / 2;
      if (score > bestScore) { bestScore = score; best = events.find(e => e.HN === c.hn && e.AN === c.an); }
    }

    if (best) {
      const markets = parseMarkets(best.MA, null); // MTID logunu kaldırdık, sadece debug'da gösteriyoruz

      if (Object.keys(markets).length > 0) {
        upserts.push({
          fixture_id: fix.fixture_id,
          odds_data: {
            source: 'İddaa / Nesine',
            markets,
            nesine_name: `${best.HN} - ${best.AN}`,
          },
          updated_at: new Date().toISOString(),
        });
        console.log(`  ✓ ${fix.home_team} vs ${fix.away_team}  →  ${best.HN} vs ${best.AN} (${bestScore.toFixed(2)}) [${Object.keys(markets).join(',')}]`);
      } else {
        console.log(`  ~ ${fix.home_team} vs ${fix.away_team}  →  eşleşti ama market yok`);
      }
    } else {
      console.log(`  ✗ ${fix.home_team} vs ${fix.away_team}  →  eşleşme bulunamadı`);

      // En yakın 3 adayı bul (eşik altında olanlar dahil)
      const top3 = allCandidates
        .filter(c => c.hs > 0.15 || c.as_ > 0.15)
        .sort((a, b) => (b.hs + b.as_) - (a.hs + a.as_))
        .slice(0, 3);

      debugMissed.push({ fix, top3 });
    }
  }

  if (!upserts.length) { console.log('[Odds] Upsert edilecek veri yok.'); }
  else {
    /* 5. Supabase upsert */
    console.log(`\n[Odds] ${upserts.length} kayıt yazılıyor...`);
    const { error: upErr } = await sb
      .from('match_odds')
      .upsert(upserts, { onConflict: 'fixture_id' });

    if (upErr) { console.error('[Odds] Upsert hatası:', upErr.message); process.exit(1); }
    console.log(`[Odds] ✅ ${upserts.length} maç oranı güncellendi.`);
  }

  /* ═══════════════════════════════════════════
   * DEBUG — EŞLEŞMEYENLERİN RAPORU (en altta)
   * ═══════════════════════════════════════════ */
  if (debugMissed.length === 0) {
    console.log('\n[DEBUG] ✅ Tüm maçlar eşleşti, kaçan yok.');
    return;
  }

  console.log('\n' + '═'.repeat(60));
  console.log(`[DEBUG] EŞLEŞMEYEN MAÇLAR — ${debugMissed.length} adet`);
  console.log('═'.repeat(60));

  for (const { fix, top3 } of debugMissed) {
    console.log(`\n❌  fixture_id=${fix.fixture_id}  tarih=${fix.date ?? '-'}`);
    console.log(`    DB  : "${fix.home_team}"  vs  "${fix.away_team}"`);

    if (top3.length === 0) {
      console.log('    → Nesine\'de hiç benzer takım bulunamadı (0.15 altı)');
    } else {
      console.log('    En yakın Nesine adayları:');
      for (const c of top3) {
        const avg = ((c.hs + c.as_) / 2).toFixed(2);
        const bar = avg >= 0.40 ? '⚠️ EŞIĞE YAKIN' : '';
        console.log(`      ${avg}  "${c.hn}" vs "${c.an}"  (ev=${c.hs.toFixed(2)} dep=${c.as_.toFixed(2)}) ${bar}`);
      }
    }
  }

  console.log('\n' + '─'.repeat(60));
  console.log('[DEBUG] İpuçları:');
  console.log('  • avg >= 0.40 ama eşleşmiyorsa → THRESHOLD\'u 0.40\'a düşür');
  console.log('  • Nesine adayı çok farklıysa   → TEAM_ALIASES tablosu ekle');
  console.log('  • Aday hiç yoksa               → takım ismi tamamen farklı');
  console.log('─'.repeat(60) + '\n');
}

run().catch(e => { console.error('[Odds] Beklenmedik hata:', e); process.exit(1); });
