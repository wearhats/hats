export type Table = { headers: string[]; rows: string[][] };

/** Splits `hats ls` or `hats ps` output into cells. Cells never hold two spaces in a row, so two or more mark a column break. */
export function parseTable(source: string, name: string): Table {
  const [header, ...lines] = source.trimEnd().split('\n');
  const headers = header.split(/\s{2,}/);
  const rows = lines.map((line) => line.split(/\s{2,}/));
  for (const row of rows) {
    if (row.length !== headers.length) throw new Error(`${name} fixture: "${row.join(' ')}" doesn't have ${headers.length} columns`);
  }
  return { headers, rows };
}

/** The same rule as Output.printTable: each column is as wide as its widest cell, joined by two spaces, the last unpadded. */
export function layoutRows({ headers, rows }: Table): string[][] {
  const widths = headers.map((header, column) => Math.max(header.length, ...rows.map((row) => row[column].length)));
  return [headers, ...rows].map((cells) =>
    cells.map((cell, index) => (index === cells.length - 1 ? cell : `${cell.padEnd(widths[index])}  `)),
  );
}
