import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';

const docs = defineCollection({
  loader: glob({ base: '../docs', pattern: 'privacy.md' }),
});

export const collections = { docs };
