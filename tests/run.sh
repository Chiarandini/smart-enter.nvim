#!/usr/bin/env bash
# Run the smart-enter test suite headlessly.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
nvim --headless \
	--cmd "set rtp+=$here" \
	-c "luafile $here/tests/smart_enter_spec.lua" \
	-c "qa!"
