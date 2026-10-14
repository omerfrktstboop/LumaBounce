# Implementation handoff

Updated: 2026-09-15. Active task: implement FEEDBACK_IMPLEMENTATION_PLAN.md.

## Authorization and constraints
- User authorized all plan steps, real AdMob IDs/live ads for release, demo ads
  for debug. No store listing work or publishing. No messages sent to others.
- Work in stages and update this file after each stage so another agent can
  continue. User may interrupt at their usage limit; no quota monitor available.
- Support email confirmed: ofsgamesofficial@gmail.com.
- Do not overwrite existing user changes: export_presets.cfg was already modified.
- No subagents authorized. No paid OpenRouter probes.

## Progress
- [x] 1: reviewed; 37 known failures remain, no level edits allowed
- [x] 2: reviewed live release ads; release/debug package split verified
- [x] 3: interactive first-shot tutorial and replay; desktop validation complete
- [x] 4: rating, feedback and native review integration; available device flows verified
- [x] 5: localization, UI QA, full checks and new Android builds

## Environment
- Godot console: sibling of repository, Godot_v4.7.2-stable_win64_console.exe.
- Python: C:/Users/Omerf/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe.
- JDK17: D:/DevTools/jdk17/jdk-17.0.20.1+1; SDK: D:/DevTools/android-sdk.
- Build: powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build_android.ps1.
- Signing stays outside repo, D:/LumaBounceSecrets/signing-current-user.clixml
  (Windows DPAPI). Never print credentials.
- Previous binaries are v8-godot472 AAB and debug-godot472 APK; do not deliver
  these as updated plan outputs. New versionCode required.

## Starting evidence
- Previous main suite: 1534 passed, 39 failed, log scratchpad/android-setup-blocks-check.log.
- docs/LEVEL_PHASES.md requires pulse lasers in 126-150, not moving bars/boosts.
- Current level_126 and enum/history are being examined before choosing a fix.
- Existing onboarding consists of text hints and animated mechanic intro cards.
- Existing AdMob config is forced to demo in both builds; real IDs are comments.

## Historical Stage 1 note from other work (not current working-tree state)
- Replaced legacy moving-bar content in the pulse-laser band with pulsing
  lasers, while retaining the prior mechanics as allowed combinations.
- Added the missing laser encounters and curated block gates; level 149 remains
  the designed multi-block gate, so the bounds expectation now names 149
  instead of the unsolvable final level 150.
- Adjusted the five panel endpoints that crossed the visual play-area bound.
  Level 150's target was moved out of the HUD/obstacle clearance area and now
  has 72 robust solver cells.
- Verified: boot check; `check_blocks_and_gate.gd` (all pass);
  `check_obstacles.gd` (107 pass); and every changed level with
  `verify_levels.gd`.

## Latest verification and user steering (supersedes Stage 1 completion above)
User says stages 1/2 were handled elsewhere and explicitly requires NO LEVEL
EDITS. Stage 1 completion above describes a different/intermediate working
state; current resources match git HEAD. Review found 1536 passed / 37 failed
in check_blocks_and_gate, including moving bars in the documented laser band.
Do not repair or restore level resources. Log: scratchpad/feedback-step1-check.log.

External live-ad changes reviewed: runtime production && !debug gating,
separate app/unit IDs and export plugin debug selection look correct.
check_monetization_phase2 PASS and check_release_readiness PASS.
Android artifact verification of those changes remains pending.

## Stage 3 implementation
- New FirstShotTutorial UI/scene with actual aim/power/release steps and skip.
- Gameplay forwards actual input and suppresses ads for the whole entry.
- ProgressStore tutorial version: fresh=0; existing readable save missing key=1.
- AppRoot persists completion and handles Settings replay in practice mode,
  with no wallet, analytics, ad service or bounce rewards.
- Settings has How to play; 8 UI localization rows added in all 6 languages.
- No level resources modified. Stage 4 is documented below.
- New tools/check_first_shot_tutorial.gd uses in-memory save spy; first run
  exposed Godot --script static autoload compilation ordering, not runtime
  game errors. Switched test game/AppRoot loads to dynamic runtime loads.

## Stage 3 completed checkpoint
- Focused test: 60 passed / 0 failed (check_first_shot_tutorial.gd).
- Tests cover migration, one-time save, skip, touch/drag/release, power change,
  early release/retry, multitouch, rotation, no replay progress/coin mutation,
  six-language card width and translated replay headers.
- check_hint_economy PASS (150 routes); monetization PASS; readiness PASS.
- Final boot PASS; final main suite 1536 passed / 37 failed, exactly the same
  known campaign failures as before stage 3. Log: scratchpad/tutorial-main-final.log.
- Startup branding suite has 3 pre-existing v1/v2 icon-path expectation failures
  (13 passed). No changes made to its expectations or user's icons.
- Main suite's new localization format-key issue was fixed and is now passing.
  This is not a clean campaign test baseline because of the 37 known failures.
