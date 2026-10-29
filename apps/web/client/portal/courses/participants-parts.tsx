import type { RowFeedback } from './use-course-participants';

/** The state of the last send for one row, in words, announced politely and shown beside the person it concerns. */
export function FeedbackText({ feedback }: { feedback: RowFeedback | undefined }) {
  if (!feedback) return null;
  return <span className="participants-feedback" data-tone={feedback.tone} role={feedback.tone === 'error' ? 'alert' : 'status'}>{feedback.text}</span>;
}
