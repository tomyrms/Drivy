import { CalendarPlus, ChevronDown, GraduationCap, Plus } from 'lucide-react';
import { Button } from '../../components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem, DropdownMenuTrigger } from '../../components/ui/dropdown-menu';

/** « Ajouter » of the agenda: a lesson, or a collective course where the school offers them. Without courses it is the plain lesson action. */
export function AgendaAddMenu({ canCreateCourse, onLesson, onCourse }: { canCreateCourse: boolean; onLesson: () => void; onCourse: () => void }) {
  if (!canCreateCourse) return <Button id="portal-agenda-add" onClick={onLesson}><Plus data-icon="inline-start" />Planifier une leçon</Button>;
  return <DropdownMenu>
    <DropdownMenuTrigger render={<Button id="portal-agenda-add" />}><Plus data-icon="inline-start" />Ajouter<ChevronDown data-icon="inline-end" /></DropdownMenuTrigger>
    <DropdownMenuContent align="end" className="min-w-56"><DropdownMenuGroup>
      <DropdownMenuItem onClick={onLesson}><CalendarPlus />Leçon individuelle</DropdownMenuItem>
      <DropdownMenuItem onClick={onCourse}><GraduationCap />Cours collectif</DropdownMenuItem>
    </DropdownMenuGroup></DropdownMenuContent>
  </DropdownMenu>;
}
