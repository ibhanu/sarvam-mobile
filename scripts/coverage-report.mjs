#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');

/**
 * Parse an LCOV file and return aggregate line, function, and branch metrics.
 * Optionally filters records using a file path predicate.
 */
function parseLcov(filePath, filterFn = () => true) {
  if (!fs.existsSync(filePath)) return null;
  const content = fs.readFileSync(filePath, 'utf8');
  const records = content.split('end_of_record');

  let linesFound = 0;
  let linesHit = 0;
  let funcsFound = 0;
  let funcsHit = 0;
  let branchesFound = 0;
  let branchesHit = 0;

  for (const record of records) {
    const lines = record.trim().split('\n');
    let sf = '';
    let lf = 0, lh = 0, fnf = 0, fnh = 0, brf = 0, brh = 0;
    for (const line of lines) {
      if (line.startsWith('SF:')) sf = line.slice(3).trim();
      else if (line.startsWith('LF:')) lf = parseInt(line.slice(3), 10) || 0;
      else if (line.startsWith('LH:')) lh = parseInt(line.slice(3), 10) || 0;
      else if (line.startsWith('FNF:')) fnf = parseInt(line.slice(4), 10) || 0;
      else if (line.startsWith('FNH:')) fnh = parseInt(line.slice(4), 10) || 0;
      else if (line.startsWith('BRF:')) brf = parseInt(line.slice(4), 10) || 0;
      else if (line.startsWith('BRH:')) brh = parseInt(line.slice(4), 10) || 0;
    }
    if (!sf || !filterFn(sf)) continue;
    linesFound += lf;
    linesHit += lh;
    funcsFound += fnf;
    funcsHit += fnh;
    branchesFound += brf;
    branchesHit += brh;
  }

  return {
    linesFound,
    linesHit,
    linePct: linesFound > 0 ? ((linesHit / linesFound) * 100).toFixed(1) : 'N/A',
    funcsFound,
    funcsHit,
    funcPct: funcsFound > 0 ? ((funcsHit / funcsFound) * 100).toFixed(1) : 'N/A',
    branchesFound,
    branchesHit,
    branchPct: branchesFound > 0 ? ((branchesHit / branchesFound) * 100).toFixed(1) : 'N/A',
  };
}

/**
 * Parse a JaCoCo CSV file and return aggregate line, method, and branch metrics.
 */
function parseJacocoCsv(filePath, filterFn = () => true) {
  if (!fs.existsSync(filePath)) return null;
  const content = fs.readFileSync(filePath, 'utf8').trim();
  const lines = content.split('\n');
  if (lines.length < 2) return null;

  const headers = lines[0].split(',');
  const pkgIdx = headers.indexOf('PACKAGE');
  const clsIdx = headers.indexOf('CLASS');
  const lineMissedIdx = headers.indexOf('LINE_MISSED');
  const lineCoveredIdx = headers.indexOf('LINE_COVERED');
  const methodMissedIdx = headers.indexOf('METHOD_MISSED');
  const methodCoveredIdx = headers.indexOf('METHOD_COVERED');
  const branchMissedIdx = headers.indexOf('BRANCH_MISSED');
  const branchCoveredIdx = headers.indexOf('BRANCH_COVERED');

  let linesMissed = 0, linesHit = 0;
  let funcsMissed = 0, funcsHit = 0;
  let branchesMissed = 0, branchesHit = 0;

  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(',');
    if (cols.length < headers.length) continue;
    const pkg = cols[pkgIdx];
    const cls = cols[clsIdx];
    if (!filterFn(pkg, cls)) continue;

    linesMissed += parseInt(cols[lineMissedIdx], 10) || 0;
    linesHit += parseInt(cols[lineCoveredIdx], 10) || 0;
    funcsMissed += parseInt(cols[methodMissedIdx], 10) || 0;
    funcsHit += parseInt(cols[methodCoveredIdx], 10) || 0;
    branchesMissed += parseInt(cols[branchMissedIdx], 10) || 0;
    branchesHit += parseInt(cols[branchCoveredIdx], 10) || 0;
  }

  const linesFound = linesMissed + linesHit;
  const funcsFound = funcsMissed + funcsHit;
  const branchesFound = branchesMissed + branchesHit;

  return {
    linesFound,
    linesHit,
    linePct: linesFound > 0 ? ((linesHit / linesFound) * 100).toFixed(1) : 'N/A',
    funcsFound,
    funcsHit,
    funcPct: funcsFound > 0 ? ((funcsHit / funcsFound) * 100).toFixed(1) : 'N/A',
    branchesFound,
    branchesHit,
    branchPct: branchesFound > 0 ? ((branchesHit / branchesFound) * 100).toFixed(1) : 'N/A',
  };
}

