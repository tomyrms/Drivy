import { lazy, type ComponentType, type LazyExoticComponent } from 'react';
import type { SectionKey } from '../console/sections';

/**
 * Rebuilt pages by section. Each page takes no props and reads the shared ConsoleContext.
 * A section absent from this registry is not offered by the rebuilt navigation.
 */
export const portalPages: Partial<Record<SectionKey, LazyExoticComponent<ComponentType>>> = {
  agenda: lazy(() => import('./agenda/agenda-page').then(module => ({ default: module.AgendaPilot }))),
  eleves: lazy(() => import('./learners/learner-page').then(module => ({ default: module.LearnerPilot }))),
  equipe: lazy(() => import('./access/access-page').then(module => ({ default: () => <module.AccessPilot /> }))),
};

export const portalSections = Object.keys(portalPages) as SectionKey[];
