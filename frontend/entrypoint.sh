#!/bin/sh
set -e

echo "📦 Syncing node_modules..."
npm install --prefer-offline --no-audit --no-fund

echo "🔥 Starting dev server..."
exec npm run dev -- --host 0.0.0.0
