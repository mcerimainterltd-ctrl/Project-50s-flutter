#!/bin/bash
sed -i 's/^version: .*/version: 2.1.0+248/' pubspec.yaml
echo "✅ pubspec.yaml version bumped to 2.1.0+248"
grep "^version:" pubspec.yaml
