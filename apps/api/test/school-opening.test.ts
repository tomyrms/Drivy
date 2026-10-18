import {expect,test} from 'vitest';
import {randomBytes,randomUUID} from 'node:crypto';
import {readSchoolOpeningConfig,openingToken,schoolOpeningBody} from '../src/school-opening-model.js';
test('opérateurs fermés par défaut et identité OIDC complète requise',()=>{
  expect(readSchoolOpeningConfig({})).toEqual({operators:[],validityDays:7});
  expect(()=>readSchoolOpeningConfig({SCHOOL_OPENING_OPERATORS_JSON:'[{"subject":"admin"}]'})).toThrow();
  expect(()=>readSchoolOpeningConfig({SCHOOL_OPENING_VALIDITY_DAYS:'365'})).toThrow();
  expect(readSchoolOpeningConfig({SCHOOL_OPENING_OPERATORS_JSON:'[{"issuer":"https://identity.example.invalid","subject":"operator"}]'}).operators).toHaveLength(1);
});
test('secret exactement 256 bits sous forme base64url canonique',()=>{
  expect(openingToken.safeParse(randomBytes(32).toString('base64url')).success).toBe(true);
  expect(openingToken.safeParse('a'.repeat(43)).success).toBe(false);
  expect(openingToken.safeParse('a'.repeat(42)+'A=').success).toBe(false);
  // Code court d'ouverture : alphabet des codes d'invitation, casse et tiret tolérés ; O, 0, I et 1 restent exclus.
  for(const code of ['ABCD-EF23','abcdef23','WXYZ9876']) expect(openingToken.safeParse(code).success).toBe(true);
  for(const code of ['ABCD-EF2','ABCO-EF23','ABC1-EF23','ABCD--EF23']) expect(openingToken.safeParse(code).success).toBe(false);
});
test('les coordonnées créées respectent les limites des étapes de préparation',()=>{
  const body={operationId:randomUUID(),token:randomBytes(32).toString('base64url'),schoolName:'Recette synthétique',displayName:'Responsable synthétique',
    contactEmail:'school@example.invalid',contactPhone:'0'.repeat(32),timeZone:'Europe/Zurich',instructs:false};
  expect(schoolOpeningBody.safeParse(body).success).toBe(true);
  expect(schoolOpeningBody.safeParse({...body,contactPhone:'0'.repeat(33)}).success).toBe(false);
  for(const timeZone of ['+01:00','-02:00','Invalid/Zone',''])expect(schoolOpeningBody.safeParse({...body,timeZone}).success).toBe(false);
});
