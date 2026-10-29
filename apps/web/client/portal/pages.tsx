import { lazy, type ComponentType, type LazyExoticComponent } from 'react';
import type { SectionKey } from '../console/sections';

/**
 * Rebuilt pages by section. Each page takes no props and reads the shared ConsoleContext.
 * A section absent from this registry is not offered by the rebuilt navigation.
 */
export const portalPages: Partial<Record<SectionKey, LazyExoticComponent<ComponentType>>> = {
  agenda: lazy(() => import('./agenda/agenda-page').then(module => ({ default: module.AgendaPilot }))),
  eleves: lazy(() => import('./learners/learner-page').then(module => ({ default: module.LearnerPilot }))),
  equipe: lazy(() => import('./team/team-page').then(module => ({ default: module.TeamPilot }))),
  invitations: lazy(() => import('./invitations/invitations-page').then(module => ({ default: module.InvitationsPilot }))),
  disponibilites: lazy(() => import('./availability/schedule-page').then(module => ({ default: module.AvailabilityPilot }))),
  absences: lazy(() => import('./availability/schedule-page').then(module => ({ default: module.AbsencesPilot }))),
  // Formations et tarifs (#326, #327). Les adresses contextuelles ouvrent la même famille.
  formations: lazy(() => import('./formations/catalogue-page').then(module => ({ default: module.FormationsPage }))),
  offres: lazy(() => import('./formations/catalogue-page').then(module => ({ default: module.OffresPage }))),
  referentiels: lazy(() => import('./formations/catalogue-page').then(module => ({ default: module.ReferentielsPage }))),
  procedures: lazy(() => import('./formations/catalogue-page').then(module => ({ default: module.ProceduresPage }))),
  prestations: lazy(() => import('./pricing/prestations-page').then(module => ({ default: module.PrestationsPage }))),
  conditions: lazy(() => import('./pricing/terms-page').then(module => ({ default: module.TermsPage }))),
  signalements: lazy(() => import('./signals/signals-page').then(module => ({ default: module.SignalsPilot }))),
};

export const portalSections = Object.keys(portalPages) as SectionKey[];
