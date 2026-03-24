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

  /* LOG */
  if (matchName) {
    console.log(`\n  [MTIDs] ${matchName}`);
    maArr.forEach(m => {
      const ocaStr = (m.OCA || []).map(o => `N${o.N}=${o.O}`).join(' | ');
      console.log(`    MTID=${m.MTID} SOV=${m.SOV ?? '-'} OCA_count=${(m.OCA||[]).length} → ${ocaStr}`);
    });
  }

  for (const m of maArr) {
    const mtid = m.MTID;
    const sov  = parseFloat(m.SOV ?? 0);
    const oca  = m.OCA || [];
    const get  = (n) => { const o = oca.find(x => x.N === n); return o ? +o.O : 0; };

    /* ── MAÇ SONUCU ─────────────────────────── */

    /* Maç Sonucu 1X2 */
    if (mtid === 1 && oca.length === 3) {
      markets['1x2'] = { home: get(1), draw: get(2), away: get(3) };
    }

    /* Çifte Şans */
    if (mtid === 3 && oca.length === 3) {
      markets['dc'] = { '1x': get(1), '12': get(2), 'x2': get(3) };
    }

    /* Handikaplı Maç Sonucu — SOV ile çizgiyi ayırt et */
    if (mtid === 268 && oca.length === 3) {
      const sign = sov >= 0
        ? `p${String(sov).replace('.','_')}`
        : `m${String(Math.abs(sov)).replace('.','_')}`;
      markets[`ah_${sign}`] = { home: get(1), draw: get(2), away: get(3), line: sov };
    }

    /* İY / Maç Sonucu */
    if (mtid === 5 && oca.length === 9) {
      markets['ht_ft'] = {
        '1/1': get(1), '1/X': get(2), '1/2': get(3),
        'X/1': get(4), 'X/X': get(5), 'X/2': get(6),
        '2/1': get(7), '2/X': get(8), '2/2': get(9),
      };
    }

    /* MS + 1.5 Alt/Üst */
    if (mtid === 342 && oca.length === 6) {
      markets['ms_ou15'] = {
        'h_u': get(1), 'x_u': get(2), 'a_u': get(3),
        'h_o': get(4), 'x_o': get(5), 'a_o': get(6),
      };
    }

    /* MS + 2.5 Alt/Üst */
    if (mtid === 343 && oca.length === 6) {
      markets['ms_ou25'] = {
        'h_u': get(1), 'x_u': get(2), 'a_u': get(3),
        'h_o': get(4), 'x_o': get(5), 'a_o': get(6),
      };
    }

    /* MS + 3.5 / 4.5 Alt/Üst — SOV ile ayırt */
    if (mtid === 272 && oca.length === 6) {
      const key = Math.abs(sov - 3.5) < 0.01 ? 'ms_ou35'
                : Math.abs(sov - 4.5) < 0.01 ? 'ms_ou45'
                : `ms_ou_${String(sov).replace('.','_')}`;
      markets[key] = {
        'h_u': get(1), 'x_u': get(2), 'a_u': get(3),
        'h_o': get(4), 'x_o': get(5), 'a_o': get(6),
      };
    }

    /* MS + Karşılıklı Gol */
    if (mtid === 414 && oca.length === 6) {
      markets['ms_kg'] = {
        'h_y': get(1), 'x_y': get(3), 'a_y': get(5),
        'h_n': get(2), 'x_n': get(4), 'a_n': get(6),
      };
    }

    /* Hangi Takım Kaç Farkla Kazanır */
    if (mtid === 588 && oca.length >= 6) {
      markets['win_margin'] = {
        'h3p': get(1), 'h2': get(2), 'h1': get(3),
        'a1':  get(4), 'a2': get(5), 'a3p': get(6),
        'draw': get(7),
      };
    }

    /* ── YARI SONUCU ────────────────────────── */

    /* 1. Yarı Sonucu */
    if (mtid === 7 && oca.length === 3) {
      markets['ht_1x2'] = { home: get(1), draw: get(2), away: get(3) };
    }

    /* 1. Yarı Çifte Şans */
    if (mtid === 8 && oca.length === 3) {
      markets['ht_dc'] = { '1x': get(1), '12': get(2), 'x2': get(3) };
    }

    /* 1Y Sonucu + 1Y 1.5 Alt/Üst */
    if (mtid === 459 && oca.length === 6) {
      markets['ht_ms_ou15'] = {
        'h_u': get(1), 'x_u': get(2), 'a_u': get(3),
        'h_o': get(4), 'x_o': get(5), 'a_o': get(6),
      };
    }

    /* 1Y Sonucu + 1Y Karşılıklı Gol */
    if (mtid === 416 && oca.length === 6) {
      markets['ht_ms_kg'] = {
        'h_y': get(1), 'x_y': get(3), 'a_y': get(5),
        'h_n': get(2), 'x_n': get(4), 'a_n': get(6),
      };
    }

    /* 2. Yarı Sonucu */
    if (mtid === 9 && oca.length === 3) {
      markets['2h_1x2'] = { home: get(1), draw: get(2), away: get(3) };
    }

    /* Ev Sahibi Her İki Yarıyı Kazanır */
    if (mtid === 591 && oca.length >= 1) {
      markets['home_win_both'] = { yes: get(1), no: get(2) };
    }

    /* Deplasman Her İki Yarıyı Kazanır */
    if (mtid === 592 && oca.length >= 1) {
      markets['away_win_both'] = { yes: get(1), no: get(2) };
    }

    /* ── YARI ALT/ÜST ───────────────────────── */

    /* 1Y 0.5 Gol Alt/Üst */
    if (mtid === 209 && oca.length === 2) {
      markets['ht_ou05'] = { under: get(1), over: get(2) };
    }

    /* 1Y 1.5 Gol Alt/Üst */
    if (mtid === 14 && oca.length === 2) {
      markets['ht_ou15'] = { under: get(1), over: get(2) };
    }

    /* 1Y 2.5 Gol Alt/Üst */
    if (mtid === 15 && oca.length === 2) {
      markets['ht_ou25'] = { under: get(1), over: get(2) };
    }

    /* İki Yarı da 1.5 Alt */
    if (mtid === 528 && oca.length === 2) {
      markets['both_half_u15'] = { yes: get(1), no: get(2) };
    }

    /* İki Yarı da 1.5 Üst */
    if (mtid === 529 && oca.length === 2) {
      markets['both_half_o15'] = { yes: get(1), no: get(2) };
    }

    /* ── MAÇ SONUCU ALT/ÜST ─────────────────── */

    /* 1.5 Gol Alt/Üst */
    if (mtid === 11 && oca.length === 2) {
      markets['ou15'] = { under: get(1), over: get(2) };
    }

    /* 2.5 Gol Alt/Üst */
    if (mtid === 12 && oca.length === 2) {
      markets['ou25'] = { under: get(1), over: get(2) };
    }

    /* 3.5 Gol Alt/Üst */
    if (mtid === 13 && oca.length === 2) {
      markets['ou35'] = { under: get(1), over: get(2) };
    }

    /* 4.5 / 5.5 Gol Alt/Üst — aynı MTID, SOV ile ayırt */
    if (mtid === 155 && oca.length === 2) {
      if (Math.abs(sov - 4.5) < 0.01) {
        markets['ou45'] = { under: get(1), over: get(2) };
      } else if (Math.abs(sov - 5.5) < 0.01) {
        markets['ou55'] = { under: get(1), over: get(2) };
      } else {
        markets[`ou_${String(sov).replace('.','_')}`] = { under: get(1), over: get(2), line: sov };
      }
    }

    /* 2.5 Alt/Üst + Karşılıklı Gol */
    if (mtid === 446 && oca.length === 4) {
      markets['ou25_kg'] = {
        'u_y': get(1), 'o_y': get(2),
        'u_n': get(3), 'o_n': get(4),
      };
    }

    /* ── GOL ────────────────────────────────── */

    /* Karşılıklı Gol */
    if (mtid === 38 && oca.length === 2) {
      markets['btts'] = { yes: get(1), no: get(2) };
    }

    /* 1Y Karşılıklı Gol */
    if (mtid === 452 && oca.length === 2) {
      markets['ht_btts'] = { yes: get(1), no: get(2) };
    }

    /* 2Y Karşılıklı Gol */
    if (mtid === 599 && oca.length === 2) {
      markets['2h_btts'] = { yes: get(1), no: get(2) };
    }

    /* 1Y/2Y Karşılıklı Gol */
    if (mtid === 801 && oca.length === 4) {
      markets['halves_btts'] = {
        'yy': get(3), 'yn': get(2),
        'ny': get(4), 'nn': get(1),
      };
    }

    /* İlk Golü Kim Atar */
    if (mtid === 291 && oca.length === 3) {
      markets['first_goal'] = { home: get(1), none: get(2), away: get(3) };
    }

    /* Ev Sahibi İki Yarıda da Gol */
    if (mtid === 295 && oca.length >= 1) {
      markets['home_score_both'] = { yes: get(1), no: get(2) };
    }

    /* Deplasman İki Yarıda da Gol */
    if (mtid === 296 && oca.length >= 1) {
      markets['away_score_both'] = { yes: get(1), no: get(2) };
    }

    /* Ev Sahibi Hangi Yarıda Daha Çok Gol */
    if (mtid === 586 && oca.length === 3) {
      markets['home_more_goals_half'] = { first: get(1), equal: get(2), second: get(3) };
    }

    /* Deplasman Hangi Yarıda Daha Çok Gol */
    if (mtid === 587 && oca.length === 3) {
      markets['away_more_goals_half'] = { first: get(1), equal: get(2), second: get(3) };
    }

    /* ── TARAF ALT/ÜST ──────────────────────── */

    /* Ev Sahibi 0.5 Alt/Üst */
    if (mtid === 212 && oca.length === 2) {
      markets['h_ou05'] = { under: get(1), over: get(2) };
    }

    /* Ev Sahibi 1.5 Alt/Üst */
    if (mtid === 20 && oca.length === 2) {
      markets['h_ou15'] = { under: get(1), over: get(2) };
    }

    /* Ev Sahibi 2.5 Alt/Üst */
    if (mtid === 326 && oca.length === 2) {
      markets['h_ou25'] = { under: get(1), over: get(2) };
    }

    /* Deplasman 0.5 Alt/Üst */
    if (mtid === 256 && oca.length === 2) {
      markets['a_ou05'] = { under: get(1), over: get(2) };
    }

    /* Deplasman 1.5 Alt/Üst */
    if (mtid === 29 && oca.length === 2) {
      markets['a_ou15'] = { under: get(1), over: get(2) };
    }

    /* Deplasman 2.5 Alt/Üst */
    if (mtid === 328 && oca.length === 2) {
      markets['a_ou25'] = { under: get(1), over: get(2) };
    }

    /* Ev Sahibi 1Y 0.5 Alt/Üst */
    if (mtid === 455 && oca.length === 2) {
      markets['h_ht_ou05'] = { under: get(1), over: get(2) };
    }

    /* Deplasman 1Y 0.5 Alt/Üst */
    if (mtid === 457 && oca.length === 2) {
      markets['a_ht_ou05'] = { under: get(1), over: get(2) };
    }

    /* ── TOPLAM GOL ─────────────────────────── */

    /* Toplam Gol Aralığı */
    if (mtid === 43 && oca.length === 4) {
      markets['goal_range'] = {
        '0_1': get(1), '2_3': get(2), '4_5': get(3), '6p': get(4),
      };
    }

    /* En Çok Gol Olacak Yarı */
    if (mtid === 48 && oca.length === 3) {
      markets['more_goals_half'] = { first: get(1), equal: get(2), second: get(3) };
    }

    /* Tek/Çift  ⚠️ NOT: MTID=49 Tek/Çift'tir, KG değil */
    if (mtid === 49 && oca.length === 2) {
      markets['odd_even'] = { odd: get(1), even: get(2) };
    }

    /* 1Y Tek/Çift */
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
  const upserts = [];

  for (const fix of allFixtures) {
    let best = null, bestScore = THRESHOLD - 0.01;

    for (const ev of events) {
      const hs  = tokenSim(fix.home_team, ev.HN);
      const as_ = tokenSim(fix.away_team, ev.AN);

      /* Her iki takım da minimum 0.35 benzerlik sağlamalı */
      if (hs < 0.35 || as_ < 0.35) continue;

      const score = (hs + as_) / 2;
      if (score > bestScore) { bestScore = score; best = ev; }
    }

    if (best) {
      const markets = parseMarkets(
        best.MA,
        `${fix.home_team} vs ${fix.away_team}  →  ${best.HN} vs ${best.AN}`
      );

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
    }
  }

  if (!upserts.length) { console.log('[Odds] Upsert edilecek veri yok.'); return; }

  /* 5. Supabase upsert */
  console.log(`\n[Odds] ${upserts.length} kayıt yazılıyor...`);
  const { error: upErr } = await sb
    .from('match_odds')
    .upsert(upserts, { onConflict: 'fixture_id' });

  if (upErr) { console.error('[Odds] Upsert hatası:', upErr.message); process.exit(1); }
  console.log(`[Odds] ✅ ${upserts.length} maç oranı güncellendi.`);
}

run().catch(e => { console.error('[Odds] Beklenmedik hata:', e); process.exit(1); });
