import { createContext } from 'react';

/** Hide portalled controls while the console revalidates restored access.
 * This is presentation state only: it never cancels a submitted command or edits a draft.
 */
export const UiSuspendedContext = createContext(false);
