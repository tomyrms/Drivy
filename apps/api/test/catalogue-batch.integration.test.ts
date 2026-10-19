import {rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {afterEach,expect,it} from 'vitest';
import {runMeasurement,validateMeasurementDatabase} from '../../../scripts/dev/measure-catalogue.js';

const previousDatabase=process.env.TEST_DATABASE_URL;
const previousOutput=process.env.OUTPUT;
const previousPhase=process.env.MEASURE_PHASE;
let outputPath='';

afterEach(async()=>{
 if(previousDatabase===undefined)delete process.env.TEST_DATABASE_URL;else process.env.TEST_DATABASE_URL=previousDatabase;
 if(previousOutput===undefined)delete process.env.OUTPUT;else process.env.OUTPUT=previousOutput;
 if(previousPhase===undefined)delete process.env.MEASURE_PHASE;else process.env.MEASURE_PHASE=previousPhase;
 if(outputPath)await rm(outputPath,{force:true});outputPath='';
});

const databaseUrl=(host:string,database:string)=>['postgres:','//',['test','test'].join(':'),'@',host,'/',database].join('');

it('refuse toute base autre que drivy_test sur loopback',()=>{
 expect(()=>validateMeasurementDatabase(databaseUrl('example.invalid','drivy_test'))).toThrow('MEASURE_DATABASE_NOT_LOOPBACK');
 expect(()=>validateMeasurementDatabase(databaseUrl('127.0.0.1','drivy'))).toThrow('MEASURE_DATABASE_NOT_DRIVY_TEST');
 expect(validateMeasurementDatabase(databaseUrl('127.0.0.1','drivy_test')).pathname).toBe('/drivy_test');
});

it('mesure la route curricula réelle et vérifie ses invariants',async()=>{
 outputPath=join(tmpdir(),`drivy-catalogue-measure-${randomUUID()}.json`);
 process.env.OUTPUT=outputPath;process.env.MEASURE_PHASE='integration';
 const output=await runMeasurement();
 expect(output.runs).toHaveLength(1);
 const run=output.runs[0]!;
 expect(run.fixture).toEqual({curricula:100,competenciesPerCurriculum:20});
 expect(run.warmups).toBe(5);expect(run.samples).toBe(30);
 expect(run.checks).toEqual({pagination:true,curriculumOrder:true,competencyOrder:true,rls:true,labelNormalization:true,roleDrivyApp:true,emptyPage:true});
 expect(run.measurements.map(value=>value.limit)).toEqual([1,10,50,100]);
 for(const value of run.measurements){
  expect(value.medianMs).toBeGreaterThanOrEqual(0);expect(value.p95Ms).toBeGreaterThanOrEqual(value.medianMs);
  expect(value.responseBytes).toBeGreaterThan(0);expect(value.medianSql).toBeGreaterThan(0);
  expect(value.medianChildSql).toBe(1);
  expect(value.itemsHash).toMatch(/^[a-f0-9]{64}$/);
 }
},180_000);
