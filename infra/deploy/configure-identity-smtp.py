#!/usr/bin/env python3
"""Configure le relais SMTP du realm Drivy (#50), sans jamais activer la récupération.

Le choix du fournisseur SMTP appartient au porteur. Ce script ne le fait pas : il valide des paramètres
fournis hors dépôt, puis écrit uniquement `smtpServer` dans le realm via l'API d'administration de Keycloak.

- Aucun secret en dépôt, en argument de ligne de commande ni dans le journal. Les paramètres SMTP viennent
  d'un fichier JSON en mode 0600 (par défaut /root/drivy-identity-smtp.json), le jeton d'administration d'un
  fichier en mode 0600 (--token-file). Le mot de passe SMTP n'est jamais affiché, même masqué en partie.
- Simulation par défaut : sans --apply, rien n'est écrit et l'état courant n'est même pas modifié.
- N'écrit ni `resetPasswordAllowed`, ni `verifyEmail`, ni aucun autre champ. L'activation de la
  récupération reste une étape distincte et manuelle (docs/implementation/recuperation-activation-50.md).
- Refuse les hôtes d'exemple (`example.*`, `.invalid`, `.test`, `localhost`) et un relais sans chiffrement qui
  demande une authentification, sauf boucle locale.
"""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import stat
import sys
import urllib.error
import urllib.request

DEFAULT_PARAMS = Path('/root/drivy-identity-smtp.json')
ALLOWED_KEYS = {'host', 'port', 'from', 'fromDisplayName', 'replyTo', 'security', 'auth', 'user', 'password'}
SECURITY = ('starttls', 'ssl', 'none')
HOST = re.compile(r'^(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$')
ADDRESS = re.compile(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]{1,64}@([A-Za-z0-9-]{1,63}\.)+[A-Za-z]{2,63}$")
PLACEHOLDER_SUFFIXES = ('.invalid', '.test', '.example', '.localhost')
PLACEHOLDER_NAMES = ('localhost', 'example.com', 'example.org', 'example.net')


class ConfigError(Exception):
    """Message sans valeur de paramètre : jamais d'hôte, d'adresse ni de secret."""


def is_loopback(host):
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def is_placeholder(host):
    lowered = host.lower()
    return lowered in PLACEHOLDER_NAMES or lowered.endswith(PLACEHOLDER_SUFFIXES) or \
        any(lowered.endswith('.' + name) for name in PLACEHOLDER_NAMES)


def read_private_file(path):
    """Lit un fichier JSON secret, refuse un fichier lisible par un autre compte ou un lien."""
    info = os.lstat(path)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ConfigError('Le fichier de paramètres doit être un fichier ordinaire.')
    if info.st_mode & 0o077:
        raise ConfigError('Le fichier de paramètres doit être en mode 0600.')
    if hasattr(os, 'geteuid') and info.st_uid != os.geteuid():
        raise ConfigError('Le fichier de paramètres doit appartenir à l\'exécutant.')
    return Path(path).read_text(encoding='utf-8')


def validate(params, allow_placeholder=False):
    """Retourne l'objet `smtpServer` de Keycloak, ou lève ConfigError sans citer les valeurs."""
    if not isinstance(params, dict):
        raise ConfigError('Les paramètres doivent former un objet JSON.')
    unknown = set(params) - ALLOWED_KEYS
    if unknown:
        raise ConfigError('Champ inconnu dans les paramètres : %s.' % ', '.join(sorted(unknown)))
    host = params.get('host')
    if not isinstance(host, str) or not HOST.match(host) and not is_ip(host):
        raise ConfigError('Hôte SMTP absent ou invalide (nom ou IP seuls, sans schéma ni chemin).')
    if not allow_placeholder and is_placeholder(host):
        raise ConfigError('Hôte SMTP d\'exemple refusé : indiquer le vrai relais choisi.')
    port = params.get('port')
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        raise ConfigError('Port SMTP absent ou hors de 1 à 65535.')
    security = params.get('security')
    if security not in SECURITY:
        raise ConfigError('security doit valoir starttls, ssl ou none.')
    auth = params.get('auth')
    if not isinstance(auth, bool):
        raise ConfigError('auth doit être vrai ou faux.')
    sender = params.get('from')
    if not isinstance(sender, str) or not ADDRESS.match(sender):
        raise ConfigError('Adresse d\'expédition absente ou invalide.')
    if not allow_placeholder and is_placeholder(sender.rsplit('@', 1)[1]):
        raise ConfigError('Adresse d\'expédition d\'exemple refusée.')
    result = {'host': host, 'port': str(port), 'from': sender,
              'ssl': 'true' if security == 'ssl' else 'false',
              'starttls': 'true' if security == 'starttls' else 'false',
              'auth': 'true' if auth else 'false'}
    for key, target in (('fromDisplayName', 'fromDisplayName'), ('replyTo', 'replyTo')):
        value = params.get(key)
        if value is None or value == '':
            continue
        if not isinstance(value, str) or len(value) > 120 or any(ord(c) < 32 for c in value):
            raise ConfigError('%s invalide.' % key)
        if key == 'replyTo' and not ADDRESS.match(value):
            raise ConfigError('replyTo invalide.')
        result[target] = value
    if auth:
        user, password = params.get('user'), params.get('password')
        if not isinstance(user, str) or not user or not isinstance(password, str) or not password:
            raise ConfigError('Authentification demandée : user et password sont obligatoires.')
        if security == 'none' and not is_loopback(host):
            raise ConfigError('Aucune authentification sans chiffrement hors boucle locale.')
        result['user'] = user
        result['password'] = password
    elif params.get('user') or params.get('password'):
        raise ConfigError('user ou password fournis alors que auth est faux.')
    return result


