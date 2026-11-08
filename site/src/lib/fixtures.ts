import ls from '../../fixtures/hats-ls.txt?raw';
import ps from '../../fixtures/hats-ps.txt?raw';
import { parseTable, type Table } from './table';

export const LS = parseTable(ls, 'hats ls');
export const PS = parseTable(ps, 'hats ps');

/** Reads one cell from a fixture, so the page never contradicts the tables it shows. */
export function cell({ headers, rows }: Table, header: string, ...key: string[]): string {
  const row = rows.find((cells) => key.every((value, index) => cells[index] === value));
  if (!row) throw new Error(`no fixture row for ${key.join(' ')}`);
  return row[headers.indexOf(header)];
}

const ACCOUNT = /^(.*?)(?: \((.*)\))?$/;

export const accountOf = (profile: string) => cell(LS, 'ACCOUNT', profile).match(ACCOUNT)![1];
export const orgOf = (profile: string): string | undefined => cell(LS, 'ACCOUNT', profile).match(ACCOUNT)![2];
