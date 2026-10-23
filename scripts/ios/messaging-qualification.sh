#!/usr/bin/env bash
# Source from the repository root. Physical qualification access is explicit,
# never an assertion that messaging is generally qualified or deployed.
messaging_qualification=${DRIVY_MESSAGING_QUALIFICATION:-0}
[[ "$messaging_qualification" == 0 || "$messaging_qualification" == 1 ]] || {
  echo 'Accès Messages de qualification invalide (0 ou 1).' >&2
  exit 1
}
messaging_build_options=()
if [[ "$messaging_qualification" == 1 ]]; then
  messaging_build_options=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DRIVY_MESSAGING_QUALIFICATION')
fi
