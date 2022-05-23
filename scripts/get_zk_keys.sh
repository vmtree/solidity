#!/usr/bin/env bash

wget \
    https://storageapi.fleek.co/10fd7cca-1427-4b72-9cd1-d81b5da792dd-bucket/update.wasm \
    -O ./circuits/update.wasm

wget \
    https://storageapi.fleek.co/10fd7cca-1427-4b72-9cd1-d81b5da792dd-bucket/update_verifier.json \
    -O ./circuits/updateVerifier.json

wget \
    https://storageapi.fleek.co/10fd7cca-1427-4b72-9cd1-d81b5da792dd-bucket/update_final.zkey \
    -O ./circuits/update.zkey

wget \
    https://storageapi.fleek.co/10fd7cca-1427-4b72-9cd1-d81b5da792dd-bucket/mass_update.wasm \
    -O ./circuits/massUpdate.wasm

wget \
    https://storageapi.fleek.co/10fd7cca-1427-4b72-9cd1-d81b5da792dd-bucket/mass_update_verifier.json \
    -O ./circuits/massUpdateVerifier.json

wget \
    https://storageapi.fleek.co/10fd7cca-1427-4b72-9cd1-d81b5da792dd-bucket/mass_update_final.zkey \
    -O ./circuits/massUpdate.zkey