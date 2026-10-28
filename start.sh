#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP="$DIR/PlatoReader.app"

# Kill any existing instance first
pkill -f "PlatoReader.app/Contents/MacOS/PlatoReader" 2>/dev/null || true

echo "🏛️ Launching PlatoReader..."
open "$APP"
echo "✅ PlatoReader is now active in your menu bar (look for 🏛️ at the top right of your screen)!"
