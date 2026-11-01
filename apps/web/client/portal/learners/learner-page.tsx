import { useEffect, useRef, useState } from 'react';
import { ArrowLeft, ArrowRight, CalendarPlus, ChevronLeft, ChevronRight, Mail, Phone, Search, UsersRound } from 'lucide-react';
import { Avatar, AvatarFallback } from '../../components/ui/avatar';
import { Badge } from '../../components/ui/badge';
import { Button } from '../../components/ui/button';
import { Input } from '../../components/ui/input';
import { Field, FieldLabel } from '../../components/ui/field';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '../../components/ui/tabs';
import { Alert, AlertTitle, AlertDescription } from '../../components/ui/alert';
import { useConsole } from '../../console/context';
import { PortalSelect } from '../components/portal-select';
import { trainingStatusLabels, useLearnerController, type LearnerController } from './learner-controller';
import { CommandFeedback, ReadFeedback } from './learner-feedback';
import { LearnerFollowUp } from './learner-follow-up';
import { LearnerFormations, LearnerConfirmation } from './learner-management';
import { LearnerInformation } from './learner-information';
import { LearnerExams, PendingExamResults } from './learner-exams';
import './learners.css';

export const initials = (name: string) => name.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join('');

export function LearnerPilot() {
  const state = useLearnerController();
  const context = useConsole();
  const [section, setSection] = useState('follow-up');
  const titleRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => { setSection('follow-up'); }, [state.selected]);
  useEffect(() => { titleRef.current?.focus({ preventScroll: true }); }, [state.selected]);
  const selectSection = (value: string) => context.confirmNavigation ? context.confirmNavigation(() => setSection(value)) : setSection(value);
  const current = state.current;
  if (!state.selected) return <LearnerDirectory state={state} />;
  if (!current) return <section className="student-page"><Button variant="ghost" onClick={() => state.setSelected(null)}><ArrowLeft />Élèves</Button><h1 ref={titleRef} tabIndex={-1}>Dossier élève</h1><ReadFeedback loaded={state.selectedLearner.status === 'error' ? state.selectedLearner : state.loaded.status === 'error' ? state.loaded : state.selectedLearner} />{state.selectedLearner.status === 'ready' && !current && <p>Ce dossier n’est pas disponible.</p>}</section>;
  const busy = state.runner.busy || !!state.runner.pending;
  return <section className="student-page">
    <nav className="student-breadcrumb" aria-label="Fil d’Ariane"><Button variant="ghost" size="sm" onClick={() => state.setSelected(null)}><ArrowLeft />Élèves</Button><ChevronRight aria-hidden="true" /><span>{current.displayName}</span></nav>
    <header className="student-heading"><div className="student-identity"><Avatar className="student-avatar"><AvatarFallback>{initials(current.displayName)}</AvatarFallback></Avatar><div><h1 ref={titleRef} tabIndex={-1}>{current.displayName}</h1><div className="student-contact">{current.contactEmail && <a href={`mailto:${current.contactEmail}`}><Mail aria-hidden="true" />{current.contactEmail}</a>}{current.contactPhone && <a href={`tel:${current.contactPhone}`}><Phone aria-hidden="true" />{current.contactPhone}</a>}{!current.contactEmail && !current.contactPhone && <span>Contact non renseigné</span>}</div></div></div>
      {current.archivedAt ? <Badge variant="secondary">Dossier archivé</Badge> : <Button disabled={busy || state.school.status !== 'ACTIVE'} onClick={() => state.navigate('agenda', { view: 'nouvelle', learner: current.id })}><CalendarPlus />Planifier une leçon</Button>}
    </header>
    {(state.routeQuery?.from === 'agenda' || state.routeQuery?.lesson) && <Button className="student-back-context" variant="ghost" onClick={() => state.navigate('agenda', { week: state.routeQuery?.week, day: state.routeQuery?.day, instructor: state.routeQuery?.instructor, lesson: state.routeQuery?.lesson })}><ArrowLeft />Retour à l’agenda</Button>}
    <CommandFeedback runner={state.runner} />
    <ReadFeedback loaded={state.resources} />
    {state.resources.data?.truncated && <Alert><AlertTitle>Références partiellement chargées</AlertTitle><AlertDescription>Les modifications attendent la lecture complète des formations, des moniteurs et des programmes.</AlertDescription></Alert>}
    {state.selectedTrainings.data?.truncated && <Alert><AlertTitle>Formations partiellement chargées</AlertTitle><AlertDescription>Les modifications sont indisponibles tant que la liste complète n’est pas lue.</AlertDescription></Alert>}
    <Tabs value={section} onValueChange={value => selectSection(String(value))} className="student-tabs">
      <TabsList aria-label="Rubriques du dossier"><TabsTrigger value="follow-up">Suivi</TabsTrigger><TabsTrigger value="formations">Formations</TabsTrigger><TabsTrigger value="exams">Examens</TabsTrigger><TabsTrigger value="information">Informations</TabsTrigger></TabsList>
      <TabsContent value="follow-up"><LearnerFollowUp state={state} /></TabsContent>
      <TabsContent value="formations"><LearnerFormations state={state} /></TabsContent>
      <TabsContent value="exams"><LearnerExams state={state} /></TabsContent>
      <TabsContent value="information"><LearnerInformation learner={current} state={state} /></TabsContent>
    </Tabs>
    <LearnerConfirmation state={state} />
  </section>;
}

