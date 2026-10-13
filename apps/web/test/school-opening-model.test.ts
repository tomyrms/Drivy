import { expect,test } from 'vitest';
import { randomBytes,randomUUID } from 'node:crypto';
import { readOpeningLink,schoolOpeningDestination,openingFailure,openingFieldErrors } from '../client/school-opening-model.js';
import { RequestFailure } from '../client/protocol.js';
test('le fragment canonique est supprimé immédiatement, sans paramètre transmis au réseau',()=>{
  const token=randomBytes(32).toString('base64url');let clean='';const parsed=readOpeningLink({pathname:'/app/ouvrir',search:'',hash:`#token=${token}`},url=>{clean=url;});
  expect(parsed.token===token).toBe(true);expect(parsed.error).toBe(false);expect(clean).toBe('/app/ouvrir');
});
test('un token hors page, dupliqué, complété ou malformé est refusé et supprimé',()=>{
  const token=randomBytes(32).toString('base64url');for(const [pathname,hash] of [['/app/ouvrir',`#token=${token}&token=${token}`],['/app/ouvrir',`#token=${token}&extra=value`],['/app/gestion',`#token=${token}`],['/app/ouvrir','#token=bad']]){
    let removed=false;const parsed=readOpeningLink({pathname:pathname!,hash:hash!,search:''},()=>{removed=true;});expect(parsed).toEqual({token:null,error:true});expect(removed).toBe(true);
  }
});
test('reprise vers la préparation ou agenda selon le statut confirmé',()=>{
  const schoolId=randomUUID(),receipt={schoolId,schoolName:'École synthétique',status:'DRAFT' as const,membershipId:randomUUID(),roles:['ADMIN'],grants:[],accessEpoch:1,operationId:randomUUID(),committedAt:new Date().toISOString()};
  expect(schoolOpeningDestination(receipt)).toBe(`/app/gestion/${schoolId}/apercu`);expect(schoolOpeningDestination({...receipt,status:'ACTIVE'})).toBe(`/app/gestion/${schoolId}/agenda`);
  expect(openingFailure(new RequestFailure('OPENING_LINK_USED'))).toContain('déjà été utilisé');
});

test('les erreurs de saisie ciblent les champs avant toute création, sans confondre refus et réponse perdue',()=>{
  const fields={schoolName:'École synthétique',displayName:'Responsable synthétique',contactEmail:'school@example.invalid',contactPhone:null,timeZone:'Europe/Zurich',instructs:false};
  expect(openingFieldErrors(fields)).toEqual({});
  expect(openingFieldErrors({...fields,schoolName:'  ',displayName:'  ',timeZone:'Zurich'})).toEqual({
    schoolName:expect.stringContaining('nom de l’école'),displayName:expect.stringContaining('votre nom'),timeZone:expect.stringContaining('Europe/Zurich'),
  });
  expect(openingFieldErrors({...fields,contactEmail:'adresse invalide',contactPhone:'   '})).toEqual({contactEmail:expect.stringContaining('e-mail'),contactPhone:expect.stringContaining('numéro')});
  expect(openingFieldErrors({...fields,timeZone:'UTC'})).toEqual({});
  expect(openingFieldErrors({...fields,timeZone:'+01:00'})).toHaveProperty('timeZone');
  expect(openingFailure(new RequestFailure('INVALID_REQUEST',400))).toContain('ne sont pas valides');
});
