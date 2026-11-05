import redirects from '../../public/_redirects?raw';

type EventData = Record<string, string>;

declare global {
  interface Window {
    umami?: { track: (event: string, data?: EventData) => void };
  }
}

/** Sends a custom Umami event. Without the tracker (no website ID, a blocker, Do Not Track) it does nothing. */
export function track(event: string, data?: EventData): void {
  try {
    window.umami?.track(event, data);
  } catch {
    // Analytics must never break the page.
  }
}

// These paths are 302s to GitHub, so the visitor leaves without a pageview here.
const redirectPaths = new Set(
  redirects
    .split('\n')
    .map((line) => line.trim().split(/\s+/)[0])
    .filter((path) => path?.startsWith('/')),
);

/** Where a link takes the visitor off this site, as host and path without the query, or undefined if it stays. */
function destinationOffSite(link: HTMLAnchorElement): string | undefined {
  if (link.protocol !== 'https:' && link.protocol !== 'http:') return undefined;
  if (link.host !== location.host) return `${link.host}${link.pathname}`.replace(/\/$/, '');
  return redirectPaths.has(link.pathname) ? link.pathname : undefined;
}

/**
 * Records links that leave the site. Umami's own `data-umami-event` holds a link's navigation until its request
 * answers, so a slow analytics server would stall the click; this sends alongside the navigation instead, and the
 * tracker's keepalive request outlives the page.
 */
function trackLinksOffSite() {
  const onClick = (event: MouseEvent) => {
    if (event.type === 'auxclick' && event.button !== 1) return;
    const link = (event.target as Element | null)?.closest?.('a[href]');
    if (!(link instanceof HTMLAnchorElement)) return;
    const to = destinationOffSite(link);
    if (to) track('outbound_clicked', { to });
  };
  document.addEventListener('click', onClick, { capture: true });
  document.addEventListener('auxclick', onClick, { capture: true });
}

trackLinksOffSite();
