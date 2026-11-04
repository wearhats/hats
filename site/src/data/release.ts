import manifestSource from '../../../.release-please-manifest.json?raw';
import readme from '../../../README.md?raw';

function parseVersion(source: string): string {
  const version = JSON.parse(source)['.'];
  if (typeof version !== 'string') throw new Error('.release-please-manifest.json has no version for "."');
  return version;
}

function parseTestedWith(source: string) {
  const match = source.match(/^Tested with Claude Desktop (\S+), Claude Code (\S+) and macOS (\S+?)\.$/m);
  if (!match) throw new Error('README.md has no parseable "Tested with" line');
  const [, desktop, code, macos] = match;
  return { desktop, code, macos };
}

export const VERSION = parseVersion(manifestSource);
export const TESTED_WITH = parseTestedWith(readme);
