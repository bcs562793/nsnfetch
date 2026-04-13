/**
 * SCOREPOP — odds-update.js  (v7 - Trend Eklentisi)
 * Değişiklikler v5 → v6:
 * 1. Per-takım min eşiği 0.35 → 0.25, genel THRESHOLD 0.45 → 0.40
 * 2. Eşleşme bulunamazsa home/away ters kontrol
 * 3. TEAM_ALIASES ile özel isim düzeltmeleri
 * v6 -> v7 (Yeni):
 * 4. markets_change objesi eklendi (oran düşüş/yükseliş takibi)
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

/* ── Normalize ──────────────────────────────── */
function norm(s) {
  return (s || '')
    .toLowerCase()
    .replace(/ğ/g,'g').replace(/ü/g,'u').replace(/ş/g,'s')
    .replace(/ı/g,'i').replace(/ö/g,'o').replace(/ç/g,'c')
    .replace(/[^a-z0-9]/g,' ')
    .replace(/\s+/g,' ').trim();
}

/* ── Alias tablosu (norm(DB ismi) → Nesine ismi) ─── */
const TEAM_ALIASES = {
  // MLS
  'seattle s'                   : 'seattle sounders',
  'st louis'                    : 's louis city',
  // Kosta Rika
  's san jose'                  : 'deportivo saprissa',
  'cs cartagines'               : 'cartagines',
  // Azerbaycan
  'gabala'                      : 'kabala',
  // Yunanistan
  'panaitolikos'                : 'paneitolikos',
  'panserraikos'                : 'panseraikos',
  // Avusturya 2. lig
  'rz pellets wac'              : 'wolfsberger',
  'tsv egger glas hartberg'     : 'hartberg',
  'fc red bull salzburg'        : 'salzburg',
  'ksv 1919'                    : 'kapfenberger sv',
  'sk rapid ii'                 : 'r wien amt',
  'sw bregenz'                  : 'schwarz weiss b',
  'sk austria klagenfurt'       : 'klagenfurt',
  'skn st polten'               : 'st polten',
  'skn st pölten'               : 'st polten',
  'fc hertha wels'              : 'wsc hertha',
  // Faroe
  'b68 toftir'                  : 'tofta itrottarfelag b68',
  // Arjantin
  'ca ferrocarril midland'      : 'f midland',
  'gimnasia y esgrima de men'   : 'gimnasia y',
  'estudiantes rio cuarto'      : 'e rio cuarto',
  // Kolombiya
  'ind medellin'                : 'ind medellin',
  'america de cali'             : 'america cali',
  // Sırbistan
  'napredak'                    : 'fk napredak kru',
  'tsc backa to'                : 'tsc backa t',
  // Rusya
  'd makhachkala'               : 'dyn makhachkala',
  // Belçika
  'rfc liege'                   : 'rfc liege',
  'raal la louviere'            : 'raal la louviere',
  'racing genk b'               : 'j krc genk u23',
  // İrlanda Kuzey
  'h w welders'                 : 'harland wolff w',
  // Avustralya (K)
  'adelaide united fc k'        : 'adelaide utd k',
  'canberra utd k'              : 'canberra utd k',
  'brisbane roar fc k'          : 'brisbane r k',
  // Kazakistan
  'kyzylzhar'                   : 'kyzyl zhar sk',
  // Gürcistan
  'd batumi'                    : 'dinamo b',
  // İspanya
  'algeciras cf'                : 'algeciras',
  'ibiza'                       : 'i eivissa',
  // İtalya
  'gubbio'                      : 'as gubbio 1910',
  'pineto'                      : 'asd pineto calcio',
  'mont tuscia'                 : 'monterosi t',
  'ssd casarano calcio'         : 'casarano',
  'palermo'                     : 'us palermo',
  'avellino'                    : 'as avellino 1912',
  // İngiltere
  'utdofmanch'                  : 'utd of manch',
  // Almanya
  'sg sonnenhof grossaspach'    : 'grossaspach',
  // Çin
  'chengdu'                     : 'chengdu ron',
  'qingdao y i'                 : 'qingdao yth is',
  // Brezilya
  'bragantino'                  : 'rb bragantino',
  'palmeiras'                   : 'palmeiras sp',
  'gremio'                      : 'gremio p',
  // TEAM_ALIASES'e eklenecekler
  'baltika'                    : 'b kaliningrad',
  'velez'                      : 'v sarsfield',
  's shenhua'                  : 'shanghai s',
  'tianjin jinmen'             : 'tianjin jin',
  'g birliği'                  : 'gençlerbirliği',
  '1 fc slovacko'              : 'slovacko',
  'jagiellonia'                : 'j bialystok',
  'ilves'                      : 'tampereen i',
  'auvergne'                   : 'le puy foot 43',
  'juventud'                   : 'ca juventud de las piedras',
  'akademisk bo'               : 'ab gladsaxe',
  'lusitania de lourosa'       : 'lusitania',
  'stade nyonnais'             : 'std nyonnis',
  'fc zurich'                  : 'zurih',
  'cordoba cf'                 : 'cordoba',
  'deportivo'                  : 'dep la coruna',
  'masr'                       : 'zed',
  'future fc'                  : 'modern sport club',
  'new york rb'                : 'ny red bulls',
  'the new saints'             : 'tns',
  'vancouver'                  : 'v whitecaps',
  'fc hradec kralove'          : 'h kralove',
  'fc midtjylland'             : 'midtjylland',
  'sønderjyske'                : 'sonderjyske',
  'pacos de ferreira'          : 'p ferreira',
};

