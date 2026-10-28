import { useEffect, type RefObject } from 'react';

/**
 * Focus a page heading once the portal frame has finished moving focus to the content landmark.
 * On a destination change the frame focuses `main` in its own effect, which runs after the page's effects:
 * focusing synchronously would be overwritten, so the heading takes focus on the next frame.
 */
export function useHeadingFocus(heading: RefObject<HTMLElement | null>, key?: unknown, options?: FocusOptions) {
  useEffect(() => {
    const frame = window.requestAnimationFrame(() => heading.current?.focus(options));
    return () => window.cancelAnimationFrame(frame);
  }, [key]);
}
