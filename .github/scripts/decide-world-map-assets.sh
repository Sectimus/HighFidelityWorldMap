#!/usr/bin/env bash
# Works out what the generate-world-map-assets action has to generate after it
# tried the caches. Prints step outputs (redirect into $GITHUB_OUTPUT):
#   art        true when the full generator has to run (HD art, and the low-res
#              maps as a by-product)
#   lowres     true when the low-res maps are written this run (a full run, or
#              the minutes-long --lowres-only run)
#   verify     the trees to sanity-check: low-res and masks always, art only
#              when it was asked for
#   cache-hit  true when the HD and low-res art both came from the cache
#
# The zone masks are not decided here: they are always built from the traces.
#
# Inputs (environment): WANT_ART (the action's `art` input: does the caller ship
# the HD art), BYPASS, and ART_HIT / LOWRES_HIT (each restore step's cache-hit,
# empty when the step did not run).
set -euo pipefail

want_art="${WANT_ART:-true}"
bypass="${BYPASS:-false}"

# missing NAME_HIT: true when that tree has to be built.
missing() { [[ "$bypass" == "true" || "${!1:-}" != "true" ]]; }

art=false lowres=false verify="lowres masks"
if [[ "$want_art" == "true" ]]; then
  verify+=" art"
  missing ART_HIT && art=true
fi
if [[ "$art" == "true" ]] || missing LOWRES_HIT; then lowres=true; fi

echo "art=${art}"
echo "lowres=${lowres}"
echo "verify=${verify}"
echo "cache-hit=$([[ "$art" == "false" && "$lowres" == "false" ]] && echo true || echo false)"
echo "Decision: art=${art} lowres=${lowres} (want art=${want_art}, bypass=${bypass})" >&2
