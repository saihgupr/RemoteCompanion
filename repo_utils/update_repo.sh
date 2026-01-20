#!/bin/bash
set -e

# Change to repo root
cd "$(dirname "$0")/.."

echo "📦 Generating Repository Metadata..."

# 1. Generate Packages
./repo_utils/scan_packages.py > ./docs/Packages
bzip2 -fk ./docs/Packages

# 2. Generate Release
# Copy template
cp repo_utils/Release docs/Release

# Append hashes to Release (crucial for Sileo)
echo "MD5Sum:" >> docs/Release
printf " $(md5 -q docs/Packages) $(stat -f%z docs/Packages) Packages\n" >> docs/Release
printf " $(md5 -q docs/Packages.bz2) $(stat -f%z docs/Packages.bz2) Packages.bz2\n" >> docs/Release

echo "✅ Repo updated!"
echo "👉 Enable GitHub Pages for your 'main' branch, pointing to '/' (root) to serve."
