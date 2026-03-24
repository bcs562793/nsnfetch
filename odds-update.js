/**
 * SCOREPOP — odds-debug.js
 * Nesine bülteninin gerçek yapısını görmek için çalıştır.
 * node odds-debug.js
 */
'use strict';
const https = require('https');

function fetchRaw(url) {
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
      console.log('HTTP Status:', res.statusCode);
      console.log('Headers:', JSON.stringify(res.headers, null, 2));
      let buf = '';
      res.on('data', d => buf += d);
      res.on('end', () => resolve(buf));
    });
    req.on('error', reject);
    req.setTimeout(30000, () => { req.destroy(); reject(new Error('Timeout')); });
  });
}

async function run() {
  console.log('\n=== cdnbulten endpoint ===');
  const raw = await fetchRaw('https://cdnbulten.nesine.com/api/bulten/getprebultenfull');
  console.log('Response uzunluğu:', raw.length, 'karakter');
  console.log('İlk 200 karakter:', raw.slice(0, 200));

  if (raw.length < 10) {
    console.log('\ncdnbulten boş geldi, direkt endpoint deneniyor...');
    const raw2 = await fetchRaw('https://bulten.nesine.com/api/bulten/getprebultenfull');
    console.log('Response uzunluğu:', raw2.length);
    console.log('İlk 200 karakter:', raw2.slice(0, 200));
    return;
  }

  let data;
  try { data = JSON.parse(raw); } catch(e) { console.log('JSON parse hatası:', e.message); return; }

  console.log('\n=== JSON ÜST LEVEL KEYS ===');
  console.log(Object.keys(data));

  // Data.C veya C bul
  const root = data?.Data || data;
  console.log('\n=== ROOT KEYS ===');
  console.log(Object.keys(root).slice(0, 20));

  const coupons = root?.C || root?.c;
  if (!coupons) {
    console.log('\nC key bulunamadı! Tüm root:', JSON.stringify(root).slice(0, 500));
    return;
  }

  const keys = Object.keys(coupons);
  console.log(`\n=== ${keys.length} ETKİNLİK BULUNDU ===`);

  // İlk 3 etkinliği detaylı göster
  for (const k of keys.slice(0, 3)) {
    console.log(`\n--- Etkinlik key: ${k} ---`);
    console.log(JSON.stringify(coupons[k], null, 2).slice(0, 800));
  }

  // İçinde "Raith" veya "Granada" geçen var mı ara
  const searchTerms = ['Raith', 'Granada', 'Shrewsbury', 'Brackley', 'Johnstone', 'Pereira'];
  console.log('\n=== ARANAN TAKIMLAR ===');
  for (const [k, ev] of Object.entries(coupons)) {
    const str = JSON.stringify(ev);
    for (const term of searchTerms) {
      if (str.toLowerCase().includes(term.toLowerCase())) {
        console.log(`BULUNDU [${term}] key:${k}`, JSON.stringify(ev).slice(0, 300));
        break;
      }
    }
  }
}

run().catch(e => { console.error('HATA:', e); });
