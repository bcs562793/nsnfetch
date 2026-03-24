/**
 * Nesine gerçek yapısını tam analiz et
 * sg.EA içindeki bir event'in MA (markets) yapısını göster
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
      let buf = '';
      res.on('data', d => buf += d);
      res.on('end', () => resolve(buf));
    });
    req.on('error', reject);
    req.setTimeout(30000, () => { req.destroy(); reject(new Error('Timeout')); });
  });
}

async function run() {
  const raw = await fetchRaw('https://cdnbulten.nesine.com/api/bulten/getprebultenfull');
  const data = JSON.parse(raw);
  const events = data?.sg?.EA || [];
  console.log(`Toplam etkinlik: ${events.length}`);

  // İlk futbol etkinliğini bul (TYPE=1 futbol)
  const football = events.filter(e => e.TYPE === 1);
  console.log(`Futbol etkinliği: ${football.length}`);

  // İlk 2 futbol maçını detaylı göster
  for (const ev of football.slice(0, 2)) {
    console.log('\n--- ETKİNLİK ---');
    console.log('C:', ev.C, '| HN:', ev.HN, '| AN:', ev.AN);
    console.log('D:', ev.D, 'T:', ev.T, 'TYPE:', ev.TYPE);
    console.log('MA (markets):', JSON.stringify(ev.MA, null, 2).slice(0, 1000));
  }

  // Raith, Granada gibi eşleşmeyen takımları ara
  const searchTerms = ['Raith', 'Granada', 'Shrewsbury', 'Brackley', 'Johnstone', 'Pereira', 'Newport'];
  console.log('\n=== ARANAN TAKIMLAR ===');
  for (const ev of events) {
    for (const term of searchTerms) {
      if ((ev.HN||'').toLowerCase().includes(term.toLowerCase()) || 
          (ev.AN||'').toLowerCase().includes(term.toLowerCase())) {
        console.log(`BULUNDU [${term}]: HN="${ev.HN}" AN="${ev.AN}" TYPE=${ev.TYPE}`);
      }
    }
  }
}

run().catch(e => console.error('HATA:', e));
