#!/usr/bin/env bash
# Source uniquement. Une seule règle de choix de l'iPhone de test, partagée par le démarrage anticipé
# (preboot-simulator.sh) et par l'exécution (test-simulator.sh) : ils doivent viser le même appareil.
iphone_simulator_id() {
  xcrun simctl list devices available -j | python3 -c '
import json,sys
devices=json.load(sys.stdin)["devices"]
candidates=[d for runtime,items in devices.items() if "iOS" in runtime for d in items if d.get("isAvailable") and d["name"].startswith("iPhone")]
if not candidates: raise SystemExit("Aucun simulateur iPhone disponible")
print(candidates[0]["udid"])
'
}
