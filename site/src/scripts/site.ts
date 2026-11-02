function setUpTabs(root: Element) {
  const tabs = [...root.querySelectorAll<HTMLButtonElement>('[role="tab"]')];
  const select = (selected: HTMLButtonElement, focus: boolean) => {
    for (const tab of tabs) {
      const isSelected = tab === selected;
      tab.setAttribute('aria-selected', String(isSelected));
      tab.tabIndex = isSelected ? 0 : -1;
      document.getElementById(tab.getAttribute('aria-controls')!)!.hidden = !isSelected;
    }
    if (focus) selected.focus();
  };
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => select(tab, false));
    tab.addEventListener('keydown', (event) => {
      const targets: Record<string, number> = {
        ArrowRight: (index + 1) % tabs.length,
        ArrowLeft: (index - 1 + tabs.length) % tabs.length,
        Home: 0,
        End: tabs.length - 1,
      };
      if (!(event.key in targets)) return;
      event.preventDefault();
      select(tabs[targets[event.key]], true);
    });
  });

  const status = root.querySelector('[data-copy-status]')!;
  for (const button of root.querySelectorAll<HTMLButtonElement>('[data-copy]')) {
    if (!navigator.clipboard) continue;
    button.hidden = false;
    button.addEventListener('click', async () => {
      const command = button.parentElement!.querySelector('[data-command]')!.textContent!;
      try {
        await navigator.clipboard.writeText(command);
        button.textContent = 'Copied';
        status.textContent = 'Copied to clipboard';
      } catch {
        button.textContent = 'Copy failed';
        status.textContent = 'Could not copy. Select the command instead.';
      }
      setTimeout(() => {
        button.textContent = 'Copy';
        status.textContent = '';
      }, 2000);
    });
  }
}

function setUpDockFilter() {
  const terminal = document.querySelector('[data-terminal]');
  if (!terminal) return;
  const views = [...terminal.querySelectorAll<HTMLElement>('[data-view]')];
  const caption = terminal.querySelector('[data-terminal-command]')!;
  const buttons = [...document.querySelectorAll<HTMLButtonElement>('[data-filter]')];
  const show = (id: string) => {
    for (const view of views) {
      const isShown = view.dataset.view === id;
      view.hidden = !isShown;
      if (isShown) caption.textContent = view.querySelector('.typed')!.textContent;
    }
    for (const button of buttons) button.setAttribute('aria-pressed', String(button.dataset.filter === id));
  };
  for (const button of buttons) {
    button.disabled = false;
    button.addEventListener('click', () => {
      show(button.getAttribute('aria-pressed') === 'true' ? 'all' : button.dataset.filter!);
    });
  }
}

function setUpDisclosure() {
  if (!matchMedia('(min-width: 768px)').matches) return;
  for (const details of document.querySelectorAll<HTMLDetailsElement>('[data-open-on-wide]')) details.open = true;
}

document.querySelectorAll('[data-tabs]').forEach(setUpTabs);
setUpDockFilter();
setUpDisclosure();
