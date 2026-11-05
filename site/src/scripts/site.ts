import { track } from './analytics';

type SelectTab = (tab: HTMLButtonElement, focus: boolean) => void;

/** ARIA tabs. `onUserSelect` runs only for a click or key press, never for `select` called from code. */
function setUpTabs(root: Element, onUserSelect?: (tab: HTMLButtonElement) => void): { tabs: HTMLButtonElement[]; select: SelectTab } {
  const tabs = [...root.querySelectorAll<HTMLButtonElement>('[role="tab"]')];
  const select: SelectTab = (selected, focus) => {
    for (const tab of tabs) {
      const isSelected = tab === selected;
      tab.setAttribute('aria-selected', String(isSelected));
      tab.tabIndex = isSelected ? 0 : -1;
      document.getElementById(tab.getAttribute('aria-controls')!)!.hidden = !isSelected;
    }
    if (focus) selected.focus();
  };
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => {
      select(tab, false);
      onUserSelect?.(tab);
    });
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
      onUserSelect?.(tabs[targets[event.key]]);
    });
  });
  return { tabs, select };
}

function setUpCopyButtons(root: Element) {
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
        track('install_copied', { method: button.dataset.copy!, place: root.getAttribute('data-tabs')! });
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

const TYPING_MS = 55;
const QUICK_TYPING_MS = 20;
const BEFORE_OUTPUT_MS = 350;
const LINE_MS = 70;
const BEFORE_ANSWER_MS = 700;
const AFTER_ANSWER_MS = 300;
const READING_MS = 1600;
const READING_MS_PER_LINE = 200;

/**
 * Plays the example commands once, typing each command and the answers to its questions, and stops
 * on the last. The markup already holds every scene in full: this only hides and reveals, so the
 * text stays for readers without JavaScript and for search engines. Reduced motion skips playback.
 * The desktop beside `hats open` follows `data-desk` (open windows) and `data-focus` (the front one),
 * mirrored onto each window as `data-open` and `data-front`, and the launchers in its Hats folder
 * open or focus a window the way `hats open` does.
 */
function setUpSession(root: HTMLElement) {
  const toggle = root.querySelector<HTMLButtonElement>('[data-session-toggle]')!;
  const screenOf = (tab: HTMLButtonElement) => document.getElementById(tab.getAttribute('aria-controls')!)!;
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  // A newer playback, a pause or a tab the visitor picked bumps this, and older loops stop at their next step.
  let generation = 0;
  // True from the start of a playback until it ends or is stopped, including the pauses between scenes.
  let playing = false;
  let resumeAt = 0;
  let current = 0;
  let autoplay: IntersectionObserver | undefined;
  const visitorTookOver = () => autoplay?.disconnect();

  const desk = root.querySelector<HTMLElement>('.session-desk')!;
  const windows = [...desk.querySelectorAll<HTMLElement>('[data-window]')];
  const setDesk = (open: string, focus: string) => {
    root.dataset.desk = open;
    root.dataset.focus = focus;
    const opened = open.split(' ');
    for (const deskWindow of windows) {
      deskWindow.toggleAttribute('data-open', opened.includes(deskWindow.dataset.window!));
      deskWindow.toggleAttribute('data-front', deskWindow.dataset.window === focus);
    }
  };
  const deskStatus = desk.querySelector('[data-desk-status]')!;
  const launchers = [...desk.querySelectorAll<HTMLButtonElement>('[data-launch]')];
  const showDesk = (when: 'Start' | 'End') => {
    setDesk(desk.dataset[`desk${when}`]!, desk.dataset[`focus${when}`]!);
    for (const launcher of launchers) launcher.removeAttribute('data-picked');
    deskStatus.textContent = '';
  };
  const setScene = (tab: HTMLButtonElement) => {
    root.dataset.scene = tab.id.replace('session-tab-', '');
  };
  const showScene = (tab: HTMLButtonElement) => {
    setScene(tab);
    showDesk('End');
  };
  let beforeLaunch = () => {};
  for (const launcher of launchers) {
    launcher.addEventListener('click', () => {
      visitorTookOver();
      beforeLaunch();
      for (const other of launchers) other.toggleAttribute('data-picked', other === launcher);
      const id = launcher.dataset.launch!;
      const wasOpen = root.dataset.desk!.split(' ').includes(id);
      setDesk(wasOpen ? root.dataset.desk! : `${root.dataset.desk} ${id}`, id);
      deskStatus.textContent = `${launcher.dataset.title} ${wasOpen ? 'comes forward' : 'opens'}.`;
    });
  }

  const { tabs, select } = setUpTabs(root, (tab) => {
    current = tabs.indexOf(tab);
    if (reduceMotion) return showScene(tab);
    visitorTookOver();
    stopAfterCurrent();
    const mine = generation;
    playing = true;
    void playScene(tab, false, mine).then((finished) => {
      if (finished) playing = false;
    });
  });
  if (reduceMotion) return;

  const typedOf = (screen: HTMLElement) => screen.querySelector<HTMLElement>('.typed')!;
  const fullText = new Map<HTMLElement, string>();
  for (const tab of tabs) {
    const screen = screenOf(tab);
    for (const element of [typedOf(screen), ...screen.querySelectorAll<HTMLElement>('.answer')]) fullText.set(element, element.textContent!);
  }

  const wait = (ms: number, mine: number) => new Promise<boolean>((resolve) => setTimeout(() => resolve(mine === generation), ms));
  const setToggle = (label: 'Pause' | 'Play' | 'Replay') => {
    toggle.textContent = label;
    toggle.dataset.state = label.toLowerCase();
  };
  const showWhole = (tab: HTMLButtonElement) => {
    const screen = screenOf(tab);
    for (const [element, text] of fullText) if (screen.contains(element)) element.textContent = text;
    for (const line of screen.querySelectorAll<HTMLElement>('.session-out')) line.hidden = false;
    for (const typing of screen.querySelectorAll('[data-typing]')) typing.removeAttribute('data-typing');
    delete screen.dataset.pending;
    screen.removeAttribute('aria-busy');
  };
  const stop = () => {
    generation += 1;
    playing = false;
    tabs.forEach(showWhole);
    showScene(tabs[current]);
  };
  /** Stops on the current scene, so Play resumes with the next one. */
  const stopAfterCurrent = () => {
    stop();
    resumeAt = (current + 1) % tabs.length;
    setToggle(resumeAt === 0 ? 'Replay' : 'Play');
  };

  async function type(element: HTMLElement, msPerKey: number, mine: number): Promise<boolean> {
    const text = fullText.get(element)!;
    element.textContent = '';
    element.dataset.typing = '';
    for (let length = 1; length <= text.length; length += 1) {
      if (!(await wait(msPerKey, mine))) return false;
      element.textContent = text.slice(0, length);
    }
    delete element.dataset.typing;
    return true;
  }

  /** Types the command, then reveals the output a line at a time, or all at once when `lineByLine` is false. */
  async function playScene(tab: HTMLButtonElement, lineByLine: boolean, mine: number): Promise<boolean> {
    const screen = screenOf(tab);
    const lines = [...screen.querySelectorAll<HTMLElement>('.session-out')];
    setScene(tab);
    showDesk('Start');
    screen.dataset.pending = '';
    screen.setAttribute('aria-busy', 'true');
    lines.forEach((line) => (line.hidden = true));
    screen.scrollTop = 0;
    if (!(await type(typedOf(screen), lineByLine ? TYPING_MS : QUICK_TYPING_MS, mine))) return false;
    if (!(await wait(BEFORE_OUTPUT_MS, mine))) return false;
    if (lineByLine) {
      for (const line of lines) {
        const answer = line.querySelector<HTMLElement>('.answer');
        if (answer) answer.textContent = '';
        line.hidden = false;
        screen.scrollTop = screen.scrollHeight;
        if (line.dataset.opens) setDesk(`${root.dataset.desk} ${line.dataset.opens}`, line.dataset.opens);
        if (answer) {
          if (!(await wait(BEFORE_ANSWER_MS, mine))) return false;
          if (!(await type(answer, TYPING_MS * 2, mine))) return false;
          if (!(await wait(AFTER_ANSWER_MS, mine))) return false;
        } else if (!(await wait(LINE_MS, mine))) {
          return false;
        }
      }
    }
    showWhole(tab);
    showScene(tab);
    screen.scrollTop = screen.scrollHeight;
    return true;
  }

  async function play(from: number) {
    stop();
    const mine = generation;
    playing = true;
    setToggle('Pause');
    for (current = from; current < tabs.length; current += 1) {
      const tab = tabs[current];
      select(tab, false);
      if (!(await playScene(tab, true, mine))) return;
      if (current === tabs.length - 1) break;
      const lines = screenOf(tab).querySelectorAll('.session-out').length;
      if (!(await wait(READING_MS + Math.min(lines, 8) * READING_MS_PER_LINE, mine))) return;
    }
    current = tabs.length - 1;
    resumeAt = 0;
    playing = false;
    setToggle('Replay');
  }

  // A launcher acts on the final frame, so a playback still changing the desk has to end first.
  beforeLaunch = () => {
    if (playing) stopAfterCurrent();
  };
  setToggle('Play');
  toggle.hidden = false;
  toggle.addEventListener('click', () => {
    visitorTookOver();
    if (toggle.dataset.state === 'pause') {
      resumeAt = current;
      stop();
      setToggle('Play');
    } else {
      void play(resumeAt);
    }
  });

  autoplay = new IntersectionObserver((entries) => {
    if (!entries.some((entry) => entry.isIntersecting)) return;
    visitorTookOver();
    void play(0);
  }, { threshold: 0.4 });
  autoplay.observe(root);
}

function setUpDisclosure() {
  if (!matchMedia('(min-width: 768px)').matches) return;
  for (const details of document.querySelectorAll<HTMLDetailsElement>('[data-open-on-wide]')) details.open = true;
}

function closeMenuOnNavigation() {
  const menu = document.querySelector<HTMLDetailsElement>('.nav-narrow');
  menu?.querySelector('nav')?.addEventListener('click', () => {
    menu.open = false;
  });
}

for (const root of document.querySelectorAll('[data-tabs]')) {
  setUpTabs(root);
  setUpCopyButtons(root);
}
document.querySelectorAll<HTMLElement>('[data-session]').forEach(setUpSession);
setUpDisclosure();
closeMenuOnNavigation();
