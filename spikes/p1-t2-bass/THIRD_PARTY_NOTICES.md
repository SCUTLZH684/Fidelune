# Third-Party Notices

## 1. Un4seen BASS Audio Library & Official Add-ons (Proprietary)
- **Components**:
  - `bass.xcframework` (BASS 2.4.18.3)
  - `bassmix.xcframework` (BASSmix 2.4.13.1)
  - `bassdsd.xcframework` (BASSDSD 2.4.2)
  - `bassflac.xcframework` (BASSFLAC 2.4.6.1)
  - `basswv.xcframework` (BASSWV 2.4.7.4)
  - `bassape.xcframework` (BASSAPE 2.4.1)
  - `bassopus.xcframework` (BASSOPUS 2.4.3.3)
- **Author**: Ian Luck / Un4seen Developments Ltd (`https://www.un4seen.com`)
- **Licensing Summary**:
  - Free for non-commercial use (no in-app donations/monetization).
  - Commercial / Shareware iOS licensing requires a paid license from Un4seen Developments prior to commercial distribution (e.g., Shareware EUR 125 / iOS Single Commercial EUR 475 as published on `un4seen.com/bass.html`).
  - Incompatible with pure GPLv2/v3 binaries unless explicitly exempted; Fidelune keeps BASS binaries out of version control and fetches pinned archives via `tools/fetch_bass.py` at build time, while insulating BASS behind `AudioPlaybackBackend` Swift protocols.
  - Public CI build artifacts containing BASS binaries are encrypted for owner hardware QA only.

## 2. LyrPlay Architectural Reference (`mtxmiller/LyrPlay`, MIT License)
- Certain iOS `AVAudioSession` lifecycle conventions (leaving `BASS_CONFIG_IOS_SESSION` default, one-time initial session activation for `MPRemoteCommandCenter`, `mediaServicesWereReset` retry on `BASS_ERROR_BUSY`, `BASS_Start()` prior to resume, avoiding `BASS_Free` inside route-change callbacks) were informed by and adapted in line with `mtxmiller/LyrPlay` (MIT License).
