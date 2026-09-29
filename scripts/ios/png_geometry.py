"""Read storage and EXIF display geometry without decoding or rewriting PNG pixels.

Returns stored width/height, displayed width/height and EXIF orientation (1 when absent).
"""

import struct

def png_geometry(payload: bytes) -> tuple[int, int, int, int, int]:
    if len(payload) < 24 or payload[:8] != b'\x89PNG\r\n\x1a\n' or payload[12:16] != b'IHDR':
        raise ValueError('La capture système exportée ne constitue pas un PNG valide.')
    width, height = struct.unpack('>II', payload[16:24])
    orientation, exif_seen = 1, False
    offset = 8
    while offset + 12 <= len(payload):
        length = struct.unpack('>I', payload[offset:offset + 4])[0]
        kind = payload[offset + 4:offset + 8]
        end = offset + 12 + length
        if end > len(payload):
            raise ValueError('Métadonnées PNG tronquées.')
        if kind == b'eXIf':
            if exif_seen:
                raise ValueError('Orientation PNG ambiguë : plusieurs blocs EXIF.')
            exif_seen = True
            data = payload[offset + 8:offset + 8 + length]
            if len(data) < 8 or data[:2] not in (b'II', b'MM'):
                raise ValueError('Entête EXIF PNG invalide.')
            order = '<' if data[:2] == b'II' else '>'
            if struct.unpack(order + 'H', data[2:4])[0] != 42:
                raise ValueError('Entête TIFF EXIF invalide.')
            ifd = struct.unpack(order + 'I', data[4:8])[0]
            if ifd < 8 or ifd + 2 > len(data):
                raise ValueError('Répertoire EXIF PNG invalide.')
            count = struct.unpack(order + 'H', data[ifd:ifd + 2])[0]
            if ifd + 2 + count * 12 > len(data):
                raise ValueError('Répertoire EXIF PNG tronqué.')
            orientation_seen = False
            for index in range(count):
                start = ifd + 2 + index * 12
                tag, field_type, field_count = struct.unpack(order + 'HHI', data[start:start + 8])
                if tag == 274:
                    if orientation_seen or field_type != 3 or field_count != 1:
                        raise ValueError('Champ orientation EXIF PNG invalide ou ambigu.')
                    orientation_seen = True
                    orientation = struct.unpack(order + 'H', data[start + 8:start + 10])[0]
                    if orientation not in range(1, 9):
                        raise ValueError('Valeur orientation EXIF PNG invalide.')
        offset = end
        if kind == b'IEND':
            break
    display_width, display_height = (height, width) if orientation in (5, 6, 7, 8) else (width, height)
    return width, height, display_width, display_height, orientation
