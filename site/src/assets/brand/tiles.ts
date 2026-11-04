import work from './tile-work.svg?raw';
import personal from './tile-personal.svg?raw';
import acme from './tile-acme.svg?raw';
import fallback from './tile-default.svg?raw';
import claudeApp from './tile-claude-app.svg?raw';

export const TILES = { work, personal, acme, default: fallback, 'claude-app': claudeApp };
export type TileName = keyof typeof TILES;
