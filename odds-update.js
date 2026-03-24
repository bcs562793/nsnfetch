/**
 * SCOREPOP — odds-update.js  (v2)
 * Gerçek Nesine yapısına göre: sg.EA array, HN/AN, MA/MTID/OCA
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
    // tam eşleşme veya bir tokenın diğerini içermesi
    if (tb.has(t)) { hit++; continue; }
    for (const u of tb) {
      if (t.startsWith(u) || u.startsWith(t)) { hit += 0.7; break; }
    }
  }
  return hit / Math.max(ta.size, tb.size);
}

/* ── Nesine MA array'inden market parse ─────
   MTID=1   → Maç Sonucu 1X2  (N:1=ev, N:2=x, N:3=dep)
   MTID=2   → Çifte Şans      (N:1=1X, N:2=12, N:3=X2)
   MTID=14  → Alt/Üst (SOV=çizgi) (N:1=alt, N:2=üst)
   MTID=25  → Karşılıklı Gol  (N:1=var, N:2=yok)
   (MTID'ler gözlemle eşleştirildi — SOV ile çizgi belirlenir)
──────────────────────────────────────────── */
function parseMarkets(maArr) {
  const markets = {};
  if (!Array.isArray(maArr)) return markets;

  for (const m of maArr) {
    const mtid = m.MTID;
    const sov  = m.SOV ?? 0;
    const oca  = m.OCA || [];
    const get  = (n) => { const o = oca.find(x => x.N === n); return o ? +o.O : 0; };

    /* 1X2 */
    if (mtid === 1 && oca.length === 3) {
      markets['1x2'] = { home: get(1), draw: get(2), away: get(3) };
    }

    /* Çifte Şans */
    if (mtid === 2 && oca.length === 3) {
      markets['dc'] = { '1x': get(1), '12': get(2), 'x2': get(3) };
    }

    /* Alt / Üst — SOV değerine göre ayırt et */
    if (mtid === 14 && oca.length === 2) {
      if (Math.abs(sov - 2.5) < 0.01) {
        markets['ou25'] = { under: get(1), over: get(2) };
      } else if (Math.abs(sov - 3.5) < 0.01) {
        markets['ou35'] = { under: get(1), over: get(2) };
      } else if (Math.abs(sov - 1.5) < 0.01) {
        markets['ou15'] = { under: get(1), over: get(2) };
      }
    }

    /* Karşılıklı Gol */
    if (mtid === 25 && oca.length === 2) {
      markets['btts'] = { yes: get(1), no: get(2) };
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
  const THRESHOLD = 0.45; // kısaltmalar için düşürüldü
  const upserts = [];

  for (const fix of allFixtures) {
    let best = null, bestScore = THRESHOLD - 0.01;

    for (const ev of events) {
      const hs = tokenSim(fix.home_team, ev.HN);
      const as_ = tokenSim(fix.away_team, ev.AN);
      const score = (hs + as_) / 2;
      if (score > bestScore) { bestScore = score; best = ev; }
    }

    if (best) {
      const markets = parseMarkets(best.MA);
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
