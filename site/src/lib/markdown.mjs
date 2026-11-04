import { REPO_URL } from '../data/site.ts';

const REPO_DOCS = `${REPO_URL}/blob/main/docs/`;

function walk(node, visit) {
  visit(node);
  (node.children ?? []).forEach((child) => walk(child, visit));
}

/** Relative links in docs/*.md only resolve inside the repo, so point them at GitHub. */
export function githubDocLinks() {
  return (tree) =>
    walk(tree, (node) => {
      if (node.type === 'link' && !/^([a-z]+:|#)/i.test(node.url)) {
        node.url = new URL(node.url, REPO_DOCS).href;
      }
    });
}

/** The page renders the document's title itself, so the entry must not repeat it as a second h1. */
export function stripTitle() {
  return (tree) => {
    const first = tree.children.findIndex((node) => node.type === 'heading');
    if (first !== -1 && tree.children[first].depth === 1) tree.children.splice(first, 1);
  };
}

const textOf = (node) => node.value ?? (node.children ?? []).map(textOf).join('');

/** Wide tables scroll inside their own focusable region, named after their section, and header cells get a scope. */
export function accessibleTables() {
  return (tree) => {
    walk(tree, (node) => {
      if (node.tagName === 'th') {
        node.properties = { ...node.properties, scope: 'col' };
      }
    });
    let section = 'Document';
    tree.children = tree.children.map((child) => {
      if (child.tagName === 'h2') section = textOf(child);
      if (child.tagName !== 'table') return child;
      return {
        type: 'element',
        tagName: 'div',
        properties: { className: ['table-scroll'], tabindex: 0, role: 'region', ariaLabel: `${section} table` },
        children: [child],
      };
    });
  };
}
