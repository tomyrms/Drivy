import {describe,expect,it} from 'vitest';
import {nearestAnchorPoint,type AnchorCandidate} from '../src/capture-observations.js';

const point=(segmentId:string,sequence:number,at:number):AnchorCandidate=>({segmentId,sequence,at});
const points=[point('a',0,1_000),point('a',1,2_000),point('a',2,3_000),point('b',0,10_000)];

describe('mesure retenue pour une observation (F3)',()=>{
 it('prend la plus récente qui ne suit pas l’observation',()=>{
  expect(nearestAnchorPoint(points,3_000)).toEqual(point('a',2,3_000));
  expect(nearestAnchorPoint(points,2_999)).toEqual(point('a',1,2_000));
  expect(nearestAnchorPoint(points,10_400)).toEqual(point('b',0,10_000));
 });
 it('ne prend jamais une mesure postérieure : validateAnchor la refuserait à la réécriture',()=>{
  expect(nearestAnchorPoint(points,999)).toBeUndefined();
  expect(nearestAnchorPoint([point('a',0,5_000)],4_999)).toBeUndefined();
 });
 it('n’invente rien au-delà de 60 secondes',()=>{
  const alone=[point('a',2,3_000)];
  expect(nearestAnchorPoint(alone,3_000+60_000)).toEqual(point('a',2,3_000));
  expect(nearestAnchorPoint(alone,3_000+60_001)).toBeUndefined();
  expect(nearestAnchorPoint([],5_000)).toBeUndefined();
  expect(nearestAnchorPoint(points,20_000,5_000)).toBeUndefined();
 });
 it('départage par l’identité du segment quand deux segments n’ont pas de recouvrement',()=>{
  expect(nearestAnchorPoint(points,9_999)?.segmentId).toBe('a');
  expect(nearestAnchorPoint(points,10_000)?.segmentId).toBe('b');
 });
});
