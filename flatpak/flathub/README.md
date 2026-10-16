# Flathub build inputs

This template generates an offline source-build manifest for `app.tsumiru.Tsumiru`.
`foreign.json` overrides the tool's SQLite binaries/patch; SQLite builds from the pinned amalgamation instead.
Keep these inputs upstream; generated manifests and `generated/` belong in the separate Flathub submission repo (as in [wger](https://github.com/flathub/de.wger.flutter)).

From the repository root, bump the source commit/tag to each release tag and regenerate (requires Python, Git, patch and Flutter's host build prerequisites):
```sh
RELEASE_REF=vX.Y.Z
RELEASE_COMMIT=$(git rev-parse "$RELEASE_REF^{commit}")
git clone --branch 0.15.0 --depth 1 https://github.com/TheAppgineer/flatpak-flutter.git flatpak/flathub/.flatpak-flutter
python3 -m venv flatpak/flathub/.venv
flatpak/flathub/.venv/bin/pip install -r flatpak/flathub/.flatpak-flutter/requirements.txt
mkdir -p flatpak/flathub/work
cp -R flatpak/flathub/patches flatpak/flathub/foreign.json flatpak/flathub/flatpak-flutter.yml flatpak/flathub/work/
sed -i "s/^        commit: .*/        commit: $RELEASE_COMMIT/" flatpak/flathub/work/flatpak-flutter.yml
cd flatpak/flathub/work
../.venv/bin/python ../.flatpak-flutter/flatpak-flutter.py flatpak-flutter.yml
flatpak run org.flatpak.Builder --user --install-deps-from=flathub --force-clean --sandbox build app.tsumiru.Tsumiru.yml
```

The public MyAnimeList client ID is a build input in the template, passed through `--dart-define=MAL_CLIENT_ID`.
The selected release commit must include the new-ID assets and current release metadata in `flatpak/app.tsumiru.Tsumiru.metainfo.xml`.
