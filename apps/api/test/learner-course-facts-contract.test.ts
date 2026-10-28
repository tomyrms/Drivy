import {readFile} from 'node:fs/promises';
import {expect,it} from 'vitest';
import {z} from 'zod';
import {learnerCourseFactsSchema} from '../src/course-facts.js';

it('le contrat des faits de cours suit exactement la projection servie, sans certificat implicite',async()=>{
 const contract=JSON.parse(await readFile(new URL('../contracts/learner-course-facts.json',import.meta.url),'utf8')) as {$defs:Record<string,unknown>};
 const {$schema:_,...expected}=z.toJSONSchema(learnerCourseFactsSchema);
 expect(contract.$defs.LearnerCourseFacts).toEqual(expected);
 expect(JSON.stringify(expected)).not.toMatch(/completedOn|certificate|amountCents|note|displayName/);
});
