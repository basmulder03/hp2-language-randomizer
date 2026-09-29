#!/usr/bin/env bash
# Wrapper: see tools/hp2mod.py.
exec python3 "$(dirname "$0")/tools/hp2mod.py" run "$@"