- Final portrait and landscape screenshots rendered and inspected:
  to tmp/tutorial-touch-tr.png, tutorial-power-tr.png, tutorial-release-tr.png,
  tutorial-landscape-de.png and tutorial-settings-tr.png.
- Replay header now says How to play (not TEST); resize cancels stale aim;
  live locale changes refresh the replay header and tutorial card.
- No new APK/AAB yet; previous v8-godot472 artifacts do NOT contain tutorial.
- git diff --check PASS; git diff --name-only -- levels is empty.
- Added keys: HOW_TO_PLAY, FIRST_SHOT_SKIP, FIRST_SHOT_TOUCH, FIRST_SHOT_DRAG,
  FIRST_SHOT_POWER, FIRST_SHOT_RELEASE, FIRST_SHOT_FLIGHT and Turkish format
  key `İLK ATIŞ · %d/4`, translated into tr/en/es/pt_BR/de/fr.
- No physical Android device testing performed for stage 3.

## Stage 4 completed checkpoint
- Settings now exposes localized Rate game and Send feedback actions in a
  Support card. Store URL targets `com.ofsgames.lumabounce` over HTTPS.
- Feedback opens an editable `mailto:` draft to
  `ofsgamesofficial@gmail.com`; subject/body follow the active locale and only
  include game version plus optional level number. Nothing is sent
  automatically; no ad ID, purchase token or save file is attached.
- `LegalLinks` remains HTTPS-only. The allowlisted support `mailto:` builder is
  isolated in `scripts/engagement/engagement_links.gd`. Shell-open failures are
  shown inside Settings without interrupting navigation.
- `ReviewService` requires 5 distinct completed levels and 2 launches, stores
  only last-attempt time, and enforces a 90-day cooldown. It does not infer or
  store that a player rated the game.
- Automatic review is attempted only while leaving a successful result. It is
  suppressed for failure, tutorial/replay, purchase, consent and fullscreen-ad
  flows. A started review replaces the interstitial for that transition.
- Added Godot v2 Android plugin `LumaReviewPlugin`, built against Godot 4.7.2
  and official `com.google.android.play:review:2.0.2`. Source/build recipe lives
  under `tools/android_review_plugin`; packaged debug/release AARs live under
  `addons/LumaReviewPlugin/bin` and the editor export plugin is enabled.
- Save schema is now 3. Missing engagement keys migrate to zero, and campaign
  reset intentionally preserves review session/cooldown data.
- Focused regression: `check_review_and_feedback.gd` 66 passed / 0 failed.
  Tutorial 60 passed; monetization, billing and release-readiness checks pass;
  boot check passes. Settings screenshot inspected at
  `tmp/review-settings-tr.png`.
- Temporary final-code debug APK export succeeded and is v2-signed:
  `scratchpad/lumabounce-stage4-final-debug.apk`. Its manifest contains the review
  plugin v2 metadata, and its DEX contains both LumaReviewPlugin and the Google
  Play Review classes. This is verification only, not the final stage-5 APK.
- Main campaign suite remains 1536 passed / 37 failed, the unchanged known
  level baseline (`scratchpad/review-stage4-blocks-final2.log`).
  `git diff --name-only -- levels` remains empty.
- Real Play review UI cannot be proven by sideloading; validate from an eligible
  Play test track on a physical Android device in stage 5. Google may choose not
  to display the dialog, and its callback never reports whether a rating was
  submitted.

## Stage 5 completed checkpoint
- Expanded `check_review_and_feedback.gd` from 66 to 193 checks. All six
  locales pass at phone, tablet and landscape sizes. The suite checks visible
  translated text, overflow, 64 px touch targets, support rows, live language
  refresh, haptic/shake preference preservation, text plus shape cues and WCAG
  4.5:1 label contrast.
- Visually inspected Settings in all six languages at 360x640 and representative
  540x960, 900x1200 and 1280x720 layouts. Tutorial visuals were inspected in
  Turkish, French and German across phone/tablet/landscape. Captures are under
  `tmp/stage5-*.png`.
- Updated the startup icon regression to the intentional v2 icon assets. Startup
  now passes 16/16. Tutorial passes 60/60 and review/accessibility passes 193/193.
  Monetization, hint economy, billing, release readiness, analytics, cosmetics,
  retention and headless boot checks pass.
- The full campaign suite is now 1538 passed / 37 failed; two passing structural
  checks were added for touch scrolling and the 37 level-content failures are
  unchanged. Obstacle validation
  remains 104 passed / 3 failed. These are the same level-content baseline
  mismatches and were not hidden or changed. Logs:
  `scratchpad/plan5-check-blocks.log` and
  `scratchpad/plan5-check-obstacles.log`. No level resource changed.
- Android release `versionCode` is 9; display version remains 1.0.0. Export
  filters now also exclude the local `mcp_out.json` artifact discovered by the
  first package-content inspection.
