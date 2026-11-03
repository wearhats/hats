import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const MEDIA_DIR = join(process.cwd(), 'public/media');
const has = (name: string) => existsSync(join(MEDIA_DIR, name));

const REQUIRED = ['demo.mp4', 'demo-poster.webp', 'demo.vtt', 'demo-transcript.txt', 'demo-version.txt'];

/** The Demo section needs real media. A fake or empty player must never ship, so missing files mean no section. */
export const hasDemo = REQUIRED.every(has);
export const hasWebm = has('demo.webm');

/** Kept with the recording: the release manifest moves on, and the recording doesn't. */
export const recordedVersion = hasDemo ? readFileSync(join(MEDIA_DIR, 'demo-version.txt'), 'utf8').trim() : '';

const STILLS = [
  { file: 'still-dock', caption: 'Your Dock, if you ask (`hats dock pin`).', alt: 'hats launchers in the Dock, with briefcase, person and letter icons.' },
  { file: 'still-ls', caption: 'Which account each profile is really on.', alt: 'hats ls output listing each profile and its account, with sample data.' },
  { file: 'still-doctor', caption: 'Caught before it costs you.', alt: 'hats doctor output warning that two profiles are signed in to the same Claude account, with sample data.' },
];

export const stills = hasDemo ? STILLS.filter(({ file }) => has(`${file}.avif`) && has(`${file}.webp`)) : [];
