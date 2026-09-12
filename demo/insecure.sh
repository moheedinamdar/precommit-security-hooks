#!/usr/bin/env bash
# FIXTURE: deliberately bad shell script used by scripts/verify.sh to prove shellcheck fires.
# Expected findings: SC2086 (unquoted expansion), SC2115 (unsafe rm path), SC2164 (cd without ||).

TARGET_DIR=$1

cd $TARGET_DIR

rm -rf $TARGET_DIR/

for f in $(ls); do
  echo $f
done
