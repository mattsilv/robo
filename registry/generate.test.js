#!/usr/bin/env node

/**
 * Tests for registry codegen — validates output correctness and idempotency.
 * Usage: node registry/generate.test.js
 */

import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');

let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (condition) {
    passed++;
    console.log(`  ✓ ${msg}`);
  } else {
    failed++;
    console.error(`  ✗ ${msg}`);
  }
}

// ─── Run codegen ────────────────────────────────────────────────────
console.log('Running codegen...');
execSync('node registry/generate.js', { cwd: ROOT, stdio: 'pipe' });

// ─── Validate source files ─────────────────────────────────────────
console.log('\n1. Source files');
const features = JSON.parse(readFileSync(join(__dirname, 'features.json'), 'utf-8'));
const copy = JSON.parse(readFileSync(join(__dirname, 'copy.json'), 'utf-8'));

assert(features.skills.length > 0, `features.json has ${features.skills.length} skills`);
assert(features.agents.length > 0, `features.json has ${features.agents.length} agents`);
assert(copy.app.name === 'Robo', 'copy.json app name is Robo');
assert(copy.tabs.capture === 'Capture', 'copy.json has tab labels');

// Validate all skills have required fields
for (const skill of features.skills) {
  assert(skill.id && skill.name && skill.status && skill.category,
    `skill "${skill.id}" has all required fields`);
  assert(['active', 'coming_soon', 'disabled'].includes(skill.status),
    `skill "${skill.id}" has valid status: ${skill.status}`);
}

// ─── Validate Swift output ──────────────────────────────────────────
console.log('\n2. Generated Swift');
const swiftPath = join(ROOT, 'ios/Robo/Generated/FeatureRegistry.swift');
assert(existsSync(swiftPath), 'FeatureRegistry.swift exists');

const swift = readFileSync(swiftPath, 'utf-8');
assert(swift.includes('AUTO-GENERATED'), 'Swift has auto-generated header');
assert(swift.includes('enum FeatureRegistry'), 'Swift has FeatureRegistry enum');
assert(swift.includes('enum AppCopy'), 'Swift has AppCopy enum');
assert(swift.includes('static let activeSkillTypes'), 'Swift has activeSkillTypes');

// Every active skill with a skillType should be in activeSkillTypes
const activeWithType = features.skills.filter(s => s.status === 'active' && s.skillType);
for (const skill of activeWithType) {
  assert(swift.includes(`.${skill.skillType}`),
    `Swift activeSkillTypes includes .${skill.skillType}`);
}

// Coming soon skills should NOT be in activeSkillTypes
const comingSoonWithType = features.skills.filter(s => s.status === 'coming_soon' && s.skillType);
const activeSkillTypesLine = swift.match(/static let activeSkillTypes.*=.*\[([^\]]*)\]/)?.[1] || '';
for (const skill of comingSoonWithType) {
  assert(!activeSkillTypesLine.includes(`.${skill.skillType}`) ||
    activeWithType.some(a => a.skillType === skill.skillType),
    `Swift activeSkillTypes does NOT include coming_soon .${skill.skillType}`);
}

// Tab labels from copy.json
assert(swift.includes(`static let capture = "${copy.tabs.capture}"`), 'Swift has capture tab label');
assert(swift.includes(`static let history = "${copy.tabs.history}"`), 'Swift has history tab label');

// ─── Validate TypeScript output ─────────────────────────────────────
console.log('\n3. Generated TypeScript');
const tsPath = join(ROOT, 'workers/src/generated/features.ts');
assert(existsSync(tsPath), 'features.ts exists');

const ts = readFileSync(tsPath, 'utf-8');
assert(ts.includes('AUTO-GENERATED'), 'TS has auto-generated header');
assert(ts.includes('export const skills'), 'TS exports skills');
assert(ts.includes('export const agents'), 'TS exports agents');
assert(ts.includes('export const copy'), 'TS exports copy');
assert(ts.includes('export const activeSkills'), 'TS exports activeSkills');

// Skill count matches
const tsSkillCount = (ts.match(/"id":/g) || []).length;
const expectedCount = features.skills.length + features.agents.length;
assert(tsSkillCount === expectedCount, `TS has ${tsSkillCount} id entries (expected ${expectedCount})`);

// ─── Validate Landing Page ──────────────────────────────────────────
console.log('\n4. Landing page badges');
const html = readFileSync(join(ROOT, 'site/index.html'), 'utf-8');

const comingSoon = features.skills.filter(s => s.status === 'coming_soon');
for (const skill of comingSoon) {
  assert(html.includes(`${skill.name} <span class="badge-coming-soon">Soon</span>`),
    `Landing page has "Soon" badge for ${skill.name}`);
}

const activeSkills = features.skills.filter(s => s.status === 'active');
for (const skill of activeSkills) {
  // Active skills should NOT have a badge
  const hasBadge = html.includes(`${skill.name} <span class="badge-coming-soon">`);
  assert(!hasBadge, `Active skill "${skill.name}" does NOT have a "Soon" badge`);
}

assert(html.includes('.badge-coming-soon'), 'Landing page has badge CSS');

// ─── Idempotency ────────────────────────────────────────────────────
console.log('\n5. Idempotency (run codegen twice)');
execSync('node registry/generate.js', { cwd: ROOT, stdio: 'pipe' });

const swift2 = readFileSync(swiftPath, 'utf-8');
const ts2 = readFileSync(tsPath, 'utf-8');
const html2 = readFileSync(join(ROOT, 'site/index.html'), 'utf-8');

assert(swift === swift2, 'Swift output is identical after second run');
assert(ts === ts2, 'TS output is identical after second run');
assert(html === html2, 'HTML output is identical after second run (no double badges)');

// ─── Summary ────────────────────────────────────────────────────────
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
