import {writeFile} from 'node:fs/promises';
import {z} from 'zod';
import {choiceCommand} from '../src/capture-contracts.js';
import {startNowCommand} from '../src/lessons.js';

const definitions=Object.fromEntries(Object.entries({RecordingChoiceCommand:choiceCommand,StartNowCommand:startNowCommand}).map(([key,schema])=>{
 const {$schema:_,...definition}=z.toJSONSchema(schema,{io:'input'});return [key,definition];
}));
await writeFile(new URL('../contracts/practical-start.json',import.meta.url),JSON.stringify({
 $schema:'https://json-schema.org/draft/2020-12/schema',$id:'urn:drivy:contract:practical-start:1',
 title:'Départ pratique et choix GPS personnel — extension de qualification',
 description:'GET recording-notice ajoute practicalStartPolicy LEGACY ou GPS_REQUIRED. Absence sur un ancien serveur = LEGACY ; panne ou valeur inconnue ne vaut jamais LEGACY. GPS_REQUIRED est limité aux écoles synthétiques configurées par GPS_ONLY_QUALIFICATION_SCHOOL_IDS, vide par défaut. POST lessons/start-now avec prepareForGPS=true réserve une leçon PLANNED sans actualStart ; seul POST lessons/{lessonId}/captures peut alors commencer atomiquement la leçon après toutes les validations. POST lessons/{lessonId}/start est refusé en GPS_REQUIRED. Choix SELF requis ; ALLOWED exige expectedChoiceVersion actuel (0 sans choix), REFUSED reste disponible sans ce prérequis. Identités, droits, clés idempotentes, reçus et If-Match existants conservés. Activation réelle bloquée par #266.',
 $defs:definitions,
},null,2)+'\n');
