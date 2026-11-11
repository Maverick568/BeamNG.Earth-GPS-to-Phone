BeamNG Earth Phone GPS add-on 1.1.0 (Android app 1.0.0, unchanged)

Independent companion for BeamNG.Earth 1.6.0-beta.
Place this ZIP in the BeamNG user folder's mods directory. Do not extract it.
No BeamNG.Earth files are replaced. No extra PC server is needed.

In GE Lua console:
extensions.beamngEarthPhoneGps.configure("PHONE_IPV4", "PAIRING_KEY", 47624, 20)
extensions.beamngEarthPhoneGps.status()
extensions.beamngEarthPhoneGps.stop()

Use BeamNG-Earth-GPS.apk on Android 8.0+. Select it as the mock location app.
Phone and PC must be on the same reachable LAN. Default: UDP 47624, up to 20 Hz.
Version 1.1 moves settings/socket initialization out of the render hook, gates state
lookups by cadence, and uses a fixed JSON formatter. status() reports meanMs/maxMs.
Only the ZIP needs updating. The wire format and Android app remain compatible.
Only the current player vehicle is sent. Speed is vehicle velocity magnitude in m/s.
Course is true direction of motion; heading is vehicle forward azimuth.
No valid fix during teleport placement or unsettled origin changes.
Settings persist in settings/beamngEarthPhoneGps.json inside the BeamNG user folder.
Stop the Android receiver to restore the phone's real location.

The Earth mod's existing _state() accessor is read only. Future Earth changes may
require updating this add-on. Android/mock/map-app compatibility requires a device test.
LAN packets contain the pairing key in plain text; use a trusted local network.
See the accompanying Polish INSTRUKCJA.md for setup and limitations.