def is_ip(value):
    try:
        ipaddress.ip_address(value)
        return True
    except (ValueError, TypeError):
        return False


def redacted(smtp):
    """Vue pour le journal : le mot de passe et l'identifiant ne sont jamais reproduits."""
    shown = {k: v for k, v in smtp.items() if k not in ('password', 'user')}
    if 'password' in smtp:
        shown['password'] = '(fourni)'
    if 'user' in smtp:
        shown['user'] = '(fourni)'
    return shown


def admin_request(base, method, path, token, body=None, opener=urllib.request.urlopen):
    data = None if body is None else json.dumps(body).encode('utf-8')
    request = urllib.request.Request(base + path, data=data, method=method)
    request.add_header('Authorization', 'Bearer ' + token)
    if data is not None:
        request.add_header('Content-Type', 'application/json')
    try:
        with opener(request, timeout=15) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as error:
        return error.code, None
    except (urllib.error.URLError, TimeoutError, OSError):
        return 0, None


def run(args, opener=urllib.request.urlopen):
    try:
        params = json.loads(read_private_file(args.params))
        smtp = validate(params, allow_placeholder=args.allow_placeholder)
    except (ConfigError, OSError, ValueError) as error:
        print('Paramètres refusés : %s' % (error if isinstance(error, ConfigError) else 'fichier illisible ou JSON invalide.'),
              file=sys.stderr)
        return 2
    print('Paramètres valides : %s' % json.dumps(redacted(smtp), ensure_ascii=False, sort_keys=True))
    if not args.apply:
        print('Simulation : rien n\'est écrit. Ajouter --apply pour écrire smtpServer.')
        return 0
    try:
        token = read_private_file(args.token_file).strip()
    except (ConfigError, OSError):
        print('Jeton d\'administration illisible ou non protégé (mode 0600 exigé).', file=sys.stderr)
        return 2
    base = args.keycloak.rstrip('/')
    if not re.match(r'^https?://[^/\s?#]+(/[A-Za-z0-9._~/-]*)?$', base):
        print('URL de Keycloak invalide.', file=sys.stderr)
        return 2
    path = '/admin/realms/' + args.realm
    status, realm = admin_request(base, 'GET', path, token, opener=opener)
    if status != 200 or not isinstance(realm, dict):
        print('Realm illisible (statut %s) : rien n\'a été écrit.' % status, file=sys.stderr)
        return 1
    if realm.get('resetPasswordAllowed') is not False:
        print('Refus : la récupération est déjà autorisée dans le realm. Cette étape ne l\'active ni ne la suppose.',
              file=sys.stderr)
        return 1
    # PUT du realm complet : Keycloak remplace les champs fournis. On ne renvoie que le champ voulu.
    status, _ = admin_request(base, 'PUT', path, token, {'smtpServer': smtp}, opener=opener)
    if status not in (200, 204):
        print('Écriture refusée (statut %s) : smtpServer inchangé à vérifier.' % status, file=sys.stderr)
        return 1
    print('smtpServer écrit. resetPasswordAllowed est resté faux : la récupération n\'est pas activée.')
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--params', default=str(DEFAULT_PARAMS), help='JSON des paramètres SMTP, mode 0600')
    parser.add_argument('--token-file', default='/root/drivy-identity-admin-token', help='jeton d\'administration, mode 0600')
    parser.add_argument('--keycloak', default='http://127.0.0.1:8081/identity', help='origine et chemin relatif de Keycloak')
    parser.add_argument('--realm', default='drivy')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--allow-placeholder', action='store_true', help='recette synthétique seulement')
    return run(parser.parse_args(argv))


if __name__ == '__main__':
    sys.exit(main())
