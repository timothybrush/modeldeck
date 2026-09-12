import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

// Only replace our complete marked block; never follow a shell-config symlink.
export async function updateProviderShellHook({ target, provider, envFile, remove = false }) {
  const name = provider === 'claude' ? 'Claude' : 'Codex';
  const begin = `# >>> ModelDeck ${name} identity switching >>>`;
  const end = `# <<< ModelDeck ${name} identity switching <<<`;
  let source = '';
  let mode = 0o600;
  try {
    const stat = await fs.promises.lstat(target);
    if (!stat.isFile()) throw new Error('The shell configuration must be a real file.');
    source = await fs.promises.readFile(target, 'utf8');
    mode = stat.mode & 0o777;
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const lines = source.split('\n');
  const first = lines.indexOf(begin);
  const last = lines.indexOf(end);
  if ((first === -1) !== (last === -1) || (first !== -1 && last < first)
      || lines.filter((line) => line === begin).length > 1
      || lines.filter((line) => line === end).length > 1) {
    throw new Error('The ModelDeck shell block is incomplete. Restore it before changing account switching.');
  }
  const block = remove ? [] : [begin, `if [ -f ${shellQuote(envFile)} ]; then`, `  . ${shellQuote(envFile)}`, 'fi', end];
  if (first !== -1) lines.splice(first, last - first + 1, ...block);
  else if (!remove) lines.push(...block, '');
  const content = lines.join('\n');
  if (content === source) return;
  const temporary = `${target}.modeldeck-${crypto.randomUUID()}`;
  try {
    await fs.promises.mkdir(path.dirname(target), { recursive: true });
    await fs.promises.writeFile(temporary, content, { mode });
    await fs.promises.rename(temporary, target);
  } finally {
    await fs.promises.rm(temporary, { force: true });
  }
}