const targets = [
  {
    name: 'Android / Kotlin (`:sarvam-core`)',
    format: 'JaCoCo CSV/XML',
    reportPath: 'packages/kotlin/sarvam-core/build/reports/jacoco/test/jacocoTestReport.csv',
    load: () =>
      parseJacocoCsv(
        path.join(rootDir, 'packages/kotlin/sarvam-core/build/reports/jacoco/test/jacocoTestReport.csv'),
        (pkg) => !pkg.includes('generated')
      ),
  },
  {
    name: 'Android Audio (`:sarvam-android-audio`)',
    format: 'JaCoCo CSV/XML',
    reportPath: 'packages/kotlin/sarvam-android-audio/build/reports/jacoco/test/jacocoTestReport.csv',
    load: () =>
      parseJacocoCsv(
        path.join(rootDir, 'packages/kotlin/sarvam-android-audio/build/reports/jacoco/test/jacocoTestReport.csv')
      ),
  },
  {
    name: 'iOS / Swift (`Sarvam` + `SarvamAudio`)',
    format: 'LLVM LCOV',
    reportPath: 'packages/swift/coverage/lcov.info',
    load: () =>
      parseLcov(
        path.join(rootDir, 'packages/swift/coverage/lcov.info'),
        (sf) => !sf.includes('SarvamSpecGenerated.swift')
      ),
  },
  {
    name: 'TypeScript Core (`@sarvam/core`)',
    format: 'Node LCOV',
    reportPath: 'packages/ts-core/coverage/lcov.info',
    load: () =>
      parseLcov(
        path.join(rootDir, 'packages/ts-core/coverage/lcov.info'),
        (sf) => sf.startsWith('dist/esm/') && !sf.includes('sarvamSpecGenerated')
      ),
  },
  {
    name: 'React Native (`@sarvam/react-native`)',
    format: 'Node LCOV',
    reportPath: 'packages/react-native/coverage/lcov.info',
    load: () =>
      parseLcov(
        path.join(rootDir, 'packages/react-native/coverage/lcov.info'),
        (sf) => sf.startsWith('dist/esm/') && !sf.includes('sarvamSpecGenerated')
      ),
  },
  {
    name: 'Flutter / Dart Core (`sarvam`)',
    format: 'Dart LCOV',
    reportPath: 'packages/dart/sarvam/coverage/lcov.info',
    load: () =>
      parseLcov(
        path.join(rootDir, 'packages/dart/sarvam/coverage/lcov.info'),
        (sf) => !sf.includes('sarvam_spec_generated.dart')
      ),
  },
  {
    name: 'Flutter Audio (`sarvam_flutter_audio`)',
    format: 'Flutter LCOV',
    reportPath: 'packages/dart/sarvam_flutter_audio/coverage/lcov.info',
    load: () =>
      parseLcov(path.join(rootDir, 'packages/dart/sarvam_flutter_audio/coverage/lcov.info')),
  },
  {
    name: 'Reference BFF Proxy (`@sarvam/bff-proxy`)',
    format: 'Node LCOV',
    reportPath: 'proxy/coverage/lcov.info',
    load: () =>
      parseLcov(
        path.join(rootDir, 'proxy/coverage/lcov.info'),
        (sf) => sf.includes('src/') && !sf.includes('worker.ts') && !sf.includes('cli.ts')
      ),
  },
];

let totalLinesFound = 0;
let totalLinesHit = 0;
const rows = [];

for (const t of targets) {
  const stats = t.load();
  if (!stats) {
    rows.push({
      ...t,
      status: 'MISSING',
      lines: 'N/A',
      funcs: 'N/A',
      branches: 'N/A',
    });
    continue;
  }
  totalLinesFound += stats.linesFound;
  totalLinesHit += stats.linesHit;
  rows.push({
    ...t,
    status: 'OK',
    lines: `${stats.linePct}% (${stats.linesHit}/${stats.linesFound})`,
    funcs: stats.funcPct !== 'N/A' ? `${stats.funcPct}% (${stats.funcsHit}/${stats.funcsFound})` : 'N/A',
    branches: stats.branchPct !== 'N/A' ? `${stats.branchPct}% (${stats.branchesHit}/${stats.branchesFound})` : 'N/A',
    raw: stats,
  });
}

const overallLinePct = totalLinesFound > 0 ? ((totalLinesHit / totalLinesFound) * 100).toFixed(1) : 'N/A';

const mdLines = [
  '# Sarvam AI Mobile SDKs — Unified Code Coverage Report',
  '',
  '| Package / Module | Format | Line Coverage | Function / Method Coverage | Branch Coverage | Report Artifact |',
  '| :--- | :--- | :--- | :--- | :--- | :--- |',
  ...rows.map(
    (r) =>
      `| ${r.name} | ${r.format} | **${r.lines}** | ${r.funcs} | ${r.branches} | \`${r.reportPath}\` |`
  ),
  `| **Total Monorepo (Handwritten Runtime)** | **Combined** | **${overallLinePct}% (${totalLinesHit}/${totalLinesFound})** | — | — | — |`,
  '',
];

const markdown = mdLines.join('\n');
fs.writeFileSync(path.join(rootDir, 'coverage-summary.md'), markdown, 'utf8');
console.log(markdown);
