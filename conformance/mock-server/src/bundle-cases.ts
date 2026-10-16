import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as YAML from 'yaml';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Find mock-server package directory, then navigate to conformance/cases
function getCasesDirectory(): string {
  let curr = __dirname;
  while (curr !== path.dirname(curr)) {
    if (fs.existsSync(path.join(curr, 'package.json'))) {
      const parentCases = path.resolve(curr, '../cases');
      if (fs.existsSync(parentCases)) {
        return parentCases;
      }
    }
    curr = path.dirname(curr);
  }
  return path.resolve(__dirname, '../../cases');
}

export const casesDir = getCasesDirectory();
export const outputFile = path.join(casesDir, 'all-cases.json');

export interface ConformanceBundle {
  version: string;
  generatedAt: string;
  totalCases: number;
  categories: {
    rest: number;
    sse: number;
    ws: number;
  };
  cases: Array<{
    id: string;
    category: 'rest' | 'sse' | 'ws';
    [key: string]: unknown;
  }>;
}

export function buildConformanceBundle(): ConformanceBundle {
  const subdirs = ['rest', 'sse', 'ws'] as const;
  const cases: ConformanceBundle['cases'] = [];
  const categories = {
    rest: 0,
    sse: 0,
    ws: 0,
  };

  const seenIds = new Set<string>();

  for (const subdir of subdirs) {
    const dirPath = path.join(casesDir, subdir);
    if (!fs.existsSync(dirPath)) {
      continue;
    }

    const files = fs.readdirSync(dirPath).filter((f) => f.endsWith('.yaml') || f.endsWith('.yml'));
    files.sort();

    for (const file of files) {
      const fullPath = path.join(dirPath, file);
      const rawContent = fs.readFileSync(fullPath, 'utf8');
      const parsed = YAML.parse(rawContent);

      if (!parsed || typeof parsed !== 'object') {
        throw new Error(`Invalid YAML case in ${fullPath}: root must be an object`);
      }

      if (!parsed.id || typeof parsed.id !== 'string') {
        throw new Error(`Missing or invalid 'id' in ${fullPath}`);
      }

      if (seenIds.has(parsed.id)) {
        throw new Error(`Duplicate case id '${parsed.id}' in ${fullPath}`);
      }
      seenIds.add(parsed.id);

      if (parsed.category !== subdir) {
        throw new Error(
          `Case '${parsed.id}' has category '${parsed.category}', expected '${subdir}' based on folder`,
        );
      }

      categories[subdir]++;
      cases.push(parsed);
    }
  }

  const bundle: ConformanceBundle = {
    version: '0.1.0',
    generatedAt: new Date().toISOString(),
    totalCases: cases.length,
    categories,
    cases,
  };

  fs.writeFileSync(outputFile, JSON.stringify(bundle, null, 2) + '\n', 'utf8');
  console.log(`[Conformance] Bundled ${bundle.totalCases} cases (${categories.rest} rest, ${categories.sse} sse, ${categories.ws} ws) -> ${outputFile}`);

  return bundle;
}

// When executed directly via tsx/node
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  buildConformanceBundle();
}
