import fs from 'node:fs';
import path from 'node:path';

export const SHARED_TRANSCRIPT_ENTRY_LIMIT = 20_000;

function unsafePath() {
  return Object.assign(new Error('Unsafe transcript directory'), { code: 'UNSAFE_PATH' });
}

function directoryIsSafe(stat) {
  return stat?.isDirectory() && !stat.isSymbolicLink()
    && (!process.getuid || stat.uid === process.getuid()) && (stat.mode & 0o022) === 0;
}

async function lstat(file) {
  try { return await fs.promises.lstat(file); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}

function lstatSync(file) {
  try { return fs.lstatSync(file); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}

// Mutations run without an event-loop yield between checking every ancestor
// and the exclusive write/unlink. Other daemon tasks cannot swap a checked
// directory for a symlink in that interval. As with other profile operations,
// the current user and their separate processes remain trusted.
function directorySync(root, parts, create = false) {
  if (!directoryIsSafe(lstatSync(root))) throw unsafePath();
  let current = root;
  for (const part of parts) {
    current = path.join(current, part);
    let stat = lstatSync(current);
    if (!stat && create) {
      try { fs.mkdirSync(current, { mode: 0o700 }); }
      catch (error) { if (error.code !== 'EEXIST') throw error; }
      stat = lstatSync(current);
    }
    if (!stat) return null;
    if (!directoryIsSafe(stat)) throw unsafePath();
  }
  return current;
}

function sameLink(stat, record) {
  return stat?.isSymbolicLink() && record?.ino === stat.ino
    && record.dev === stat.dev && record.birthtimeMs === stat.birthtimeMs;
}

// Check every component with lstat, including before each mutation. Never
// recurse through a profile, projects directory, or project slug symlink.
async function directory(root, parts) {
  if (!directoryIsSafe(await lstat(root))) throw unsafePath();
  let current = root;
  for (const part of parts) {
    current = path.join(current, part);
    const stat = await lstat(current);
    if (!stat) return null;
    if (!directoryIsSafe(stat)) throw unsafePath();
  }
  return current;
}

async function context(profilesDir, profileRef, maxEntries, provider = 'claude', ownedLinks = {}) {
  if (!profilesDir || !profileRef) throw unsafePath();
  if (!directoryIsSafe(await lstat(path.resolve(profilesDir)))) throw unsafePath();
  const root = await fs.promises.realpath(profilesDir);
  if (await fs.promises.realpath(path.dirname(profileRef)) !== root) throw unsafePath();
  const profile = path.basename(profileRef);
  if (profile.startsWith('.')) throw unsafePath();
  if (!await directory(root, [profile])) throw unsafePath();
  if (!['claude', 'codex'].includes(provider)) throw unsafePath();
  return {
    root, profile, provider,
    ownedLinks: { ...ownedLinks },
    limit: Number.isSafeInteger(maxEntries) && maxEntries > 0
      ? Math.min(maxEntries, SHARED_TRANSCRIPT_ENTRY_LIMIT) : SHARED_TRANSCRIPT_ENTRY_LIMIT,
    examined: 0, created: 0, pruned: 0, sharedTranscripts: 0,
  };
}

async function entries(ctx, parts, visit) {
  const parent = await directory(ctx.root, parts);
  if (!parent) return;
  const stream = await fs.promises.opendir(parent);
  for await (const entry of stream) {
    if (ctx.examined >= ctx.limit) {
      throw Object.assign(new Error('Transcript entry limit reached'), { code: 'ENTRY_LIMIT' });
    }
    ctx.examined += 1;
    await visit(entry);
  }
}

async function transcripts(ctx, profile, visit) {
  const layouts = ctx.provider === 'claude'
    ? [['projects', [/.+/], /\.jsonl$/]]
    : [['sessions', [/^\d{4}$/, /^\d{2}$/, /^\d{2}$/], /^rollout-.*\.jsonl$/],
      ['archived_sessions', [], /\.jsonl$/]];
  async function walk(parts, levels, filePattern) {
    await entries(ctx, [profile, ...parts], async (entry) => {
      if (levels.length) {
        if (entry.isDirectory() && !entry.isSymbolicLink() && levels[0].test(entry.name)) {
          await walk([...parts, entry.name], levels.slice(1), filePattern);
        }
      } else if (filePattern.test(entry.name)) await visit([...parts, entry.name]);
    });
  }
  for (const [name, levels, filePattern] of layouts) await walk([name], levels, filePattern);
}

// Containment is necessary but does not prove ownership. Pruning also requires
// the daemon's recorded target and symlink identity to match the current link.
function sharedTarget(ctx, parts, target) {
  if (path.isAbsolute(target)) return null;
  const destination = path.join(ctx.root, ctx.profile, ...parts);
  const source = path.resolve(path.dirname(destination), target);
  const relative = path.relative(ctx.root, source).split(path.sep);
  const [profile, ...rest] = relative;
  if (!profile || profile.startsWith('.') || profile === ctx.profile
      || rest.length !== parts.length || rest.some((part, index) => part !== parts[index])) return null;
  return target === path.relative(path.dirname(destination), source) ? relative : null;
}

function outcome(ctx, error) {
  const code = /^[A-Z_]+$/.test(error?.code) ? error.code : 'IO_ERROR';
  return {
    examined: ctx?.examined ?? 0,
    created: ctx?.created ?? 0,
    pruned: ctx?.pruned ?? 0,
    ownedLinks: ctx?.ownedLinks,
    ...(!error ? { sharedTranscripts: ctx.sharedTranscripts } : {}),
    ...(error ? { warning: code === 'ENTRY_LIMIT'
      ? `Transcript sharing reached its ${ctx.limit}-entry safety limit; some past conversations remain unlinked (ENTRY_LIMIT).`
      : `Some past conversations could not be linked (${code}). Retry account activation to reconcile them.` } : {}),
  };
}

async function inspectLinks(ctx, prune) {
  const seen = new Set();
  await transcripts(ctx, ctx.profile, async (parts) => {
    const parentParts = [ctx.profile, ...parts.slice(0, -1)];
    if (!await directory(ctx.root, parentParts)) return;
    const file = path.join(ctx.root, ctx.profile, ...parts);
    const stat = await lstat(file);
    const key = parts.join('/');
    seen.add(key);
    if (!stat?.isSymbolicLink()) {
      delete ctx.ownedLinks[key];
      return;
    }
    const target = await fs.promises.readlink(file);
    const recorded = ctx.ownedLinks[key];
    const owned = recorded?.target === target && sameLink(stat, recorded);
    if (!owned) delete ctx.ownedLinks[key];
    const sourceParts = sharedTarget(ctx, parts, target);
    if (!sourceParts) return;
    const parent = await directory(ctx.root, sourceParts.slice(0, -1));
    const sourceStat = parent ? await lstat(path.join(ctx.root, ...sourceParts)) : null;
    if (!sourceStat && prune && owned) {
      const sourceParent = directorySync(ctx.root, sourceParts.slice(0, -1));
      if ((!sourceParent || !lstatSync(path.join(ctx.root, ...sourceParts)))
          && directorySync(ctx.root, parentParts)
          && sameLink(lstatSync(file), recorded)
          && fs.readlinkSync(file) === target) {
        fs.unlinkSync(file);
        delete ctx.ownedLinks[key];
        ctx.pruned += 1;
      }
    } else if (sourceStat?.isFile()) {
      ctx.sharedTranscripts += 1;
    }
  });
  for (const key of Object.keys(ctx.ownedLinks)) {
    if (!seen.has(key)) delete ctx.ownedLinks[key];
  }
}

// No transcript bytes are read or copied. The bound counts directory entries
// too, so a tree full of unrelated files cannot turn activation into a crawl.
export async function reconcileSharedTranscripts({ profilesDir, profileRef, maxEntries, provider, ownedLinks } = {}) {
  let ctx;
  try {
    ctx = await context(profilesDir, profileRef, maxEntries, provider, ownedLinks);
    await inspectLinks(ctx, true);
    await entries(ctx, [], async (profile) => {
      if (!profile.isDirectory() || profile.isSymbolicLink()
          || profile.name.startsWith('.') || profile.name === ctx.profile) return;
      await transcripts(ctx, profile.name, async (parts) => {
        const sourceParent = [profile.name, ...parts.slice(0, -1)];
        if (!directorySync(ctx.root, sourceParent)) return;
        const source = path.join(ctx.root, profile.name, ...parts);
        if (!lstatSync(source)?.isFile()) return;
        if (!directorySync(ctx.root, [ctx.profile])) throw unsafePath();
        const parent = directorySync(ctx.root, [ctx.profile, ...parts.slice(0, -1)], true);
        const destination = path.join(parent, parts.at(-1));
        if (lstatSync(destination)) return;
        try {
          const target = path.relative(parent, source);
          fs.symlinkSync(target, destination);
          // The write is synchronous with the checks above, so another daemon
          // task cannot swap the parent in between. Re-verify anyway: if the
          // parent is no longer a safe managed directory, the link landed
          // somewhere else and is removed before anything records it.
          try {
            directorySync(ctx.root, [ctx.profile, ...parts.slice(0, -1)]);
          } catch (error) {
            try { fs.unlinkSync(destination); } catch {}
            throw error;
          }
          ctx.created += 1;
          ctx.sharedTranscripts += 1;
          const stat = lstatSync(destination);
          if (stat?.isSymbolicLink() && fs.readlinkSync(destination) === target) {
            ctx.ownedLinks[parts.join('/')] = { target, ino: stat.ino, dev: stat.dev, birthtimeMs: stat.birthtimeMs };
          }
        } catch (error) {
          // Exclusive creation preserves a conversation/link that appeared
          // after lstat. No replacement, chmod, or rename of a transcript.
          if (error.code !== 'EEXIST') throw error;
        }
      });
    });
    return outcome(ctx);
  } catch (error) {
    return outcome(ctx, error);
  }
}

export async function sharedTranscriptState(options = {}) {
  let ctx;
  try {
    ctx = await context(options.profilesDir, options.profileRef, options.maxEntries, options.provider);
    await inspectLinks(ctx, false);
    return { sharedTranscripts: ctx.sharedTranscripts };
  } catch (error) {
    return { sharedTranscriptsWarning: outcome(ctx, error).warning };
  }
}