function normWithAlias(s) {
  const n = norm(s);
  return TEAM_ALIASES[n] || n;
}

/* ── Token benzerliği ───────────────────────── */
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

function matchScore(homeDB, awayDB, ev) {
  const hs  = tokenSim(normWithAlias(homeDB), norm(ev.HN));
  const as_ = tokenSim(normWithAlias(awayDB), norm(ev.AN));
  return { hs, as_, avg: (hs + as_) / 2 };
}

/* ── Market parse ───────────────────────────── */
function parseMarkets(maArr) {
  const markets = {};
  if (!Array.isArray(maArr)) return markets;

  for (const m of maArr) {
    const mtid = m.MTID;
    const sov  = parseFloat(m.SOV ?? 0);
    const oca  = m.OCA || [];
    const get  = (n) => { const o = oca.find(x => x.N === n); return o ? +o.O : 0; };

    if (mtid === 1   && oca.length === 3) { markets['1x2']        = { home: get(1), draw: get(2), away: get(3) }; }
    if (mtid === 3   && oca.length === 3) { markets['dc']         = { '1x': get(1), '12': get(2), 'x2': get(3) }; }
    if (mtid === 268 && oca.length === 3) {
      const sign = sov >= 0 ? `p${String(sov).replace('.','_')}` : `m${String(Math.abs(sov)).replace('.','_')}`;
      markets[`ah_${sign}`] = { home: get(1), draw: get(2), away: get(3), line: sov };
    }
    if (mtid === 5   && oca.length === 9) {
      markets['ht_ft'] = { '1/1': get(1), '1/X': get(2), '1/2': get(3), 'X/1': get(4), 'X/X': get(5), 'X/2': get(6), '2/1': get(7), '2/X': get(8), '2/2': get(9) };
    }
    if (mtid === 342 && oca.length === 6) { markets['ms_ou15'] = { 'h_u': get(1), 'x_u': get(2), 'a_u': get(3), 'h_o': get(4), 'x_o': get(5), 'a_o': get(6) }; }
    if (mtid === 343 && oca.length === 6) { markets['ms_ou25'] = { 'h_u': get(1), 'x_u': get(2), 'a_u': get(3), 'h_o': get(4), 'x_o': get(5), 'a_o': get(6) }; }
    if (mtid === 272 && oca.length === 6) {
      const key = Math.abs(sov - 3.5) < 0.01 ? 'ms_ou35' : Math.abs(sov - 4.5) < 0.01 ? 'ms_ou45' : `ms_ou_${String(sov).replace('.','_')}`;
      markets[key] = { 'h_u': get(1), 'x_u': get(2), 'a_u': get(3), 'h_o': get(4), 'x_o': get(5), 'a_o': get(6) };
    }
    if (mtid === 414 && oca.length === 6) { markets['ms_kg']      = { 'h_y': get(1), 'x_y': get(3), 'a_y': get(5), 'h_n': get(2), 'x_n': get(4), 'a_n': get(6) }; }
    if (mtid === 588 && oca.length >= 6)  { markets['win_margin'] = { 'h3p': get(1), 'h2': get(2), 'h1': get(3), 'a1': get(4), 'a2': get(5), 'a3p': get(6), 'draw': get(7) }; }
    if (mtid === 7   && oca.length === 3) { markets['ht_1x2']     = { home: get(1), draw: get(2), away: get(3) }; }
    if (mtid === 8   && oca.length === 3) { markets['ht_dc']      = { '1x': get(1), '12': get(2), 'x2': get(3) }; }
    if (mtid === 459 && oca.length === 6) { markets['ht_ms_ou15'] = { 'h_u': get(1), 'x_u': get(2), 'a_u': get(3), 'h_o': get(4), 'x_o': get(5), 'a_o': get(6) }; }
    if (mtid === 416 && oca.length === 6) { markets['ht_ms_kg']   = { 'h_y': get(1), 'x_y': get(3), 'a_y': get(5), 'h_n': get(2), 'x_n': get(4), 'a_n': get(6) }; }
    if (mtid === 9   && oca.length === 3) { markets['2h_1x2']     = { home: get(1), draw: get(2), away: get(3) }; }
    if (mtid === 591 && oca.length >= 1)  { markets['home_win_both'] = { yes: get(1), no: get(2) }; }
    if (mtid === 592 && oca.length >= 1)  { markets['away_win_both'] = { yes: get(1), no: get(2) }; }
    if (mtid === 209 && oca.length === 2) { markets['ht_ou05']       = { under: get(1), over: get(2) }; }
    if (mtid === 14  && oca.length === 2) { markets['ht_ou15']       = { under: get(1), over: get(2) }; }
    if (mtid === 15  && oca.length === 2) { markets['ht_ou25']       = { under: get(1), over: get(2) }; }
    if (mtid === 528 && oca.length === 2) { markets['both_half_u15'] = { yes: get(1), no: get(2) }; }
    if (mtid === 529 && oca.length === 2) { markets['both_half_o15'] = { yes: get(1), no: get(2) }; }
    if (mtid === 11  && oca.length === 2) { markets['ou15']          = { under: get(1), over: get(2) }; }
    if (mtid === 12  && oca.length === 2) { markets['ou25']          = { under: get(1), over: get(2) }; }
    if (mtid === 13  && oca.length === 2) { markets['ou35']          = { under: get(1), over: get(2) }; }
    if (mtid === 155 && oca.length === 2) {
      if      (Math.abs(sov - 4.5) < 0.01) { markets['ou45'] = { under: get(1), over: get(2) }; }
      else if (Math.abs(sov - 5.5) < 0.01) { markets['ou55'] = { under: get(1), over: get(2) }; }
      else { markets[`ou_${String(sov).replace('.','_')}`] = { under: get(1), over: get(2), line: sov }; }
    }
    if (mtid === 446 && oca.length === 4) { markets['ou25_kg']           = { 'u_y': get(1), 'o_y': get(2), 'u_n': get(3), 'o_n': get(4) }; }
    if (mtid === 38  && oca.length === 2) { markets['btts']              = { yes: get(1), no: get(2) }; }
    if (mtid === 452 && oca.length === 2) { markets['ht_btts']           = { yes: get(1), no: get(2) }; }
    if (mtid === 599 && oca.length === 2) { markets['2h_btts']           = { yes: get(1), no: get(2) }; }
    if (mtid === 801 && oca.length === 4) { markets['halves_btts']       = { 'yy': get(3), 'yn': get(2), 'ny': get(4), 'nn': get(1) }; }
    if (mtid === 291 && oca.length === 3) { markets['first_goal']        = { home: get(1), none: get(2), away: get(3) }; }
    if (mtid === 295 && oca.length >= 1)  { markets['home_score_both']   = { yes: get(1), no: get(2) }; }
    if (mtid === 296 && oca.length >= 1)  { markets['away_score_both']   = { yes: get(1), no: get(2) }; }
    if (mtid === 586 && oca.length === 3) { markets['home_more_goals_half'] = { first: get(1), equal: get(2), second: get(3) }; }
    if (mtid === 587 && oca.length === 3) { markets['away_more_goals_half'] = { first: get(1), equal: get(2), second: get(3) }; }
    if (mtid === 212 && oca.length === 2) { markets['h_ou05']    = { under: get(1), over: get(2) }; }
    if (mtid === 20  && oca.length === 2) { markets['h_ou15']    = { under: get(1), over: get(2) }; }
    if (mtid === 326 && oca.length === 2) { markets['h_ou25']    = { under: get(1), over: get(2) }; }
    if (mtid === 256 && oca.length === 2) { markets['a_ou05']    = { under: get(1), over: get(2) }; }
    if (mtid === 29  && oca.length === 2) { markets['a_ou15']    = { under: get(1), over: get(2) }; }
    if (mtid === 328 && oca.length === 2) { markets['a_ou25']    = { under: get(1), over: get(2) }; }
    if (mtid === 455 && oca.length === 2) { markets['h_ht_ou05'] = { under: get(1), over: get(2) }; }
    if (mtid === 457 && oca.length === 2) { markets['a_ht_ou05'] = { under: get(1), over: get(2) }; }
    if (mtid === 43  && oca.length === 4) { markets['goal_range']    = { '0_1': get(1), '2_3': get(2), '4_5': get(3), '6p': get(4) }; }
    if (mtid === 48  && oca.length === 3) { markets['more_goals_half'] = { first: get(1), equal: get(2), second: get(3) }; }
    if (mtid === 49  && oca.length === 2) { markets['odd_even']      = { odd: get(1), even: get(2) }; }
    if (mtid === 450 && oca.length === 2) { markets['ht_odd_even']   = { odd: get(1), even: get(2) }; }
  }

  return markets;
}

