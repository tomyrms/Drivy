import { createHmac,hkdfSync,randomBytes } from 'node:crypto';

// Code d'invitation : 8 caractères sans O/0/I/1 ambigus (32 symboles, soit 40 bits). 256 est multiple de 32 : l'octet modulo 32 est uniforme.
const codeAlphabet='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export function generateInvitationCode():string {
  const bytes=randomBytes(8);const chars=Array.from(bytes,byte=>codeAlphabet[byte%32]).join('');return `${chars.slice(0,4)}-${chars.slice(4)}`;
}
/** Saisie tolérante : majuscules, sans espaces ni tirets. C'est cette forme, et elle seule, qui entre dans l'empreinte. */
export const normalizeInvitationCode=(code:string)=>code.toUpperCase().replace(/[\s-]/g,'');

/** Étiquette de dérivation : un autre usage du même secret obtient une autre clé. */
export const invitationCodeKeyLabel='drivy/invitation-code/v1';

/**
 * Empreinte d'un code : HMAC-SHA256 du code normalisé, avec une clé serveur. Un code de 40 bits se devine hors ligne en quelques minutes
 * sur un GPU à partir d'un simple SHA-256 (base copiée, sauvegarde) ; avec la clé, la base seule ne permet plus de deviner un code.
 * La clé se dérive par HKDF-SHA256 de `INVITATION_CODE_SECRET` s'il est défini, sinon du secret de curseur de l'API : aucune
 * configuration nouvelle n'est nécessaire. Changer l'un de ces secrets invalide les codes en attente (un renvoi en génère un nouveau).
 * Les jetons des liens e-mail (256 bits aléatoires) gardent leur SHA-256 : ils ne se devinent pas.
 * Le résultat fait 64 caractères hexadécimaux, comme token_hash l'exige.
 */
export function invitationCodeHasher(cursorSecret:string,dedicatedSecret?:string):(code:string)=>string {
  const key=Buffer.from(hkdfSync('sha256',dedicatedSecret ?? cursorSecret,Buffer.alloc(0),invitationCodeKeyLabel,32));
  return code=>createHmac('sha256',key).update(normalizeInvitationCode(code)).digest('hex');
}
