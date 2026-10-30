import { Alert, AlertDescription, AlertTitle } from '../../components/ui/alert';

/** The school's confirmation of the last change, shown on the sheet and on the editor's first composition. It fades after a few seconds. */
export function CourseNotice({ message }: { message: string | null }) {
  if (!message) return null;
  return <Alert className="course-notice"><AlertTitle>Confirmé par l’école</AlertTitle><AlertDescription>{message}</AlertDescription></Alert>;
}
