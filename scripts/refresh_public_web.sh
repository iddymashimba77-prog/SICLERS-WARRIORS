#!/usr/bin/env bash
# Rebuild the Flutter public web app and refresh the committed snapshot in
# public-web/ that the Render static site (sicklers-app) actually serves.
# Render static sites have no Flutter SDK, so Flutter source changes only reach
# production after this snapshot is rebuilt, committed and pushed.
set -o errexit

cd "$(dirname "$0")/.."

(cd apps/mobile && flutter build web --release --no-pub)
rsync -a --delete apps/mobile/build/web/ public-web/

echo "public-web/ refreshed. Commit and push the snapshot:"
echo "  git add public-web scripts/refresh_public_web.sh DEPLOYMENT.md"
echo "  git commit -m 'Refresh public web build'"
echo "  git push origin main"
