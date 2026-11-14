import { FAQ } from '../data/copy';
import { VERSION } from '../data/release';
import { DESCRIPTION, LICENSE_URL, MAINTAINER_SITE, MAINTAINER_URL, REPO_URL } from '../data/site';
import { plain } from './inline';

/** The home page's JSON-LD. `site` is the canonical origin, and every node's `@id` hangs off it. */
export function homeStructuredData(site: URL): string {
  const home = site.href;
  const graph = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebSite',
        '@id': `${home}#website`,
        url: home,
        name: 'hats',
        // "hats" alone is a common word, so these are the names people can search for.
        alternateName: ['wearhats', 'hats for Claude'],
        description: DESCRIPTION,
        inLanguage: 'en',
      },
      {
        '@type': 'SoftwareApplication',
        '@id': `${home}#software`,
        name: 'hats',
        url: home,
        description: DESCRIPTION,
        image: new URL('/og/home.png', site).href,
        operatingSystem: 'macOS 14+',
        applicationCategory: 'DeveloperApplication',
        offers: { '@type': 'Offer', price: 0, priceCurrency: 'USD' },
        license: LICENSE_URL,
        downloadUrl: `${REPO_URL}/releases`,
        softwareVersion: VERSION,
        sameAs: [REPO_URL],
        author: { '@type': 'Person', name: 'Max Novak', url: MAINTAINER_SITE, sameAs: [MAINTAINER_URL] },
      },
      {
        '@type': 'FAQPage',
        '@id': `${home}#faq`,
        mainEntity: FAQ.map(([question, answer]) => ({
          '@type': 'Question',
          name: question,
          acceptedAnswer: { '@type': 'Answer', text: plain(answer) },
        })),
      },
    ],
  };
  // Inside a <script>, a "<" in the copy could end the element early.
  return JSON.stringify(graph).replace(/</g, '\\u003c');
}
