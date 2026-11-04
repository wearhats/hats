export const SHIPPED = 'Shipped';
export const EXPECTED = 'Expected, being verified';

export type Status = { label: typeof SHIPPED | typeof EXPECTED; scope?: string };

export const shipped = (scope?: string): Status => ({ label: SHIPPED, scope });
export const expected = (scope?: string): Status => ({ label: EXPECTED, scope });
