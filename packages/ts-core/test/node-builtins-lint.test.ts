import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const tsCoreSrcDir = path.resolve(__dirname, '../src');
const reactNativeSrcDir = path.resolve(__dirname, '../../react-native/src');

function getAllFiles(dir: string): string[] {
  const files: string[] = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...getAllFiles(fullPath));
    } else if (entry.isFile() && entry.name.endsWith('.ts')) {
      files.push(fullPath);
    }
  }
  return files;
}

describe('Zero Node.js Built-ins & Zero Buffer Verification', () => {
  const files = [...getAllFiles(tsCoreSrcDir), ...getAllFiles(reactNativeSrcDir)];

  test('verifies all files under ts-core/src and react-native/src have zero forbidden imports', () => {
    const forbiddenImportsRegex = /from\s+['"](node:.*|fs|path|crypto|stream|ws)['"]/g;

    for (const file of files) {
      const content = fs.readFileSync(file, 'utf8');
      const matches = content.match(forbiddenImportsRegex);
      assert.equal(
        matches,
        null,
        `File ${file} contains forbidden Node.js imports: ${matches?.join(', ')}`
      );
    }
  });

  test('verifies all files have zero usage of Node Buffer identifier', () => {
    // Matches identifier Buffer as a word, but not TypedArray or other words
    const bufferIdentifierRegex = /\bBuffer\b/g;

    for (const file of files) {
      const content = fs.readFileSync(file, 'utf8');
      const matches = content.match(bufferIdentifierRegex);
      assert.equal(
        matches,
        null,
        `File ${file} contains forbidden Node Buffer identifier: ${matches?.join(', ')}`
      );
    }
  });
});
