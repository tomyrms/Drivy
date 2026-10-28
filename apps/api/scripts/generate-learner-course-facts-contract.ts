import {writeFile} from 'node:fs/promises';
import {z} from 'zod';
import {learnerCourseFactsSchema} from '../src/course-facts.js';

// Extension d'implémentation ; le contrat OpenAPI canonique 3.11.0 reste inchangé.
const {$schema:_,...definition}=z.toJSONSchema(learnerCourseFactsSchema);
await writeFile(new URL('../contracts/learner-course-facts.json',import.meta.url),JSON.stringify({
 $schema:'https://json-schema.org/draft/2020-12/schema',$id:'urn:drivy:contract:learner-course-facts:1',
 title:'Faits internes des cours utiles au dossier élève',
 description:'GET /v1/schools/{schoolId}/learners/{learnerId}/course-facts, sans query ni corps. Enveloppe data/requestId/serverTime. Accès dossier scolaire sous RLS puis élève propre dossier ou ADMIN/INSTRUCTOR+MANAGE_COURSES. Dossier hors périmètre : 404 ; droit de cours insuffisant : 403 COURSE_ACCESS_REQUIRED. Aucune écriture, aucun paiement ou note. FIRST_AID/AWARENESS identifiés par stable_key ; accomplissements non révoqués et inscriptions actives avec leurs présences séparées par série. validatedAt est la date de validation interne, jamais une date d’attestation, une dispense ou une date de dépôt. Aucun completedOn déduit.',
 $defs:{LearnerCourseFacts:definition},
},null,2)+'\n');
