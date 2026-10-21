/**
 * Photo de profil : JPEG seulement, nettoyé sans dépendance de décodage.
 * Le fichier est relu segment par segment. Les segments de métadonnées (APP1 à APP15 : EXIF, position GPS, XMP, ICC…, et COM)
 * sont retirés ; seuls restent la structure d'image (DQT, SOF, DHT, DRI, SOS et les données compressées) et l'en-tête JFIF.
 * Un fichier qui ne suit pas cette structure est refusé : rien d'autre qu'une image JPEG n'est stocké.
 */
export interface CleanJpeg { data: Buffer; width: number; height: number }

export const PHOTO_MAX_BYTES = 262_144;
export const PHOTO_MIN_SIDE = 64;
export const PHOTO_MAX_SIDE = 1024;

const SOF = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);

export function cleanJpeg(input: Buffer): CleanJpeg | undefined {
  if (input.length < 4 || input.length > PHOTO_MAX_BYTES * 2 || input[0] !== 0xff || input[1] !== 0xd8) return undefined;
  const kept: Buffer[] = [Buffer.from([0xff, 0xd8])];
  let offset = 2, width = 0, height = 0, scanned = false;
  while (offset < input.length) {
    if (input[offset] !== 0xff) return undefined;
    let marker = input[offset + 1];
    // Octets de bourrage 0xFF autorisés entre deux segments.
    while (marker === 0xff && offset + 2 < input.length) { offset += 1; marker = input[offset + 1]; }
    if (marker === undefined) return undefined;
    if (marker === 0xd9) { kept.push(Buffer.from([0xff, 0xd9])); break; }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) { offset += 2; continue; }
    if (offset + 4 > input.length) return undefined;
    const length = input.readUInt16BE(offset + 2);
    if (length < 2 || offset + 2 + length > input.length) return undefined;
    const segment = input.subarray(offset, offset + 2 + length);
    if (SOF.has(marker)) {
      if (length < 8) return undefined;
      height = input.readUInt16BE(offset + 5); width = input.readUInt16BE(offset + 7);
    }
    const metadata = (marker >= 0xe1 && marker <= 0xef) || marker === 0xfe;
    const jfif = marker === 0xe0 && input.subarray(offset + 4, offset + 9).toString('latin1') === 'JFIF\u0000';
    if (marker === 0xe0 && !jfif) { offset += 2 + length; continue; }
    if (!metadata) kept.push(segment);
    offset += 2 + length;
    if (marker === 0xda) {
      // Données compressées jusqu'au prochain marqueur qui n'est ni un octet échappé (FF00) ni un redémarrage (FFD0-D7).
      let end = offset;
      while (end + 1 < input.length) {
        if (input[end] === 0xff) {
          const next = input[end + 1]!;
          if (next !== 0x00 && !(next >= 0xd0 && next <= 0xd7)) break;
        }
        end += 1;
      }
      if (end + 1 >= input.length) return undefined;
      kept.push(input.subarray(offset, end));
      offset = end;
      scanned = true;
    }
  }
  if (!scanned || kept[kept.length - 1]![1] !== 0xd9) return undefined;
  if (width < PHOTO_MIN_SIDE || height < PHOTO_MIN_SIDE || width > PHOTO_MAX_SIDE || height > PHOTO_MAX_SIDE) return undefined;
  const data = Buffer.concat(kept);
  if (data.length > PHOTO_MAX_BYTES) return undefined;
  return { data, width, height };
}
