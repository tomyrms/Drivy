#!/usr/bin/env bash
# Installe un navigateur Playwright et ses dépendances système sur un runner GitHub Ubuntu.
#
# Cause des échecs constatés les 5 et 11 novembre 2026 : l'image du runner désigne le miroir apt
# azure.archive.ubuntu.com (/etc/apt/apt-mirrors.txt). Sur certains runners, la résolution DNS de ce
# seul nom échoue (« Temporary failure resolving »), apt attend 20 s par fichier puis `--with-deps`
# échoue sur les polices manquantes de l'image. Le même workflow réussit sur un runner dont le DNS
# répond : ce n'est pas une différence push / pull request / dispatch.
#
# Correctif : diagnostiquer le DNS, retirer du miroir tout hôte qui ne se résout pas (les miroirs
# officiels archive.ubuntu.com et security.ubuntu.com restent), réduire les délais apt, réessayer.
# Aucun secret, aucune donnée de personne : seuls des noms d'hôtes publics sont écrits dans le journal.
set -euo pipefail

browser="${1:?navigateur Playwright attendu (chromium, msedge…)}"
cli="infra/dev/node_modules/playwright-core/cli.js"
mirrors="/etc/apt/apt-mirrors.txt"

resolves() {
  local host="$1" try
  for try in 1 2 3; do
    if getent hosts "$host" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}

if [ -f "$mirrors" ]; then
  echo "::group::Miroirs apt et résolution DNS"
  kept="$(mktemp)"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    host="$(printf '%s' "$line" | sed -E 's#^[a-z]+://([^/[:space:]]+).*#\1#')"
    if resolves "$host"; then
      echo "miroir conservé : $host"
      printf '%s\n' "$line" >>"$kept"
    else
      echo "miroir retiré (DNS muet) : $host"
    fi
  done <"$mirrors"
  if [ ! -s "$kept" ]; then
    echo "aucun miroir résolu : repli sur les miroirs officiels"
    printf 'https://archive.ubuntu.com/ubuntu/\tpriority:1\nhttps://security.ubuntu.com/ubuntu/\tpriority:2\n' >"$kept"
  fi
  sudo install -m 0644 "$kept" "$mirrors"
  rm -f "$kept"
  echo "::endgroup::"
fi

# Délais courts et nouvelles tentatives : un hôte muet coûte quelques secondes, pas vingt par fichier.
sudo tee /etc/apt/apt.conf.d/99drivy-ci >/dev/null <<'APT'
Acquire::Retries "3";
Acquire::http::Timeout "15";
Acquire::https::Timeout "15";
APT

for attempt in 1 2 3; do
  if node "$cli" install --with-deps "$browser"; then
    exit 0
  fi
  echo "Installation du navigateur : tentative $attempt en échec."
  sleep $((attempt * 10))
done
exit 1