function LearnerDirectory({ state }: { state: LearnerController }) {
  return <section className="student-page">
    <header className="student-heading"><div><p className="student-eyebrow">École</p><h1>Élèves</h1></div><span className="student-directory-count"><UsersRound aria-hidden="true" />{state.loaded.data ? `${state.visible.length} dossier${state.visible.length > 1 ? 's' : ''}${state.loaded.data.truncated ? ' chargés' : ''}` : 'Annuaire'}</span></header>
    <div className="student-directory-tools"><Field className="student-search"><FieldLabel className="sr-only" htmlFor="learner-search">Rechercher un élève</FieldLabel><Search aria-hidden="true" /><Input id="learner-search" type="search" placeholder="Nom, e-mail ou téléphone" value={state.search} onChange={event => { state.setSearch(event.target.value); state.setPage(1); }} /></Field>
      <PortalSelect id="directory-status" label="Dossiers" value={state.statusFilter} onValueChange={value => { if (value === 'active' || value === 'archived' || value === 'all') state.setStatusFilter(value); state.setPage(1); }} options={[{ value: 'active', label: 'Actifs' }, { value: 'archived', label: 'Archivés' }, { value: 'all', label: 'Tous' }]} />
      <PortalSelect id="directory-readiness" label="Profil" value={state.readinessFilter} onValueChange={value => { if (value === 'all' || value === 'incomplete') state.setReadinessFilter(value); state.setPage(1); }} options={[{ value: 'all', label: 'Tous les profils' }, { value: 'incomplete', label: 'À compléter' }]} />
      <PortalSelect id="directory-sort" label="Trier" value={state.sort} onValueChange={value => { if (value === 'name-asc' || value === 'name-desc') state.setSort(value); }} options={[{ value: 'name-asc', label: 'Nom A–Z' }, { value: 'name-desc', label: 'Nom Z–A' }]} />
    </div>
    <PendingExamResults state={state} />
    <ReadFeedback loaded={state.loaded} />
    {state.loaded.data?.truncated && <Alert><AlertTitle>Annuaire partiellement chargé</AlertTitle><AlertDescription>La recherche porte sur les dossiers chargés.</AlertDescription></Alert>}
    <div className="student-directory" role="list" aria-label="Dossiers élèves">{state.pageRows.map(learner => {
      const trainings = state.trainingsOf(learner.id); const active = trainings.filter(training => training.status === 'ACTIVE' || training.status === 'PAUSED');
      return <button type="button" className="student-directory-row" key={learner.id} role="listitem" onClick={() => state.setSelected(learner.id)}><Avatar><AvatarFallback>{initials(learner.displayName)}</AvatarFallback></Avatar><span className="student-directory-person"><strong>{learner.displayName}</strong><span>{learner.contactEmail ?? learner.contactPhone ?? 'Contact non renseigné'}</span></span><span className="student-directory-training">{state.listTrainings.status === 'ready' ? active.length ? active.map(training => `${state.category(training)} · ${trainingStatusLabels[training.status]}`).join(', ') : 'Aucune formation en cours' : 'Formations indisponibles'}</span><span className="student-directory-state">{learner.archivedAt ? <Badge variant="secondary">Archivé</Badge> : state.notReady(learner) ? <Badge variant="outline">Profil à compléter</Badge> : null}</span><ArrowRight className="student-row-arrow" aria-hidden="true" /></button>;
    })}</div>
    {state.loaded.status === 'ready' && !state.visible.length && <div className="student-empty"><UsersRound aria-hidden="true" /><h2>{state.search || state.readinessFilter !== 'all' ? 'Aucun dossier correspondant' : 'Aucun élève dans cette liste'}</h2>{(state.search || state.readinessFilter !== 'all') && <Button variant="outline" onClick={() => { state.setSearch(''); state.setReadinessFilter('all'); }}>Effacer les filtres</Button>}</div>}
    {state.visible.length > state.pageSize && <footer className="student-pagination"><span>Page {state.currentPage} sur {Math.ceil(state.visible.length / state.pageSize)}</span><div><Button variant="outline" size="icon" aria-label="Page précédente" disabled={state.currentPage <= 1} onClick={() => state.setPage(state.currentPage - 1)}><ChevronLeft /></Button><Button variant="outline" size="icon" aria-label="Page suivante" disabled={state.currentPage * state.pageSize >= state.visible.length} onClick={() => state.setPage(state.currentPage + 1)}><ChevronRight /></Button></div></footer>}
  </section>;
}
