// Public issue #2 tripwire: the bundled daemon's launchd plist carries a
// static PATH that launchd never $HOME-expands, so a native-installer
// `claude` in ~/.local/bin was invisible to both the health-card probe
// (bare-name `--version` spawn → ENOENT) and `which`-based resolution — the
// CLI card said "not installed" on a machine where `claude doctor` was
// clean. Both paths must fall back to probing the known home-relative
// install directories by absolute path. All three tests VERIFIED TO FAIL
// against the pre-fix service.mjs (2026-08-18).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Store } from '../src/db.mjs';
import { ModelDeckService } from '../src/service.mjs';

function fixture(options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'modeldeck-toolpath-'));
  // A stand-in for ~/.local/bin holding a real executable file, since the
  // fallback probe checks the filesystem (X_OK), not the exec fake.
  const localBin = path.join(root, 'home', '.local', 'bin');
  fs.mkdirSync(localBin, { recursive: true });
  const nativeClaude = path.join(localBin, 'claude-fixture');
  fs.writeFileSync(nativeClaude, '#!/bin/sh\n', { mode: 0o755 });
  const store = new Store(':memory:');
  store.saveSettings({ claudeManaged: true, codexManaged: true });
  const enoent = () => {
    const error = new Error('spawn ENOENT');
    error.code = 'ENOENT';
    return error;
  };
  const service = new ModelDeckService(store, {
    claudePath: 'claude-fixture',
    codexPath: 'codex-fixture',
    claudeActiveLink: path.join(root, 'active', '.claude'),
    codexActiveLink: path.join(root, 'active', '.codex'),
    claudeProfilesDir: path.join(root, 'profiles'),
    codexProfilesDir: path.join(root, 'codex-profiles'),
    toolPathFallbackDirs: [localBin],
    platform: 'linux',
    listProviderProcesses: async () => [],
    registryFetch: async () => ({ ok: true, json: async () => ({ version: '9.9.9' }) }),
    // The daemon's restricted PATH: bare names and `which` both miss, only
    // the absolute fallback path answers `--version`.
    exec: async (binary, args) => {
      if (binary === '/usr/bin/which') throw enoent();
      if (args?.[0] === '--version') {
        if (binary === nativeClaude) return { stdout: 'Claude Code 2.1.220' };
        throw enoent();
      }
      return { stdout: '' };
    },
    ...options,
  });
  return {
    root, localBin, nativeClaude, store, service,
    close() { store.close(); fs.rmSync(root, { recursive: true, force: true }); },
  };
}

test('health probe reports a native-installer CLI the daemon PATH cannot see', async (t) => {
  const data = fixture();
  t.after(() => data.close());
  const tools = await data.service.probeTools();
  assert.equal(tools.tools.claude.installed, true);
  assert.equal(tools.tools.claude.version, '2.1.220');
  // Codex has no fallback install in this fixture and stays honestly absent.
  assert.equal(tools.tools.codex.installed, false);
});

test('toolExecutablePath falls back to the install dirs when `which` misses', async (t) => {
  const data = fixture({
    exec: async (binary) => {
      if (binary === '/usr/bin/which') {
        const error = new Error('which exited 1');
        error.code = 1;
        throw error;
      }
      return { stdout: '' };
    },
  });
  t.after(() => data.close());
  assert.equal(await data.service.toolExecutablePath('claude-fixture'), data.nativeClaude);
});

test('a CLI absent from PATH and the fallback dirs still reports not installed', async (t) => {
  const data = fixture();
  t.after(() => data.close());
  await assert.rejects(
    data.service.toolExecutablePath('codex-fixture'),
    /codex-fixture is not installed/,
  );
  const tools = await data.service.probeTools();
  assert.match(tools.tools.codex.error, /codex-fixture is not installed/);
});

// Second sighting (2026-09-11): login resolved the CLI through the fallback
// and succeeded, then "I've Signed In — Verify" spawned the bare name and
// reported "Claude Code is not installed". Every daemon-side spawn — verify
// for both providers, and Claude renewal — must hand the adapter the same
// resolved executable the login step used. All three VERIFIED TO FAIL
// against the pre-fix service.mjs.
function profileHome(root, name) {
  const home = path.join(root, 'profiles', name);
  fs.mkdirSync(home, { recursive: true, mode: 0o700 });
  fs.chmodSync(home, 0o700);
  return home;
}

test('verify hands the Claude adapter the resolved native-installer path', async (t) => {
  let seenPath = null;
  const data = fixture({
    readClaudeAuth: async ({ claudePath }) => {
      seenPath = claudePath;
      return { authenticated: true, identity: 'user@example.invalid' };
    },
  });
  t.after(() => data.close());
  const account = data.store.saveAccount({
    provider: 'claude', label: 'Native', profileRef: profileHome(data.root, 'native'),
  });
  const result = await data.service.verifyAccount(account.id);
  assert.equal(result.authenticated, true);
  assert.equal(seenPath, data.nativeClaude);
});

test('verify hands the Codex adapter the resolved fallback path', async (t) => {
  const data = fixture();
  t.after(() => data.close());
  const nativeCodex = path.join(data.localBin, 'codex-fixture');
  fs.writeFileSync(nativeCodex, '#!/bin/sh\n', { mode: 0o755 });
  let seenBinary = null;
  data.service.readCodexAuth = async ({ binary }) => {
    seenBinary = binary;
    return { authenticated: true, identity: 'user@example.invalid' };
  };
  const account = data.store.saveAccount({
    provider: 'codex', label: 'Native', profileRef: profileHome(data.root, 'codex-native'),
  });
  await data.service.verifyAccount(account.id);
  assert.equal(seenBinary, nativeCodex);
});

test('Claude renewal spawns the resolved native-installer path, not the bare name', async (t) => {
  const spawned = [];
  const data = fixture({
    exec: async (binary) => {
      spawned.push(binary);
      // The daemon's restricted PATH: only an absolute path spawns.
      if (!path.isAbsolute(binary)) throw Object.assign(new Error('spawn ENOENT'), { code: 'ENOENT' });
      return { stdout: '' };
    },
  });
  t.after(() => data.close());
  const profileRef = profileHome(data.root, 'renewal');
  await data.service.runClaudeRenewalCli(['--version'], profileRef);
  assert.deepEqual(spawned, ['claude-fixture', data.nativeClaude]);
});
