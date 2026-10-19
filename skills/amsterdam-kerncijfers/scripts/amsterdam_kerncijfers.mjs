#!/usr/bin/env node

/**
 * Amsterdam Dashboard Kerncijfers Client
 * 
 * Fetches and processes data from Gemeente Amsterdam Onderzoek en Statistiek (BBGA)
 * Underlying API: https://onderzoek.amsterdam.nl/statistieken/api
 */

const BASE_API = 'https://onderzoek.amsterdam.nl/statistieken/api';

/**
 * Perform a GET request to the Amsterdam statistics API
 */
export async function fetchJson(endpoint) {
  const url = endpoint.startsWith('http') ? endpoint : `${BASE_API}${endpoint}`;
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'Antigravity-Agent/1.0 (Amsterdam Kerncijfers Client)',
      'Accept': 'application/json'
    }
  });

  if (!res.ok) {
    throw new Error(`API error ${res.status}: ${res.statusText} (${url})`);
  }
  return await res.json();
}

/**
 * Parse an interactive dashboard URL into its query parameters
 * Example: https://onderzoek.amsterdam.nl/interactief/dashboard-kerncijfers?tab=indicator&thema=bevolking&indicator=BEVTOTAAL&indeling=ggwgebieden&jaar=2026&gebied=GA01&taal=nl
 */
export function parseDashboardUrl(urlStr) {
  try {
    const parsed = new URL(urlStr);
    return {
      tab: parsed.searchParams.get('tab') || 'indicator',
      theme: parsed.searchParams.get('thema'),
      indicator: parsed.searchParams.get('indicator'),
      level: parsed.searchParams.get('indeling'),
      year: parsed.searchParams.get('jaar') ? parseInt(parsed.searchParams.get('jaar'), 10) : null,
      areaCode: parsed.searchParams.get('gebied'),
      lang: parsed.searchParams.get('taal') || 'nl'
    };
  } catch (err) {
    throw new Error(`Invalid URL: ${urlStr}`);
  }
}

/**
 * Fetch all indicators metadata
 */
export async function getIndicators() {
  return await fetchJson('/data/meta/indicators.json');
}

/**
 * Fetch all areas metadata
 */
export async function getAreas() {
  return await fetchJson('/data/meta/areas.json');
}

/**
 * Fetch statistical metadata overview
 */
export async function getStatsSummary() {
  return await fetchJson('/data/meta/stats.json');
}

/**
 * Fetch all data records for an indicator
 */
export async function getIndicatorData(indicator) {
  return await fetchJson(`/data/indicatoren/${encodeURIComponent(indicator)}.json`);
}

/**
 * Resolve kerncijfers for a dashboard URL or specific query parameters
 */
export async function resolveKerncijfers(options = {}) {
  let indicator = options.indicator;
  let areaCode = options.areaCode || options.gebied;
  let year = options.year ? parseInt(options.year, 10) : (options.jaar ? parseInt(options.jaar, 10) : null);
  let lang = options.lang || options.taal || 'nl';

  if (options.url) {
    const params = parseDashboardUrl(options.url);
    indicator = indicator || params.indicator;
    areaCode = areaCode || params.areaCode;
    year = year !== null && year !== undefined ? year : params.year;
    lang = params.lang || lang;
  }

  if (!indicator) {
    throw new Error('Indicator name/code is required (e.g. BEVTOTAAL)');
  }

  const [allIndicators, allAreas, data] = await Promise.all([
    getIndicators(),
    getAreas(),
    getIndicatorData(indicator)
  ]);

  const indicatorMeta = allIndicators.find(
    i => (i.name && i.name.toUpperCase() === indicator.toUpperCase()) ||
         (i.indicator && i.indicator.toUpperCase() === indicator.toUpperCase())
  ) || null;

  const areaMeta = areaCode ? (allAreas[areaCode] || Object.values(allAreas).find(a => a.code === areaCode)) : null;

  let records = data;
  if (areaCode) {
    records = records.filter(r => r.areaCode === areaCode);
  }
  if (year) {
    records = records.filter(r => r.year === year);
  }

  return {
    query: { indicator, areaCode, year, lang },
    indicatorMeta,
    areaMeta,
    totalRecords: records.length,
    records
  };
}

