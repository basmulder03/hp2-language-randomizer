# flag-icons (vendored subset)

Source: https://github.com/lipis/flag-icons
License: MIT (see `LICENSE` in this directory — Copyright (c) 2013
Panayiotis Lipiridis).

Only the 15 country SVGs this project's language pool actually needs
(`4x3/*.svg`) are vendored here, fetched from the `main` branch of the
upstream repo. Not the whole package, and not built as an npm
dependency — `tools/scripts/generate_flags.py` rasterizes these
directly to the 64x32 PNGs the mod imports.

To refresh (e.g. if upstream fixes/improves a flag): re-fetch the
specific file(s) from
`https://raw.githubusercontent.com/lipis/flag-icons/main/flags/4x3/<cc>.svg`
and re-run `generate_flags.py`. Country-code -> language-code mapping
lives in that script's `COUNTRY_FLAGS` dict.
