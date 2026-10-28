import {readFile} from 'node:fs/promises';
import {expect,it} from 'vitest';
import {z} from 'zod';
import {setupDraftSchema,setupContentSchema} from '../src/school-onboarding-model.js';
import {saveSetupDraftCommand,completeSetupDraftCommand} from '../src/school-onboarding.js';
import {createFormationCommand,saveTariffCommand,updateProgrammeCommand,reviseSharedTermsCommand} from '../src/formation-catalogue.js';
import {requiresGPS} from '../src/practical-start-policy.js';
import {choiceCommand} from '../src/capture-contracts.js';
import {startNowCommand} from '../src/lessons.js';

it('la politique GPS reconnaît le même UUID quelle que soit sa casse',()=>{
 const school='abcdefab-1234-4234-8234-abcdefabcdef';
 expect(requiresGPS({gpsOnlyQualificationSchoolIds:[school]},school.toUpperCase())).toBe(true);
 expect(requiresGPS({gpsOnlyQualificationSchoolIds:[school.toUpperCase()]},school)).toBe(true);
 expect(requiresGPS({},school)).toBe(false);
});

it('le contrat de départ suit les commandes et le texte commun web vient du générateur serveur',async()=>{
 const contract=JSON.parse(await readFile(new URL('../contracts/practical-start.json',import.meta.url),'utf8')) as {$defs:Record<string,unknown>};
 for(const [key,schema] of Object.entries({RecordingChoiceCommand:choiceCommand,StartNowCommand:startNowCommand})){
  const {$schema:_,...expected}=z.toJSONSchema(schema,{io:'input'});
  expect(contract.$defs[key]).toEqual(expected);
 }
 const source=await readFile(new URL('../src/school-commercial-rules.ts',import.meta.url),'utf8');
 const client=await readFile(new URL('../../web/client/common-lesson-rules.ts',import.meta.url),'utf8');
 expect(client.slice(client.indexOf('\n')+1).replaceAll('\r\n','\n')).toBe(source.replaceAll('\r\n','\n'));
});

it('les contrats du brouillon et des conditions partagées suivent exactement les schémas servis',async()=>{
 const groups=[
  ['school-setup-draft',{SchoolSetupDraft:setupDraftSchema,SchoolSetupDraftContent:setupContentSchema,SaveSchoolSetupDraftCommand:saveSetupDraftCommand,ApplySchoolSetupDraftCommand:completeSetupDraftCommand}],
  ['formations',{CreateFormationCommand:createFormationCommand,UpdateFormationProgrammeCommand:updateProgrammeCommand,SaveTariffCommand:saveTariffCommand,ReviseSharedTermsCommand:reviseSharedTermsCommand}],
 ] as const;
 for(const [name,schemas] of groups){
  const contract=JSON.parse(await readFile(new URL(`../contracts/${name}.json`,import.meta.url),'utf8')) as {$defs:Record<string,unknown>};
  for(const [key,schema] of Object.entries(schemas)){
   const {$schema:_,...expected}=z.toJSONSchema(schema,{unrepresentable:'any'});
   expect(contract.$defs[key],`${name}/${key}`).toEqual(expected);
  }
 }
});
