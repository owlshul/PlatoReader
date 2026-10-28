#!/bin/bash
echo "Stopping PlatoReader..."
pkill -f "PlatoReader" 2>/dev/null && echo "✅ PlatoReader stopped." || echo "PlatoReader was not running."
