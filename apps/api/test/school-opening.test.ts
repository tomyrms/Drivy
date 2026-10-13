import {expect,test} from 'vitest';
import {randomBytes} from 'node:crypto';
import {readSchoolOpeningConfig,openingToken} from '../src/school-opening-model.js';
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
});
