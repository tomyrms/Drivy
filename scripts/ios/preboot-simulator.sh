#!/usr/bin/env bash
# Démarre l'iPhone de test pendant la compilation. Le premier démarrage d'un simulateur sur un runner neuf
# (migration des données) dure de deux à cinq minutes ; le lancer avant la compilation le cache derrière elle.
# Mesuré sur 209 démarrages : médiane 143 s, 90e centile 308 s, jusqu'à 461 s.
# Meilleur effort : aucune erreur ici ne fait échouer le job, test-simulator.sh redémarre l'appareil si besoin.
source scripts/ios/test-selection.sh
# Les captures et la campagne iPad gèrent leurs propres appareils ; seul l'iPhone des tests est concerné.
if [[ "$visual_only" == 1 ]]; then
  echo 'Captures visuelles : pas de démarrage anticipé.'
  exit 0
fi
source scripts/ios/simulator-iphone.sh
device_id=$(iphone_simulator_id) || { echo 'Aucun iPhone à démarrer à l’avance.'; exit 0; }
mkdir -p artifacts/ios
printf '%s\n' "$device_id" > artifacts/ios/preboot-iphone.txt
# Détaché et sans flux hérités : l'étape ne doit ni attendre la fin du démarrage ni retenir ses journaux.
# Le démarrage lui-même se poursuit dans le service CoreSimulator, pas dans ce processus.
( xcrun simctl boot "$device_id" || true ) > /dev/null 2>&1 < /dev/null &
disown || true
echo "Démarrage anticipé de l'iPhone de test lancé."
