#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../app"
swift build -c release --product Rufus
cp "$(swift build -c release --show-bin-path)/Rufus" ../build/linux/rufuswift
echo "Built Linux binary: ../build/linux/rufuswift"