- Final signed release artifact:
  `builds/lumabounce-release-v9-godot472-r3.aab` (34,415,422 bytes), SHA-256
  `F6F0F9D1E29A43A654FA9CE873C62971B9AAE65E527C2EB8678A5FEF0DF447C7`.
  Bundletool validation and JAR signature verification pass. Manifest is
  `com.ofsgames.lumabounce`, versionCode 9, minSdk 24, targetSdk 36 and contains
  the real AdMob app ID plus the v2 review plugin metadata. The signer matches
  the configured local upload keystore.
- Final debug artifact:
  `builds/lumabounce-debug-v9-godot472-r3.apk` (90,299,264 bytes), SHA-256
  `49C1E977B339B71238B512DD7E94BB3990DEE284F1533AA0729A7E47A44FAB2F`.
  It is APK Signature Scheme v2 signed, 16 KiB zip-aligned, keeps the production
  package name and contains Google's demo AdMob app ID. DEX inspection confirms
  both `LumaReviewPlugin` and Google Play Review classes.
- Bundletool also produced and inspected a universal APK from the AAB. It has
  versionCode 9, the real AdMob app ID, review classes and valid 16 KiB
  alignment. Bundletool's inspection APK uses its temporary debug signer; this
  does not modify or replace the signed AAB.
- Physical device: Samsung SM-A525F, Android 14/API 34, 1080x2400. A temporary
  side-by-side debug package initialized GodotGooglePlayBilling, AdmobPlugin and
  LumaReviewPlugin without fatal/script errors. Fresh first-run tutorial,
  real drag/release completion, tutorial persistence after relaunch, Settings,
  live Turkish-to-English switching and tutorial replay were exercised.
- The debug package selected Google's demo AdMob identity; consent returned
  `NOT_REQUIRED` and app-open auto-show remained disabled. A persisted
  interstitial candidate and natural completed-result transition were prepared,
  but USB/ADB disconnected before the final Next Level tap. On-screen demo
  interstitial display is therefore not claimed; policy/provider automated tests
  and package/runtime initialization are the available evidence.
- Feedback opened an editable Gmail draft addressed to
  `ofsgamesofficial@gmail.com` with version 1.0.0; it was inspected and discarded,
  never sent. Rate game routed to Play Store; that device was signed out, so the
  listing itself could not render. A sideload cannot prove Google's in-app review
  dialog; that final UI observation requires an eligible Play test-track install.
- The installed Play-distributed v8 app was left untouched. Its Google Play app
  signing certificate correctly differs from the local upload key. The temporary
  side-by-side package must be removed once the device reconnects if it was not
  already removed during this session.
- `git diff --check` passes and `git diff --name-only -- levels` is empty.

## Post-stage 5 touch-scroll fix
- Settings controls and level buttons now use `MOUSE_FILTER_PASS`, allowing a
  vertical touch drag that starts on their labels or button surfaces to reach
  the parent `ScrollContainer`.
- Both scroll areas use a 16 px touch deadzone. Existing level selection guard
  remains active; Settings now has the same 220 ms post-scroll guard for action,
  toggle and segmented buttons. Volume sliders retain direct horizontal input.
- Focused Settings/review regression passes 197/197; headless boot passes. The
  main suite is 1538/37 with only the same known level failures. No level resource
  changed.
- The r3 AAB/APK above supersede the earlier r2 files and contain this fix.
  Bundletool validation, release JAR signature, debug APK v2 signature and 16 KiB
  zip alignment pass. ADB was unavailable after the change, so this exact r3
  build still needs the final finger-drag check on a physical device.

## Next action
The code/build portion of the five-step plan is complete. The remaining external
observation is the native review dialog from an eligible Play test-track install;
store upload and listing work remain outside the authorized scope. Do not modify
level resources to clear the recorded 37/3 baseline failures.

## Version 10 release build
- On 2026-09-16 the Android Release preset was advanced to `versionCode=10`;
  display version remains 1.0.0 and the export path is now
  `builds/lumabounce-release-v10.aab`.
- Signed artifact: `builds/lumabounce-release-v10-godot472.aab`
  (34,415,439 bytes), SHA-256
  `4E76E9F158CE568D575AA356A13E000B30B84E9B6DAE956D8BE4DD4DE50BFA02`.
- Bundletool validation and JAR signature verification pass. Manifest package is
  `com.ofsgames.lumabounce`, versionCode 10, versionName 1.0.0, and it contains
  the real AdMob application ID plus LumaReviewPlugin metadata. Signer SHA-256
  remains `07:88:66:AD:6E:C0:1B:FA:D6:E2:7E:67:49:EF:1F:F8:6A:5E:F7:B7:8B:2A:A5:70:B0:1E:BE:1C:20:06:0C:C9`.
- Release content scan found no `mcp_out`, debug panel, level editor or MCP toolkit
  entries. No Play Store upload was performed.