/* ── Ana ────────────────────────────────────── */
async function run() {
  console.log('[Odds] Supabase maçları çekiliyor...');
  const { data: rawFixtures, error: fErr } = await sb
    .from('future_matches')
    .select('fixture_id, date, data')
    .limit(1200);

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

  // YENİ EKLEME (V7) 1. KISIM: Veritabanındaki eski oranları (trend için) çekiyoruz
  console.log('[Odds] Eski oranlar çekiliyor (Trend analizi için)...');
  const { data: existingDbOdds } = await sb
    .from('match_odds')
    .select('fixture_id, odds_data')
    .in('fixture_id', allFixtures.map(f => f.fixture_id));
  
  const oldOddsMap = {};
  (existingDbOdds || []).forEach(row => {
    oldOddsMap[row.fixture_id] = row.odds_data || {};
  });

  console.log('[Odds] Nesine bülten indiriliyor...');
  let nesineData;
  try { nesineData = await fetchJSON('https://cdnbulten.nesine.com/api/bulten/getprebultenfull'); }
  catch (e) { console.error('[Odds] Nesine CDN hatası:', e.message); process.exit(1); }

  const events = (nesineData?.sg?.EA || []).filter(e => e.TYPE === 1);
  console.log(`[Odds] Nesine'de ${events.length} futbol etkinliği`);

  const THRESHOLD    = 0.40;  // v5: 0.45
  const MIN_PER_TEAM = 0.25;  // v5: 0.35

  const upserts     = [];
  const debugMissed = [];

  for (const fix of allFixtures) {
    let best = null, bestScore = THRESHOLD - 0.01;
    let bestSwapped = false;

    const allCandidates = events.map(ev => {
      const normal  = matchScore(fix.home_team, fix.away_team, ev);
      const swapped = matchScore(fix.away_team, fix.home_team, ev);
      const useSwap = swapped.avg > normal.avg;
      return {
        hn: ev.HN, an: ev.AN,
        hs:      useSwap ? swapped.hs  : normal.hs,
        as_:     useSwap ? swapped.as_ : normal.as_,
        avg:     useSwap ? swapped.avg : normal.avg,
        swapped: useSwap,
        _ev: ev,
      };
    });

    for (const c of allCandidates) {
      if (c.hs < MIN_PER_TEAM || c.as_ < MIN_PER_TEAM) continue;
      if (c.avg > bestScore) {
        bestScore   = c.avg;
        best        = c._ev;
        bestSwapped = c.swapped;
      }
    }

    if (best) {
      const markets = parseMarkets(best.MA);
      if (Object.keys(markets).length > 0) {
        const swapLabel = bestSwapped ? ' [TERS]' : '';

        // YENİ EKLEME (V7) 2. KISIM: Eski oranlarla karşılaştırıp değişimi hesaplıyoruz
        const oldData = oldOddsMap[fix.fixture_id] || {};
        const oldMarkets = oldData.markets || {};
        const oldChanges = oldData.markets_change || {};
        const markets_change = {};

        for (const mKey of Object.keys(markets)) {
          markets_change[mKey] = {};
          for (const oKey of Object.keys(markets[mKey])) {
            if (oKey === 'line') continue; // line değişimi trend hesaplamaz

            const newVal = markets[mKey][oKey];
            const oldVal = oldMarkets[mKey]?.[oKey];

            if (oldVal && newVal !== oldVal) {
              markets_change[mKey][oKey] = newVal > oldVal ? 1 : -1; // 1: Arttı, -1: Düştü
            } else {
              markets_change[mKey][oKey] = oldVal ? (oldChanges[mKey]?.[oKey] || 0) : 0; // Eski trendi koru veya 0 (sabit)
            }
          }
        }

        upserts.push({
          fixture_id: fix.fixture_id,
          odds_data: {
            source: 'İddaa / Nesine',
            markets,
            markets_change, // Yeni eklenen trend verisi DB'ye gidiyor
            nesine_name: `${best.HN} - ${best.AN}`,
          },
          updated_at: new Date().toISOString(),
        });
        console.log(`  ✓ ${fix.home_team} vs ${fix.away_team}  →  ${best.HN} vs ${best.AN} (${bestScore.toFixed(2)})${swapLabel} [${Object.keys(markets).join(',')}]`);
      } else {
        console.log(`  ~ ${fix.home_team} vs ${fix.away_team}  →  eşleşti ama market yok`);
      }
    } else {
      console.log(`  ✗ ${fix.home_team} vs ${fix.away_team}  →  eşleşme bulunamadı`);
      const top3 = allCandidates
        .filter(c => c.hs > 0.15 || c.as_ > 0.15)
        .sort((a, b) => b.avg - a.avg)
        .slice(0, 3);
      debugMissed.push({ fix, top3 });
    }
  }

  if (!upserts.length) {
    console.log('[Odds] Upsert edilecek veri yok.');
  } else {
    console.log(`\n[Odds] ${upserts.length} kayıt yazılıyor...`);
    const { error: upErr } = await sb
      .from('match_odds')
      .upsert(upserts, { onConflict: 'fixture_id' });
    if (upErr) { console.error('[Odds] Upsert hatası:', upErr.message); process.exit(1); }
    console.log(`[Odds] ✅ ${upserts.length} maç oranı güncellendi.`);
  }

  /* ═══════════════════════════════════════════
   * DEBUG — EN ALTTA
   * ═══════════════════════════════════════════ */
  if (debugMissed.length === 0) {
    console.log('\n[DEBUG] ✅ Tüm maçlar eşleşti.');
    return;
  }

  console.log('\n' + '═'.repeat(60));
  console.log(`[DEBUG] EŞLEŞMEYEN MAÇLAR — ${debugMissed.length} adet`);
  console.log('═'.repeat(60));

  for (const { fix, top3 } of debugMissed) {
    console.log(`\n❌  fixture_id=${fix.fixture_id}  tarih=${fix.date ?? '-'}`);
    console.log(`    DB  : "${fix.home_team}"  vs  "${fix.away_team}"`);
    if (top3.length === 0) {
      console.log('    → Nesine\'de hiç benzer takım yok');
    } else {
      console.log('    En yakın adaylar:');
      for (const c of top3) {
        const near = c.avg >= 0.35 ? '⚠️ ALIAS ekle' : '';
        const swap = c.swapped ? ' [ters]' : '';
        console.log(`      ${c.avg.toFixed(2)}  "${c.hn}" vs "${c.an}"  (ev=${c.hs.toFixed(2)} dep=${c.as_.toFixed(2)})${swap} ${near}`);
      }
    }
  }

  console.log('\n' + '─'.repeat(60));
  console.log('[DEBUG] İpuçları:');
  console.log('  • ⚠️ ALIAS ekle  → TEAM_ALIASES objesine ekle');
  console.log('  • [ters]         → DB\'de home/away yanlış');
  console.log('  • Aday yok       → Nesine\'de bu maç yok');
  console.log('─'.repeat(60) + '\n');
}

run().catch(e => { console.error('[Odds] Beklenmedik hata:', e); process.exit(1); });
