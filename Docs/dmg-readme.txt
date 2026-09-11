LingoFloat — first-launch guide
====================================

LingoFloat is ad-hoc signed for integrity but is not Apple-notarized.
macOS Gatekeeper blocks it on first launch and shows the dialog:

   "Apple could not verify "LingoFloat.app" is free of malware..."

Click Done. Then follow these steps once:

   1. Drag LingoFloat to Applications (use the arrow in this window).
   2. Open  System Settings → Privacy & Security.
   3. Scroll all the way to the bottom. You will see a line:
          "LingoFloat.app was blocked to protect your Mac."
   4. Click  Open Anyway.
   5. Confirm with Touch ID, Apple Watch, or your password.
   6. macOS remembers this choice forever. Future launches work normally
      with a double-click like any other app.


Prefer no Gatekeeper friction at all?
======================================

Build from source instead. Xcode can sign the local build under your own
Apple ID, so macOS can treat it as a locally built application:

   cd /path/to/your/LingoFloat/source-checkout
   open LingoFloat/LingoFloat.xcodeproj
   # in Xcode: hit Cmd+R

This is the recommended path if you want zero trust in someone else's
build. Source code is public; every commit goes through CI.


Verify this binary before granting Microphone / Screen Recording
=================================================================

   codesign --verify --deep --strict --verbose=2 /Applications/LingoFloat.app
   codesign -dvv /Applications/LingoFloat.app 2>&1 | grep -E '^(Identifier|Signature)'

Expected identity fields:

   Identifier=com.whaledolphin.lingofloat
   Signature=adhoc

Also compare the downloaded DMG against the accompanying `.dmg.sha256`
file on the GitHub Release page before opening it.


Source code and docs are included in the LingoFloat project checkout.
