#!/usr/bin/env bash

echo "Fetching zk keys from ipfs"

wget \
    https://storageapi.fleek.co/10fd7cca-1427-4b72-9cd1-d81b5da792dd-bucket/poseidon-circuits/mass_update.wasm \
    -O ./circuits/mass_update.wasm

wget \
    https://storageapi.fleek.co/10fd7cca-1427-4b72-9cd1-d81b5da792dd-bucket/poseidon-circuits/mass_update_verifier.json \
    -O ./circuits/mass_update_verifier.json

wget \
    https://storageapi.fleek.co/10fd7cca-1427-4b72-9cd1-d81b5da792dd-bucket/poseidon-circuits/mass_update.zkey \
    -O ./circuits/mass_update.zkey