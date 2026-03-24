/**
 * SCOREPOP — odds-update.js
 * Nesine CDN'den pre-match oranlarını çeker, Supabase match_odds tablosuna yazar.
 *
 * Nasıl çalışır:
 *  1. Supabase'den bugün + gelecek maçları çeker (fixture_id, home_team, away_team, date)
 *  2. Nesine cdnbulten API'sinden tam bülten indirir (~2MB, auth yok)
 *  3. Takım adı benzerliğiyle maçları eşleştirir
 *  4. match_odds tablosuna upsert eder
 *
 * Ortam değişkenleri: SUPABASE_URL, SUPABASE_KEY
 */

'use strict';

const https = require('https');
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_KEY;

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error('[Odds] SUPABASE_URL ve SUPABASE_KEY gerekli');
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SUPABASE_KEY);

/* ── HTTP GET yardımcı ─────────────────────────── */
function fetchJSON(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, {
      headers: {
        'Accept': 'application/json',
        'Accept-Encoding': 'identity',   // Brotli devre dışı (Node zlib yok)
        'Referer': 'https://www.nesine.com/',
        'User-Agent': 'Mozilla/5.0 (compatible; ScorePop/1.0)',
      }
    }, res => {
      let buf = '';
      res.on('data', d => buf += d);
      res.on('end', () => {
        try { resolve(JSON.parse(buf)); }
        catch (e) { reject(new Error(`JSON parse hatası (${url}): ${e.message}`)); }
      });
    });
    req.on('error', reject);
    req.setTimeout(30000, () => { req.destroy(); reject(new Error('Timeout')); });
  });
}

/* ── Türkçe harf normalize + benzerlik ─────────── */
function normalize(s) {
  return (s || '')
    .toLowerCase()
    .replace(/ğ/g,'g').replace(/ü/g,'u').replace(/ş/g,'s')
    .replace(/ı/g,'i').replace(/ö/g,'o').replace(/ç/g,'c')
    .replace(/[^a-z0-9]/g,' ')
    .replace(/\s+/g,' ').trim();
}

/* Basit token overlap benzerliği (0..1) */
function similarity(a, b) {
  const ta = new Set(normalize(a).split(' ').filter(Boolean));
  const tb = new Set(normalize(b).split(' ').filter(Boolean));
  if (!ta.size || !tb.size) return 0;
  let common = 0;
  for (const t of ta) if (tb.has(t)) common++;
  return common / Math.max(ta.size, tb.size);
}

/* ── Nesine bülten parse ────────────────────────
   Nesine JSON yapısı (getprebultenfull):
   {
     "Data": {
       "C": {         ← Coupon/Maç listesi
         "<EventCode>": {
           "OCG": {   ← Oran Grubu (market)
             "1": { "OC": { "1": val, "0": val, "2": val } },  ← 1X2
             "5": { ... }                                        ← Alt/Üst
           },
           "D": "2026-03-24",
           "T": "21:45",
           "N": "Galatasaray - Fenerbahçe",
           ...
         }
       }
     }
   }
   Market kodları (Nesine):
     OCG["1"]  → Maç Sonucu (1X2): OC.1=ev, OC.0=beraberlik, OC.2=deplasman
     OCG["5"]  → Alt/Üst 2.5:      OC.25=alt, OC.26=üst
     OCG["6"]  → Alt/Üst 3.5:      OC.35=alt, OC.36=üst
     OCG["3"]  → Çifte Şans:       OC.3=1X, OC.7=12, OC.8=X2
     OCG["7"]  → Karşılıklı Gol:   OC.76=var, OC.77=yok
   ─────────────────────────────────────────────── */
function parseNesineEvent(ev) {
  try {
    const ocg = ev.OCG || {};
    const markets = {};

    /* 1X2 */
    const m1 = ocg['1']?.OC;
    if (m1) {
      markets['1x2'] = {
        home: parseFloat(m1['1'] || 0),
        draw: parseFloat(m1['0'] || 0),
        away: parseFloat(m1['2'] || 0),
      };
    }

    /* Çifte Şans */
    const m3 = ocg['3']?.OC;
    if (m3) {
      markets['dc'] = {
        '1x': parseFloat(m3['3'] || 0),
        '12': parseFloat(m3['7'] || 0),
        'x2': parseFloat(m3['8'] || 0),
      };
    }

    /* Alt/Üst 2.5 */
    const m5 = ocg['5']?.OC;
    if (m5) {
      markets['ou25'] = {
        under: parseFloat(m5['25'] || 0),
        over:  parseFloat(m5['26'] || 0),
      };
    }

    /* Alt/Üst 3.5 */
    const m6 = ocg['6']?.OC;
    if (m6) {
      markets['ou35'] = {
        under: parseFloat(m6['35'] || 0),
        over:  parseFloat(m6['36'] || 0),
      };
    }

    /* Karşılıklı Gol */
    const m7 = ocg['7']?.OC;
    if (m7) {
      markets['btts'] = {
        yes: parseFloat(m7['76'] || 0),
        no:  parseFloat(m7['77'] || 0),
      };
    }

    return { markets, name: ev.N || '', date: ev.D || '' };
  } catch {
    return null;
  }
}

