# Contournement du proxy Cloudflare pour Drivy (#93) — 21 octobre 2026

État : **préparé, bascule en attente**. Aucune modification de DNS, de Caddy, du NAT ou de l'IPA.

## Inventaire (lecture seule)

| Élément | Constat |
| --- | --- |
| Serveurs de noms `shulker.ch` | Cloudflare (`holly`, `vern`) |
| `drivy.shulker.ch` | Proxied : IPv4/IPv6 d'anycast Cloudflare |
| Caddy CT109 | 2.11.2, écoute `*:80` et `*:443`, CrowdSec actif sur le site Drivy |
| Certificat Drivy | Let's Encrypt (YE2), échéance 23 novembre 2026, obtenu sans défi DNS (aucun `acme_dns` global) : renouvellement HTTP-01/TLS-ALPN-01 possible en direct |
| Accès direct HTTPS | Valide (`ssl_verify_result=0`) avec le nom `drivy.shulker.ch` sur l'IP publique |
| Ports joignables sur l'IP publique (test depuis le LAN, NAT en boucle) | 80, 443 seulement. Fermés : 22, 3000, 3001, 3002, 5000, 5432, 8006, 8080, 8081, 8090, 9000, 9001 |
| Filtrage « IP Cloudflare uniquement » | Aucun dans Caddy, CT109 ni le pare-feu Proxmox |
| IPv6 publique du homelab | Aucune sortie IPv6 : l'enregistrement direct sera IPv4 seul |
| `X-Forwarded-For` | Réécrit par Caddy avec `{remote_host}`. Derrière Cloudflare, c'est une IP Cloudflare : la limitation par adresse du web et CrowdSec voyaient donc les nœuds Cloudflare, pas les visiteurs. En direct, ils voient la vraie adresse. |

L'IP publique n'est pas consignée ici.

## Mesures avant bascule (Wi-Fi local, médiane de 5 essais)

| Chemin | Via Cloudflare TLS / TTFB | Direct IP publique TLS / TTFB | LAN TLS / TTFB |
| --- | --- | --- | --- |
| Découverte OIDC | 988 / 3 848 ms | 17 / 20 ms | 14 / 17 ms |
| `/app/` | 607 / 1 368 ms | 15 / 17 ms | 13 / 14 ms |
| `/refonte/` (404 attendu) | 968 / 1 938 ms | 17 / 19 ms | 14 / 15 ms |

Le test direct depuis le LAN passe par le NAT en boucle de la box : il ne mesure pas la 5G. Mesure 5G à faire après bascule.

## Bascule (une seule action, dans Cloudflare)

DNS → `shulker.ch` → enregistrement `drivy` : **Proxied → DNS only**. Ne toucher à aucun autre enregistrement.

- Noter avant : type (A ou CNAME), cible, TTL.
- Si c'est un A : vérifier qu'il contient l'IP publique actuelle. Si c'est un CNAME vers un nom dynamique : vérifier que ce nom résout vers la même IP.
- Les AAAA d'anycast disparaissent d'eux-mêmes. Ne pas ajouter d'AAAA.
- URL publiques inchangées : **pas de nouvel IPA**.

Portée : le trafic HTTP(S) ne traverse plus Cloudflare. **Le DNS autoritatif reste chez Cloudflare.** Quitter aussi le DNS est une phase séparée (inventaire MX/TXT/SPF/DKIM/DMARC/CAA/DNSSEC de toute la zone).

## Risques acceptés par la bascule

- IP publique du homelab visible pour `drivy.shulker.ch`.
- Plus de WAF, de filtrage de bots, ni de protection DDoS Cloudflare pour Drivy. Restent : CrowdSec, limitation de connexion du web, refus 404 des chemins internes.
- Plus de cache Cloudflare sur `/identity/resources/*` (fichiers légers, servis en ~15 ms).
- Les autres sous-domaines de `shulker.ch` ne changent pas.

## Contrôles après bascule

1. `nslookup drivy.shulker.ch 1.1.1.1` ne renvoie plus `188.114.x.x` ni `2a06:98c1:…`.
2. `python .local/cf-measure.py 5` : codes 200/200/404, `verify=0`.
3. En 5G : connexion dans l'app iOS, liste des élèves, démarrage d'une leçon, puis `/app/` dans Safari.
4. Chemins fermés : `/refonte/health/ready`, `/identity/admin/`, `/identity/realms/master/` → 404.
5. Logs Caddy/CrowdSec sur une journée : volume et blocages.

## Retour arrière

Remettre l'enregistrement `drivy` sur **Proxied**. Aucun changement Caddy à défaire. Les clients reviennent après le TTL (Auto = 300 s).
