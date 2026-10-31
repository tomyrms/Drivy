import {describe,expect,it} from 'vitest';
import * as M from '../src/school-metrics-model.js';

describe('dates civiles et période',()=>{
 it('valide les dates réelles, l\'ordre et la limite de 366 jours',()=>{
  expect(M.isCivilDate('2026-10-31')).toBe(true);
  expect(M.isCivilDate('2026-02-30')).toBe(false);
  expect(M.isCivilDate('2026-1-31')).toBe(false);
  expect(M.validatePeriod('2026-10-01','2026-11-01')).toBe(31);
  expect(M.validatePeriod('2026-01-01','2027-01-02')).toBe(366);
  expect(()=>M.validatePeriod('2026-11-01','2026-10-01')).toThrow(expect.objectContaining({code:'INVALID_PERIOD'}));
  expect(()=>M.validatePeriod('2026-10-01','2026-10-01')).toThrow(expect.objectContaining({code:'INVALID_PERIOD'}));
  expect(()=>M.validatePeriod('2026-01-01','2027-01-03')).toThrow(expect.objectContaining({code:'PERIOD_TOO_LARGE'}));
 });
 it('calcule jours, semaines et mois sans durée fixe',()=>{
  expect(M.addDays('2026-10-31',1)).toBe('2026-11-01');
  expect(M.addMonths('2026-10-15',1)).toBe('2026-11-01');
  expect(M.addMonths('2026-01-31',-1)).toBe('2025-12-01');
  expect(M.weekStart('2026-10-25')).toBe('2026-10-19');// dimanche -> lundi précédent
  expect(M.weekStart('2026-10-19')).toBe('2026-10-19');
  expect(M.daysBetween('2026-10-01','2026-11-01')).toBe(31);
 });
});

describe('comparaisons (règle K9)',()=>{
 it('mois complet contre mois complet, longueurs différentes affichées',()=>{
  const plan=M.planComparison('previous-month','2026-10-01','2026-11-01','2026-10-28');
  expect(plan).toEqual({mode:'FULL_MONTH',base:{from:'2026-09-01',toExclusive:'2026-10-01',days:30,clipped:false}});
 });
 it('mois à date contre la même plage du mois précédent',()=>{
  expect(M.planComparison('previous-month','2026-10-01','2026-10-29','2026-10-28'))
   .toEqual({mode:'MONTH_TO_DATE',base:{from:'2026-09-01',toExclusive:'2026-09-29',days:28,clipped:false}});
 });
 it('mois à date tronqué quand le mois précédent est plus court',()=>{
  // Le 30 octobre : 30 jours courants contre septembre (30 jours) : pas tronqué.
  expect(M.planComparison('previous-month','2026-10-01','2026-10-31','2026-10-30').base.clipped).toBe(false);
  // Le 31 octobre est un mois complet ; un mois de 31 jours contre un mois de 30 jours se tronque en mois à date au 31 décembre... ici janvier contre février.
  const plan=M.planComparison('previous-month','2026-03-01','2026-03-31','2026-03-30');
  expect(plan.mode).toBe('MONTH_TO_DATE');
  expect(plan.base).toEqual({from:'2026-02-01',toExclusive:'2026-03-01',days:28,clipped:true});
 });
 it('période équivalente = même nombre de jours juste avant',()=>{
  expect(M.planComparison('equivalent-period','2026-10-12','2026-10-19','2026-10-28'))
   .toEqual({mode:'EQUIVALENT_PERIOD',base:{from:'2026-10-05',toExclusive:'2026-10-12',days:7,clipped:false}});
 });
 it('refuse un « mois précédent » qui n\'est ni un mois complet ni un mois à date',()=>{
  expect(()=>M.planComparison('previous-month','2026-10-05','2026-10-20','2026-10-28')).toThrow(expect.objectContaining({code:'INVALID_PERIOD'}));
  expect(()=>M.planComparison('previous-month','2026-10-01','2026-10-20','2026-10-28')).toThrow(expect.objectContaining({code:'INVALID_PERIOD'}));
 });
});

describe('écart en dixièmes de pour cent',()=>{
 it('arrondit demi à l\'écart de zéro, en entiers',()=>{
  expect(M.percentTenths(2,3)).toBe(667);
  expect(M.percentTenths(19_000,38_000)).toBe(500);
  expect(M.percentTenths(-1_000,58_000)).toBe(-17);
  expect(M.percentTenths(1,8)).toBe(125);
  expect(M.percentTenths(-1,8)).toBe(-125);
  expect(M.percentTenths(Number.MAX_SAFE_INTEGER,1)).toBe(Number.MAX_SAFE_INTEGER*1000);
 });
 it('ne donne jamais de pourcentage sans base exploitable',()=>{
  const ok={complete:true,beforeData:false};
  expect(M.compareValues({value:5,complete:true},{value:3,...ok})).toEqual({current:5,base:3,delta:2,percentTenths:667,percentReason:null});
  expect(M.compareValues({value:1,complete:true},{value:0,...ok})).toEqual({current:1,base:0,delta:1,percentTenths:null,percentReason:'BASE_ZERO'});
  expect(M.compareValues({value:5,complete:true},{value:null,complete:false,beforeData:true})).toEqual({current:5,base:null,delta:null,percentTenths:null,percentReason:'BASE_BEFORE_DATA_START'});
  expect(M.compareValues({value:218,complete:false},{value:195,...ok})).toEqual({current:218,base:195,delta:null,percentTenths:null,percentReason:'PARTIAL_COVERAGE'});
  expect(M.compareValues({value:null,complete:false},{value:195,...ok}).percentReason).toBe('PARTIAL_COVERAGE');
 });
});

