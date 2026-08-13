# UMP Privacy Options Extension

The bundled AdMob plugin is based on upstream `godot-sdk-integrations/godot-admob`
tag `v7.0` (`4b4ddceab0be81f0dcb12a6313038dba6cf9eacf`). Its Android bridge adds the two
UMP 3.2 APIs required by LumaBounce:

- `get_privacy_options_requirement_status()`
- `show_privacy_options_form()` and `privacy_options_form_dismissed`

The AARs were built against the Godot `4.7-stable` Android library with JDK 17.
They contain no app IDs, ad-unit IDs, keystores, or passwords.
The exact Java bridge delta is preserved in `patches/privacy_options.patch`.

Expected SHA-256 values:

- debug: `08A7889416D97FDE91B170BF22DD66B850419E9439B4C737D48C0A339F90FC69`
- release: `86BD590DBF3721B26DB51271C265581DD844E3E3ED784A93FD49C63E38191AE3`

When upgrading the upstream plugin, keep this contract or replace it with an
upstream release that exposes the same UMP privacy-options entry point. The
release-readiness test intentionally blocks exports when the contract is absent.
