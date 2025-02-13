#!/usr/bin/env bash
# Fetch latest signers' keys. We do this in order to check if a key was revoked.
while read fingerprint _
do
  gpg --recv-keys ${fingerprint}
done < ./keys.txt
