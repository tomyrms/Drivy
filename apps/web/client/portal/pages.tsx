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
};

export const portalSections = Object.keys(portalPages) as SectionKey[];