describe('intervalles des séries',()=>{
 it('découpe en semaines du lundi, extrémités partielles',()=>{
  const list=M.buckets('2026-10-01','2026-11-01','week');
  expect(list.map(b=>[b.key,b.from,b.toExclusive,b.partial])).toEqual([
   ['2026-09-28','2026-10-01','2026-10-05',true],['2026-10-05','2026-10-05','2026-10-12',false],['2026-10-12','2026-10-12','2026-10-19',false],
   ['2026-10-19','2026-10-19','2026-10-26',false],['2026-10-26','2026-10-26','2026-11-01',true]]);
 });
 it('découpe en jours et en mois civils',()=>{
  expect(M.buckets('2026-10-30','2026-11-02','day').map(b=>b.key)).toEqual(['2026-10-30','2026-10-31','2026-11-01']);
  expect(M.buckets('2026-09-15','2026-11-10','month').map(b=>[b.key,b.from,b.toExclusive,b.partial])).toEqual([
   ['2026-09-01','2026-09-15','2026-10-01',true],['2026-10-01','2026-10-01','2026-11-01',false],['2026-11-01','2026-11-01','2026-11-10',true]]);
 });
 it('refuse plus de 400 intervalles',()=>{
  expect(()=>M.buckets('2026-01-01','2027-01-02','day')).not.toThrow();
  expect(()=>M.buckets('2025-01-01','2026-12-31','day')).toThrow(expect.objectContaining({code:'PERIOD_TOO_LARGE'}));
 });
});

describe('entiers et paramètres',()=>{
 it('refuse un cumul hors des entiers sûrs',()=>{
  expect(M.safeInteger('9007199254740991')).toBe(Number.MAX_SAFE_INTEGER);
  expect(()=>M.safeInteger('9007199254740992')).toThrow(expect.objectContaining({code:'AMOUNT_OUT_OF_RANGE'}));
  expect(M.safeInteger(null)).toBe(0);
 });
 it('valide strictement les paramètres',()=>{
  const ok={domain:'activity',from:'2026-10-01',toExclusive:'2026-11-01'};
  expect(M.metricsQuery.parse(ok).compare).toBe('none');
  expect(()=>M.metricsQuery.parse({...ok,extra:'1'})).toThrow();
  expect(()=>M.metricsQuery.parse({...ok,from:'2026-13-01'})).toThrow();
  expect(()=>M.metricsQuery.parse({...ok,instructorMembershipId:'pas-un-uuid'})).toThrow();
  expect(()=>M.seriesQuery.parse({from:'2026-10-01',toExclusive:'2026-11-01',granularity:'year',measures:'L01'})).toThrow();
  expect(()=>M.seriesQuery.parse({from:'2026-10-01',toExclusive:'2026-11-01',granularity:'week',measures:'L01,L02,L03,L04,L05,L06'})).toThrow();
  expect(M.detailsQuery.parse({measure:'F06',part:'a',from:'2026-10-01',toExclusive:'2026-11-01'}).limit).toBe(50);
  expect(()=>M.detailsQuery.parse({measure:'L01',from:'2026-10-01',toExclusive:'2026-11-01',limit:'101'})).toThrow();
 });
 it('le dictionnaire ne contient aucun identifiant en double',()=>{
  expect(new Set(M.definitions.map(d=>d.id)).size).toBe(M.definitions.length);
  expect(M.definitions.filter(d=>d.domain==='finance').map(d=>d.id)).toEqual(['F01','F02','F03','F04','F05','F06','F07']);
 });
});

describe('CSV (D8)',()=>{
 it('neutralise les formules des cellules texte',()=>{
  for(const start of ['=','+','-','@','\t','\r'])expect(M.textCell(`${start}SUM(A1)`)).toMatch(/^"?'/);
  expect(M.textCell('=1+1')).toBe(`'=1+1`);
  expect(M.textCell('Lou Monitrice')).toBe('Lou Monitrice');
  expect(M.textCell(null)).toBe('');
 });
 it('échappe séparateur, guillemets et sauts de ligne, accents conservés',()=>{
  expect(M.textCell('a;b')).toBe('"a;b"');
  expect(M.textCell('dit "oui"')).toBe('"dit ""oui"""');
  expect(M.textCell('ligne 1\nligne 2')).toBe('"ligne 1\nligne 2"');
  expect(M.textCell('=cmd;x')).toBe(`"'=cmd;x"`);
  expect(M.textCell('Élodie Müller')).toBe('Élodie Müller');
 });
 it('assemble un document UTF-8 avec BOM, CRLF et en-têtes stables',()=>{
  const text=M.csvDocument([['definitionsVersion','2026-10-31.1'],['complete','true']],[[M.textCell('LESSON'),M.textCell('id'),'','COMPLETED','','','','','1','2700','10000','CHF']]);
  expect(text.startsWith('﻿#definitionsVersion;2026-10-31.1\r\n#complete;true\r\n')).toBe(true);
  expect(text).toContain('\r\nline_kind;line_id;event_at;status;instructor_id;instructor_name;category_code;product_key;quantity;duration_seconds;amount_cents;currency\r\n');
  expect(text.endsWith('LESSON;id;;COMPLETED;;;;;1;2700;10000;CHF\r\n')).toBe(true);
  expect(M.numberCell(null)).toBe('');
  expect(M.numberCell(0)).toBe('0');
 });
});