/* ── Ana fonksiyon ──────────────────────────────── */
async function run() {
  /* 1. Supabase maçları çek */
  const today = new Date().toISOString().slice(0, 10);
  const tomorrow = new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10);

  console.log('[Odds] Supabase maçları çekiliyor...');
  const { data: fixtures, error: fErr } = await sb
    .from('future_matches')
    .select('fixture_id, home_team, away_team, match_date')
    .gte('match_date', today)
    .lte('match_date', tomorrow)
    .limit(300);

  if (fErr) { console.error('[Odds] Supabase hata:', fErr.message); process.exit(1); }

  const { data: futureFixtures } = await sb
    .from('future_matches')
    .select('fixture_id, home_team, away_team, match_date')
    .gte('match_date', today)
    .lte('match_date', tomorrow)
    .limit(300);

  const allFixtures = [...(fixtures || []), ...(futureFixtures || [])];
  console.log(`[Odds] ${allFixtures.length} maç bulundu`);

  if (!allFixtures.length) {
    console.log('[Odds] Güncellenecek maç yok. Çıkılıyor.');
    return;
  }

  /* 2. Nesine bülten indir */
  console.log('[Odds] Nesine bülten indiriliyor...');
  let nesineData;
  try {
    nesineData = await fetchJSON('https://cdnbulten.nesine.com/api/bulten/getprebultenfull');
  } catch (e) {
    console.error('[Odds] Nesine CDN hatası:', e.message);
    process.exit(1);
  }

  /* Nesine event listesini düzleştir */
  const events = [];
  try {
    const coupons = nesineData?.Data?.C || nesineData?.C || {};
    for (const [code, ev] of Object.entries(coupons)) {
      const parsed = parseNesineEvent(ev);
      if (parsed && parsed.name) {
        // "Galatasaray - Fenerbahçe" → iki takım adı
        const parts = parsed.name.split(/\s*[-–]\s*/);
        if (parts.length >= 2) {
          events.push({
            code,
            home: parts[0].trim(),
            away: parts.slice(1).join(' - ').trim(),
            date: parsed.date,
            markets: parsed.markets,
          });
        }
      }
    }
  } catch (e) {
    console.error('[Odds] Bülten parse hatası:', e.message);
  }

  console.log(`[Odds] Nesine'de ${events.length} etkinlik parse edildi`);

  /* 3. Eşleştir + upsert */
  const upserts = [];
  const THRESHOLD = 0.55;

  for (const fix of allFixtures) {
    let best = null, bestScore = THRESHOLD - 0.01;

    for (const ev of events) {
      const hs = similarity(fix.home_team, ev.home);
      const as_ = similarity(fix.away_team, ev.away);
      const score = (hs + as_) / 2;
      if (score > bestScore) {
        bestScore = score;
        best = ev;
      }
    }

    if (best && Object.keys(best.markets).length > 0) {
      upserts.push({
        fixture_id: fix.fixture_id,
        odds_data: {
          source: 'İddaa / Nesine',
          markets: best.markets,
          nesine_name: best.home + ' - ' + best.away,
        },
        updated_at: new Date().toISOString(),
      });
      console.log(`  ✓ ${fix.home_team} vs ${fix.away_team} → ${best.home} vs ${best.away} (${bestScore.toFixed(2)})`);
    } else {
      console.log(`  ✗ ${fix.home_team} vs ${fix.away_team} → eşleşme bulunamadı`);
    }
  }

  if (!upserts.length) {
    console.log('[Odds] Upsert edilecek oran yok.');
    return;
  }

  /* 4. Supabase upsert */
  console.log(`[Odds] ${upserts.length} kayıt Supabase'e yazılıyor...`);
  const { error: upErr } = await sb
    .from('match_odds')
    .upsert(upserts, { onConflict: 'fixture_id' });

  if (upErr) {
    console.error('[Odds] Upsert hatası:', upErr.message);
    process.exit(1);
  }

  console.log(`[Odds] ✅ ${upserts.length} maç oranı güncellendi.`);
}

run().catch(e => { console.error('[Odds] Beklenmedik hata:', e); process.exit(1); });
