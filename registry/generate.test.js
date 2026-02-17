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

// ─── Validate Shared Constants ───────────────────────────────────────
console.log('\n5. Generated shared constants');
const sharedConstantsPath = join(ROOT, 'packages/shared/src/constants.ts');
assert(existsSync(sharedConstantsPath), 'constants.ts exists in packages/shared/src/');

const sharedTs = readFileSync(sharedConstantsPath, 'utf-8');
assert(sharedTs.includes('AUTO-GENERATED'), 'Shared constants has auto-generated header');
assert(sharedTs.includes('export const SKILL_IDS'), 'Shared constants exports SKILL_IDS');
assert(sharedTs.includes('export const AGENT_IDS'), 'Shared constants exports AGENT_IDS');
assert(sharedTs.includes('export const COPY'), 'Shared constants exports COPY');
assert(sharedTs.includes('export type FeatureStatus'), 'Shared constants exports FeatureStatus type');
assert(sharedTs.includes('export type FeatureCategory'), 'Shared constants exports FeatureCategory type');
assert(sharedTs.includes('export type SkillType'), 'Shared constants exports SkillType type');

// Verify all skill IDs are present
for (const skill of features.skills) {
  assert(sharedTs.includes(`${skill.id.toUpperCase()}: '${skill.id}'`),
    `Shared constants SKILL_IDS includes ${skill.id.toUpperCase()}`);
}

// Verify all agent IDs are present
for (const agent of features.agents) {
  assert(sharedTs.includes(`${agent.id.toUpperCase()}: '${agent.id}'`),
    `Shared constants AGENT_IDS includes ${agent.id.toUpperCase()}`);
}

// Verify copy data includes app name
assert(sharedTs.includes('"name": "Robo"'), 'Shared constants COPY includes app name');

// ─── Idempotency ────────────────────────────────────────────────────
console.log('\n6. Idempotency (run codegen twice)');
execSync('node registry/generate.js', { cwd: ROOT, stdio: 'pipe' });

const swift2 = readFileSync(swiftPath, 'utf-8');
const ts2 = readFileSync(tsPath, 'utf-8');
const html2 = readFileSync(join(ROOT, 'site/index.html'), 'utf-8');
const sharedTs2 = readFileSync(sharedConstantsPath, 'utf-8');

assert(swift === swift2, 'Swift output is identical after second run');
assert(ts === ts2, 'TS output is identical after second run');
assert(html === html2, 'HTML output is identical after second run (no double badges)');
assert(sharedTs === sharedTs2, 'Shared constants output is identical after second run');

// ─── P1: Swift string escaping ──────────────────────────────────────
console.log('\n7. Swift string escaping');

// Verify no unescaped special chars in Swift string literals
// Match all `"..."` inside static let/Skill/Agent declarations
const swiftStringLiterals = swift.match(/(?<=(?:static let \w+ = |id: |name: |tagline: |description: |icon: |color: |ogTitle: |ogDescription: ))"([^"]*)"/g) || [];
for (const literal of swiftStringLiterals) {
  const inner = literal.slice(1, -1); // strip outer quotes
  // Check no raw backslashes that aren't part of escape sequences
  const badBackslash = inner.match(/\\(?![\\nrt"])/);
  assert(!badBackslash, `No unescaped backslashes in Swift literal: ${literal.slice(0, 40)}`);
}

// Verify escaping works on strings that contain special chars
// The current data may not have them, but verify the mechanism:
// All quotes in source data should appear as \" in Swift
for (const agent of features.agents) {
  if (agent.description.includes('"')) {
    assert(swift.includes(agent.description.replace(/"/g, '\\"')),
      `Agent "${agent.name}" description quotes are escaped in Swift`);
  }
}
// em-dash (—) should pass through unchanged (valid UTF-8 in Swift)
for (const agent of features.agents) {
  if (agent.description.includes('—')) {
    assert(swift.includes('—'), `Em-dash passes through in Swift for agent "${agent.name}"`);
  }
}
assert(swiftStringLiterals.length > 0, `Found ${swiftStringLiterals.length} Swift string literals to validate`);

// ─── P2: Badge reversibility (status change simulation) ────────────
console.log('\n8. Badge reversibility');

// Simulate: change a coming_soon skill to active, re-run codegen, verify badge removed
import { writeFileSync as writeTmp } from 'fs';
const featuresPath = join(__dirname, 'features.json');
const originalFeatures = readFileSync(featuresPath, 'utf-8');

// Mutate: make "beacon" active
const mutated = JSON.parse(originalFeatures);
const beaconSkill = mutated.skills.find(s => s.id === 'beacon');
beaconSkill.status = 'active';
writeTmp(featuresPath, JSON.stringify(mutated, null, 2));

try {
  execSync('node registry/generate.js', { cwd: ROOT, stdio: 'pipe' });
  const htmlAfterChange = readFileSync(join(ROOT, 'site/index.html'), 'utf-8');
  assert(!htmlAfterChange.includes('BLE Beacons <span class="badge-coming-soon">Soon</span>'),
    'BLE Beacons badge REMOVED after status changed to active');
  assert(htmlAfterChange.includes('Motion Capture <span class="badge-coming-soon">Soon</span>'),
    'Motion Capture badge STILL PRESENT (unchanged)');

  // Verify Swift also updated
  const swiftAfterChange = readFileSync(swiftPath, 'utf-8');
  const activeLineAfter = swiftAfterChange.match(/static let activeSkillTypes.*=.*\[([^\]]*)\]/)?.[1] || '';
  assert(activeLineAfter.includes('.beacon'),
    'Swift activeSkillTypes now includes .beacon after status change');
} finally {
  // Restore original features.json
  writeTmp(featuresPath, originalFeatures);
  execSync('node registry/generate.js', { cwd: ROOT, stdio: 'pipe' });
}

// Verify restoration
const htmlRestored = readFileSync(join(ROOT, 'site/index.html'), 'utf-8');
assert(htmlRestored.includes('BLE Beacons <span class="badge-coming-soon">Soon</span>'),
  'BLE Beacons badge RESTORED after reverting features.json');

// ─── Summary ────────────────────────────────────────────────────────
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