// CLI handler
async function runCli() {
  const args = process.argv.slice(2);
  if (args.length === 0 || args.includes('-h') || args.includes('--help')) {
    console.log(`
Gebruik:
  node amsterdam_kerncijfers.mjs <url>
  node amsterdam_kerncijfers.mjs --indicator <naam> [--gebied <code>] [--jaar <jaar>]
  node amsterdam_kerncijfers.mjs --search <zoekterm>

Voorbeelden:
  node amsterdam_kerncijfers.mjs "https://onderzoek.amsterdam.nl/interactief/dashboard-kerncijfers?tab=indicator&thema=bevolking&indicator=BEVTOTAAL&indeling=ggwgebieden&jaar=2026&gebied=GA01&taal=nl"
  node amsterdam_kerncijfers.mjs --indicator BEVTOTAAL --gebied GA01 --jaar 2026
  node amsterdam_kerncijfers.mjs --search bevolking
`);
    return;
  }

  if (args[0].startsWith('http://') || args[0].startsWith('https://')) {
    const res = await resolveKerncijfers({ url: args[0] });
    printResult(res);
    return;
  }

  let indicator = null;
  let gebied = null;
  let jaar = null;
  let search = null;
  let jsonOutput = false;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--indicator' && args[i + 1]) indicator = args[++i];
    else if (args[i] === '--gebied' && args[i + 1]) gebied = args[++i];
    else if (args[i] === '--jaar' && args[i + 1]) jaar = args[++i];
    else if (args[i] === '--search' && args[i + 1]) search = args[++i];
    else if (args[i] === '--json') jsonOutput = true;
  }

  if (search) {
    const indicators = await getIndicators();
    const term = search.toLowerCase();
    const matches = indicators.filter(i => 
      (i.name && i.name.toLowerCase().includes(term)) ||
      (i.label && i.label.toLowerCase().includes(term)) ||
      (i.definition && i.definition.toLowerCase().includes(term))
    );
    console.log(`Gevonden indicatoren voor "${search}" (${matches.length}):`);
    matches.slice(0, 20).forEach(m => {
      console.log(`- ${m.name}: ${m.label} (${m.themes?.join(', ')}) [eenheid: ${m.unit || 'n.v.t.'}]`);
    });
    return;
  }

  if (indicator) {
    const res = await resolveKerncijfers({ indicator, areaCode: gebied, year: jaar });
    if (jsonOutput) {
      console.log(JSON.stringify(res, null, 2));
    } else {
      printResult(res);
    }
  }
}

function printResult(res) {
  console.log('='.repeat(60));
  console.log('DASHBOARD KERNCIJFERS - GEMEENTE AMSTERDAM');
  console.log('='.repeat(60));
  if (res.indicatorMeta) {
    console.log(`\nIndicator: ${res.indicatorMeta.label} (${res.indicatorMeta.name})`);
    console.log(`Thema:     ${res.indicatorMeta.themes?.join(', ')}`);
    console.log(`Eenheid:   ${res.indicatorMeta.unit || 'n.v.t.'} (decimalen: ${res.indicatorMeta.decimals})`);
    console.log(`Bron:      ${res.indicatorMeta.source || 'n.v.t.'}`);
    console.log(`Definitie: ${res.indicatorMeta.definition}`);
  }

  if (res.areaMeta) {
    console.log(`\nGebied:    ${res.areaMeta.naam} (${res.areaMeta.code})`);
    console.log(`Type:      ${res.areaMeta.label || res.areaMeta.type}`);
    console.log(`Stadsdeel: ${res.areaMeta.stadsdeelNaam || 'n.v.t.'}`);
  }

  console.log(`\nResultaten (${res.records.length} records):`);
  console.table(res.records.map(r => ({
    Jaar: r.year,
    Gebiedscode: r.areaCode,
    Gebiedsnaam: r.areaName,
    Type: r.areaType,
    Waarde: r.value
  })));
}

if (process.argv[1] && process.argv[1].endsWith('amsterdam_kerncijfers.mjs')) {
  runCli().catch(err => {
    console.error('Fout:', err.message);
    process.exit(1);
  });
}
