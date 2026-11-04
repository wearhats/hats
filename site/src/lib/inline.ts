const ESCAPES: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' };
const escape = (text: string) => text.replace(/[&<>"]/g, (char) => ESCAPES[char]);

/** Copy lives in data files as plain strings with `code`, *emphasis*, **strong** and [links](url). */
export function inline(source: string): string {
  return source
    .split(/(`[^`]+`)/)
    .map((part) => {
      if (part.startsWith('`') && part.endsWith('`') && part.length > 1) return `<code>${escape(part.slice(1, -1))}</code>`;
      return escape(part)
        .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
        .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
        .replace(/\*([^*]+)\*/g, '<em>$1</em>');
    })
    .join('');
}
