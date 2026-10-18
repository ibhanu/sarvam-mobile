#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const rootDir = resolve(__dirname, '..');

const isCheckMode = process.argv.includes('--check');

// 1. Read authoritative versions from .release-please-manifest.json
const manifestPath = resolve(rootDir, '.release-please-manifest.json');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));

const versions = {
  rust: manifest['packages/rust-core'] || '0.2.0',
  kotlin: manifest['packages/kotlin'] || '0.1.0',
  swift: manifest['packages/swift'] || '0.2.1',
  tsCore: manifest['packages/ts-core'] || '0.3.0',
  reactNative: manifest['packages/react-native'] || '0.3.0',
  dart: manifest['packages/dart/sarvam'] || '0.3.0',
  dartAudio: manifest['packages/dart/sarvam_flutter_audio'] || '0.2.1',
};

console.log(`[sync-readme-versions] Current target versions:`);
console.log(`  Rust Core:     ${versions.rust}`);
console.log(`  Kotlin:        ${versions.kotlin}`);
console.log(`  Swift:         ${versions.swift}`);
console.log(`  TypeScript:    ${versions.tsCore}`);
console.log(`  React Native:  ${versions.reactNative}`);
console.log(`  Dart (sarvam): ${versions.dart}`);
console.log(`  Dart Audio:    ${versions.dartAudio}`);

let driftedFiles = 0;

function updateFile(relativePath, updateFn) {
  const fullPath = resolve(rootDir, relativePath);
  let original;
  try {
    original = readFileSync(fullPath, 'utf8');
  } catch (err) {
    console.warn(`[sync-readme-versions] Skipping ${relativePath} (not found)`);
    return;
  }

  const updated = updateFn(original);
  if (original !== updated) {
    driftedFiles++;
    if (isCheckMode) {
      console.error(`[sync-readme-versions] DRIFT DETECTED: ${relativePath} has outdated version references!`);
    } else {
      writeFileSync(fullPath, updated, 'utf8');
      console.log(`[sync-readme-versions] Updated versions in ${relativePath}`);
    }
  } else {
    console.log(`[sync-readme-versions] Up to date: ${relativePath}`);
  }
}

// Update Root README.md
updateFile('README.md', (content) => {
  let c = content;
  // Rust Core badge
  c = c.replace(
    /badge\/Rust%20Core-[0-9a-zA-Z.-]+-DEA584\.svg/g,
    `badge/Rust%20Core-${versions.rust}-DEA584.svg`
  );
  // SwiftPM badge at top
  c = c.replace(
    /badge\/SwiftPM-[0-9a-zA-Z.-]+-orange\.svg/g,
    `badge/SwiftPM-${versions.swift}-orange.svg`
  );
  // Package table Rust crates.io badge
  c = c.replace(
    /badge\/crates\.io-[0-9a-zA-Z.-]+-orange\.svg/g,
    `badge/crates.io-${versions.rust}-orange.svg`
  );
  // Package table SwiftPM badge
  c = c.replace(
    /badge\/SwiftPM-v[0-9a-zA-Z.-]+-orange\.svg/g,
    `badge/SwiftPM-v${versions.swift}-orange.svg`
  );
  // Kotlin Quickstart dependencies
  c = c.replace(
    /implementation\("io\.github\.ibhanu:sarvam-core:[^"]+"\)/g,
    `implementation("io.github.ibhanu:sarvam-core:${versions.kotlin}")`
  );
  c = c.replace(
    /implementation\("io\.github\.ibhanu:sarvam-android-audio:[^"]+"\)/g,
    `implementation("io.github.ibhanu:sarvam-android-audio:${versions.kotlin}")`
  );
  // Swift Quickstart dependencies
  c = c.replace(
    /from: "[0-9a-zA-Z.-]+"\)/g,
    `from: "${versions.swift}")`
  );
  // Dart Quickstart dependencies
  c = c.replace(
    /sarvam: \^[0-9a-zA-Z.-]+/g,
    `sarvam: ^${versions.dart}`
  );
  c = c.replace(
    /sarvam_flutter_audio: \^[0-9a-zA-Z.-]+/g,
    `sarvam_flutter_audio: ^${versions.dartAudio}`
  );
  return c;
});

