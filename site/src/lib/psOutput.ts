export type PsTable = { headers: string[]; rows: string[][] };

export const NO_INSTANCES = 'No running Claude instances.';

export function parsePs(source: string): PsTable {
  const [header, ...lines] = source.trimEnd().split('\n');
  const headers = header.split(/\s{2,}/);
  const rows = lines.map((line) => line.split(/\s{2,}/));
  for (const row of rows) {
    if (row.length !== headers.length) throw new Error(`hats ps fixture: "${row.join(' ')}" doesn't have ${headers.length} columns`);
  }
  return { headers, rows };
}

/** The same rule as Output.printTable: each column is as wide as its widest cell, joined by two spaces, the last unpadded. */
export function layoutCells(cells: string[], widths: number[]): string[] {
  return cells.map((cell, index) => (index === cells.length - 1 ? cell : `${cell.padEnd(widths[index])}  `));
}

export function columnWidths({ headers, rows }: PsTable): number[] {
  return headers.map((header, column) => Math.max(header.length, ...rows.map((row) => row[column].length)));
}

export const onlyProfile = (table: PsTable, profile: string): PsTable => ({
  headers: table.headers,
  rows: table.rows.filter(([name]) => name === profile),
});
