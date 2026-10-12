/**
 * Un dossier est complet quand chaque champ que la politique applicable exige aux étapes JOIN et BEFORE_LESSON est
 * renseigné : c’est ce qui manque pour planifier une leçon (R81). Un champ facultatif ou d’une étape à venir ne rend
 * jamais un dossier incomplet. La règle s’écrit deux fois, en TypeScript pour les lectures d’un dossier et en SQL
 * pour les listes (filtre et pagination) ; `profile-completeness.integration.test.ts` vérifie qu’elles s’accordent.
 */
export const PLANNING_STAGES = ['JOIN','BEFORE_LESSON'] as const;

export interface ProfileRule { field:string; requirement:string; stage:string }
export interface ProfileValues {
  first_name:string|null; last_name:string|null; birthDate?:string|null; birth_date?:unknown;
  postal_address:unknown; contact_email:string|null; contact_phone:string|null;
}

const valueOf=(row:ProfileValues,field:string):unknown=>({
  firstName:row.first_name,lastName:row.last_name,birthDate:row.birthDate ?? row.birth_date,postalAddress:row.postal_address,
  contactEmail:row.contact_email,contactPhone:row.contact_phone,
} as Record<string,unknown>)[field];

/** Les règles exigées aux étapes données dont le champ est absent ou vide, dans l’ordre de la politique. */
export function missingRules<T extends ProfileRule>(row:ProfileValues,rules:readonly T[],stages:readonly string[]):T[] {
  return rules.filter(rule=>{
    if(rule.requirement!=='REQUIRED' || !stages.includes(rule.stage)) return false;
    const value=valueOf(row,rule.field);
    return value===null || value===undefined || value==='';
  });
}

/** `MINIMAL` tant que l’identité manque, `ACTION_REQUIRED` s’il manque autre chose, sinon `READY`. */
export function readinessOf(missing:readonly string[]):'MINIMAL'|'ACTION_REQUIRED'|'READY' {
  if(missing.length===0) return 'READY';
  return missing.some(field=>field==='firstName' || field==='lastName')?'MINIMAL':'ACTION_REQUIRED';
}

/**
 * La même règle pour une ligne `drivy.learner_profile` d’alias `l` : `mp.fields`, les champs manquants dans l’ordre de
 * la politique applicable (aucune politique : rien n’est exigé). À joindre avec `LEFT JOIN LATERAL … mp ON true`.
 */
export const missingProfileFieldsLateral=(alias:string)=>`LEFT JOIN LATERAL (
  SELECT coalesce(array_agg(r.rule->>'field' ORDER BY r.ord),'{}'::text[]) AS fields
  FROM drivy.profile_field_policy pol CROSS JOIN LATERAL jsonb_array_elements(pol.fields) WITH ORDINALITY AS r(rule,ord)
  WHERE pol.id=drivy.applicable_profile_policy(${alias}.school_id) AND r.rule->>'requirement'='REQUIRED'
    AND r.rule->>'stage' IN (${PLANNING_STAGES.map(stage=>`'${stage}'`).join(',')})
    AND CASE r.rule->>'field'
      WHEN 'firstName' THEN nullif(${alias}.first_name,'') IS NULL WHEN 'lastName' THEN nullif(${alias}.last_name,'') IS NULL
      WHEN 'birthDate' THEN ${alias}.birth_date IS NULL WHEN 'postalAddress' THEN ${alias}.postal_address IS NULL
      WHEN 'contactEmail' THEN nullif(${alias}.contact_email,'') IS NULL WHEN 'contactPhone' THEN nullif(${alias}.contact_phone,'') IS NULL
      ELSE false END
) mp ON true`;

/** `readinessOf` en SQL, sur `mp.fields`. */
export const readinessSql=`CASE WHEN cardinality(mp.fields)=0 THEN 'READY'
  WHEN mp.fields && ARRAY['firstName','lastName']::text[] THEN 'MINIMAL' ELSE 'ACTION_REQUIRED' END`;
