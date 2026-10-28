import {writeFile} from 'node:fs/promises';
import {z} from 'zod';
import {createFormationCommand,saveTariffCommand,updateProgrammeCommand,reviseSharedTermsCommand} from '../src/formation-catalogue.js';

// Contrat d'implémentation séparé : ne modifie pas la livraison OpenAPI canonique 3.11.0.
const schemas={CreateFormationCommand:createFormationCommand,UpdateFormationProgrammeCommand:updateProgrammeCommand,SaveTariffCommand:saveTariffCommand,ReviseSharedTermsCommand:reviseSharedTermsCommand};
const definitions=Object.fromEntries(Object.entries(schemas).map(([key,schema])=>{const {$schema:_,...definition}=z.toJSONSchema(schema,{unrepresentable:'any'});return [key,definition];}));
await writeFile(new URL('../contracts/formations.json',import.meta.url),JSON.stringify({$schema:'https://json-schema.org/draft/2020-12/schema',$id:'urn:drivy:contract:formations:1',
  title:'Formations et tarifs : fiche d’un permis et commandes composées',
  description:'GET /v1/schools/{schoolId}/formations, /formations/sheet?category=, /formations/uncategorized-tariffs, /formations/terms, /formations/references/{id} (ADMIN courant). POST /formations (CREATE_FORMATION), /formations/programmes (UPDATE_FORMATION_PROGRAMME), /formations/tariffs (SAVE_TARIFF), /formations/terms/revise (REVISE_SHARED_TERMS) : Idempotency-Key = operationId, 201, une opération et un reçu AP72 par commande ; têtes attendues comparées sous le verrou scolaire ; CONFIGURE_CATALOG requis pour toute écriture commerciale.',
  $defs:definitions},null,2)+'\n');
