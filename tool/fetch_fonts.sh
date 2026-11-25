#!/usr/bin/env bash
set -euo pipefail

mkdir -p assets/fonts

curl --fail --location --retry 3 \
  'https://raw.githubusercontent.com/google/fonts/main/ofl/cairo/Cairo%5Bslnt%2Cwght%5D.ttf' \
  --output assets/fonts/Cairo.ttf
curl --fail --location --retry 3 \
  'https://raw.githubusercontent.com/google/fonts/main/ofl/cairo/OFL.txt' \
  --output assets/fonts/Cairo-OFL.txt

curl --fail --location --retry 3 \
  'https://raw.githubusercontent.com/google/fonts/main/ofl/opensans/OpenSans%5Bwdth%2Cwght%5D.ttf' \
  --output assets/fonts/OpenSans.ttf
curl --fail --location --retry 3 \
  'https://raw.githubusercontent.com/google/fonts/main/ofl/opensans/OFL.txt' \
  --output assets/fonts/OpenSans-OFL.txt

test -s assets/fonts/Cairo.ttf
test -s assets/fonts/OpenSans.ttf