// Update packages/kotlin/README.md
updateFile('packages/kotlin/README.md', (content) => {
  let c = content;
  c = c.replace(
    /implementation\("io\.github\.ibhanu:sarvam-core:[^"]+"\)/g,
    `implementation("io.github.ibhanu:sarvam-core:${versions.kotlin}")`
  );
  c = c.replace(
    /implementation\("io\.github\.ibhanu:sarvam-android-audio:[^"]+"\)/g,
    `implementation("io.github.ibhanu:sarvam-android-audio:${versions.kotlin}")`
  );
  c = c.replace(
    /implementation 'io\.github\.ibhanu:sarvam-core:[^']+'/g,
    `implementation 'io.github.ibhanu:sarvam-core:${versions.kotlin}'`
  );
  c = c.replace(
    /implementation 'io\.github\.ibhanu:sarvam-android-audio:[^']+'/g,
    `implementation 'io.github.ibhanu:sarvam-android-audio:${versions.kotlin}'`
  );
  return c;
});

// Update packages/swift/README.md
updateFile('packages/swift/README.md', (content) => {
  let c = content;
  c = c.replace(
    /from: "[0-9a-zA-Z.-]+"\)/g,
    `from: "${versions.swift}")`
  );
  return c;
});

// Update packages/dart/sarvam/README.md
updateFile('packages/dart/sarvam/README.md', (content) => {
  let c = content;
  c = c.replace(
    /sarvam: \^[0-9a-zA-Z.-]+/g,
    `sarvam: ^${versions.dart}`
  );
  return c;
});

// Update packages/dart/sarvam_flutter_audio/README.md
updateFile('packages/dart/sarvam_flutter_audio/README.md', (content) => {
  let c = content;
  c = c.replace(
    /sarvam_flutter_audio: \^[0-9a-zA-Z.-]+/g,
    `sarvam_flutter_audio: ^${versions.dartAudio}`
  );
  return c;
});

// Update docs/snippets/kotlin/quickstart.md
updateFile('docs/snippets/kotlin/quickstart.md', (content) => {
  let c = content;
  c = c.replace(
    /implementation\("io\.github\.ibhanu:sarvam-core:[^"]+"\)/g,
    `implementation("io.github.ibhanu:sarvam-core:${versions.kotlin}")`
  );
  c = c.replace(
    /implementation\("io\.github\.ibhanu:sarvam-android-audio:[^"]+"\)/g,
    `implementation("io.github.ibhanu:sarvam-android-audio:${versions.kotlin}")`
  );
  return c;
});

// Update packages/kotlin/samples/android-voice-demo/README.md
updateFile('packages/kotlin/samples/android-voice-demo/README.md', (content) => {
  let c = content;
  c = c.replace(
    /implementation\("io\.github\.ibhanu:sarvam-core:[^"]+"\)/g,
    `implementation("io.github.ibhanu:sarvam-core:${versions.kotlin}")`
  );
  c = c.replace(
    /implementation\("io\.github\.ibhanu:sarvam-android-audio:[^"]+"\)/g,
    `implementation("io.github.ibhanu:sarvam-android-audio:${versions.kotlin}")`
  );
  return c;
});

if (isCheckMode && driftedFiles > 0) {
  console.error(`\n[sync-readme-versions] Error: Found ${driftedFiles} file(s) with outdated versions. Run 'npm run sync:versions' to fix.`);
  process.exit(1);
} else if (driftedFiles > 0) {
  console.log(`\n[sync-readme-versions] Successfully synchronized ${driftedFiles} file(s).`);
} else {
  console.log(`\n[sync-readme-versions] All README version references are already up to date.`);
}
