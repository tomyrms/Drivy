import { useEffect, useState } from 'react';
import { ArrowLeft } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { courseSeriesSchema, type CourseCatalogue, type CourseSeries } from '../../console/course-model';
import { useCommandSnapshot } from '../../command-store';
import { useConsole, useLoad, type Loaded } from '../../console/context';
import { RequestFailure } from '../../protocol';
import { readSchool } from '../../school-api';
import { ReadFeedback } from '../agenda/presentation';
import { CourseEditor } from './course-editor';
import { CourseSheet } from './course-sheet';
import './courses.css';

/**
 * Opens a course from the agenda: a draft (or a new course) in the editor, anything else as the sheet.
 * `courseId` null means a new course. The workspace owns what survives a save: the confirmation, and the series just written.
 */
export function CourseWorkspace({ courseId, occurrenceId, catalogue, onClose, onShow, onChanged }: {
  courseId: string | null; occurrenceId: string | undefined; catalogue: Loaded<CourseCatalogue>; onClose: () => void;
  onShow: (id: string, occurrence?: string) => void; onChanged: () => void;
}) {
  const { schoolId } = useConsole();
  const { revision } = useCommandSnapshot();
  // The loaded value is never null: a null would read as « nothing on screen » and unmount a new course's editor at each confirmation.
  const loaded = useLoad(async (): Promise<{ series: CourseSeries | null }> => {
    if (!courseId) return { series: null };
    const series = await readSchool(schoolId, `course-series/${courseId}`, courseSeriesSchema);
    if (series.id !== courseId || series.schoolId !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    return { series };
  }, [schoolId, courseId, revision], `${schoolId}/${courseId ?? 'new'}`, `course-series/${courseId ?? 'new'}`);
  const [notice, setNotice] = useState<string | null>(null);
  useEffect(() => { if (!notice) return; const timer = window.setTimeout(() => setNotice(null), 8000); return () => window.clearTimeout(timer); }, [notice]);
  const done = (series: CourseSeries | null, message: string) => {
    setNotice(message); onChanged();
    if (series) onShow(series.id, occurrenceId); else loaded.reload();
  };
  const series = loaded.data?.series ?? null;
  const unavailable = <section className="course-page"><Button variant="ghost" className="course-back" onClick={onClose}><ArrowLeft data-icon="inline-start" />Retour à l’agenda</Button>
    <ReadFeedback loaded={loaded} label="Lecture du cours" /></section>;
  if (loaded.status !== 'ready' || (courseId && !series)) return unavailable;
  if (catalogue.status !== 'ready' && (!series || series.status === 'DRAFT')) return <section className="course-page"><Button variant="ghost" className="course-back" onClick={onClose}><ArrowLeft data-icon="inline-start" />Retour à l’agenda</Button>
    <ReadFeedback loaded={catalogue} label="Lecture des types et des moniteurs" /></section>;
  const reread = () => { loaded.reload(); catalogue.reload(); };
  if (!series || series.status === 'DRAFT') {
    // The key follows the series, not the version: saving the draft never discards what is on screen.
    return <CourseEditor key={series?.id ?? 'new'} series={series} catalogue={catalogue.data!} canManage={series ? series.canManage : catalogue.data!.canManage} notice={notice}
      onClose={onClose} onDone={done} onReread={reread} />;
  }
  return <CourseSheet series={series} catalogue={catalogue.data} occurrenceId={occurrenceId} notice={notice} onClose={onClose} onChanged={done} onReread={reread} />;
}
