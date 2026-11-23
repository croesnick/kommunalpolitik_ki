#!/bin/sh
# PROTOTYPE: checks all proofs, then prints the D.1 demo.
set -eu
export ELAN_HOME="${ELAN_HOME:-$HOME/.cache/elan}"
export PATH="$ELAN_HOME/bin:$PATH"
cd "$(dirname "$0")"
lake build
lake env lean Demo.lean
