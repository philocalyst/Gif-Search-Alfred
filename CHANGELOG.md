# Changelog

All notable changes to this project will be documented in this file.  
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] – 2025-05-12

### Changed
- API key input is now optional by default (changed `required` from `true` to `false`)  
- Upscaled the workflow icon image for better resolution in README and UI  
- Download script now uses **CopyFile.app** to copy the downloaded GIF’s path to the clipboard  

### Removed
- Removed obsolete `category` metadata (`Internet`) from `info.plist`  
- Removed header icon image from the README  
- Dropped empty `variablesdontexport` array after refactoring validation logic  

## [1.0.0] – 2025-05-12

### Added
- Alfred workflow metadata: `icon.png`, `info.plist`, `prefs.plist`.  
- Swift-based search CLI (`search.swift`) with Tenor API integration, response decoding, caching via `CacheManager`, and Alfred-formatted JSON output.  
- GIF download helper script (`download.sh`) to fetch a GIF and copy its path to the clipboard.  
- Autocomplete script (`autocomplete.swift`) leveraging Tenor’s autocomplete endpoint, environment-driven configuration, result decoding, and caching hints.  
- Inline documentation and comments across all scripts for clarity and maintainability.

### Changed
- `download.sh` now uses `set -euo pipefail`, streamlined argument checks, temp-file creation, and clearer error messages.  
- Renamed `GIFSearchCLI` to `GIFSearch` in `search.swift` for a simpler entry point.  
- In `search.swift`, removed hardcoded API key; now forcibly unwraps `API_KEY` from the environment.  
- Updated Alfred workflow definitions in `info.plist`: switched to `.swift` script files, bumped action `type` codes, enabled `concurrently`, and adjusted script argument settings.

---

[Unreleased]: https://…/compare/v1.1.0…HEAD
[1.1.0]: https://…/compare/v1.0.0…v1.1.0  
[1.0.0]: https://github.com/your/repo/compare/...v1.0.0
