import {readFile,writeFile} from 'node:fs/promises';
import {z} from 'zod';
import {setupDraftSchema,setupContentSchema} from '../src/school-onboarding-model.js';
import {saveSetupDraftCommand,completeSetupDraftCommand} from '../src/school-onboarding.js';

// Contrat d'implémentation séparé : ne modifie pas la livraison OpenAPI canonique.
const schemas={SchoolSetupDraft:setupDraftSchema,SchoolSetupDraftContent:setupContentSchema,SaveSchoolSetupDraftCommand:saveSetupDraftCommand,ApplySchoolSetupDraftCommand:completeSetupDraftCommand};
const definitions=Object.fromEntries(Object.entries(schemas).map(([key,schema])=>{const {$schema:_,...definition}=z.toJSONSchema(schema);return [key,definition];}));
await writeFile(new URL('../contracts/school-setup-draft.json',import.meta.url),JSON.stringify({$schema:'https://json-schema.org/draft/2020-12/schema',$id:'urn:drivy:contract:school-setup-draft:1',
  title:'Préparation scolaire web : brouillon durable et application explicite',
  description:'GET/PUT /v1/schools/{schoolId}/setup-draft ; GET preview?activate=true|false ; POST complete. ADMIN courant, Idempotency-Key et If-Match draft requis pour les écritures. Validation métier et droits revérifiés au commit.',
  $defs:definitions},null,2)+'\n');
// Même génération de texte dans l'aperçu web et la publication serveur, sans dépendance du build web au service API.
await writeFile(new URL('../../web/client/common-lesson-rules.ts',import.meta.url),
  '// Généré par apps/api/scripts/generate-school-setup-contract.ts depuis school-commercial-rules.ts.\n'+await readFile(new URL('../src/school-commercial-rules.ts',import.meta.url),'utf8'));
