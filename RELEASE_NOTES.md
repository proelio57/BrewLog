<!-- Notes for the next release, grouped by platform. scripts/release-notes.sh uses this file for the release
     whose commits change it; otherwise the notes come from the feat/fix/perf commit subjects. -->
iOS
• Pressure view: big colour-coded pressure number and pressure graph with a target band while a pressure sensor is connected (Settings: Automatic, Always, Off)
• Landscape full-screen chart with a button or by turning the phone (can be turned off in Settings)
• Bigger, coloured flow (g/s) readout
• Weight cleanup now runs on the shared Kotlin Multiplatform core

Android
• Add Dark Mode toggle in Settings (Appearance: System, Light, Dark)
• Fix capsule switch thumb width across Filter/Espresso and Journal toggles
• Fix Journal top header layout when no brews have been recorded yet
• Fix espresso machine chip wrap and eliminate empty space in machine settings
• Fix in-app APK installer closing unexpectedly after Google Play Protect scan
• Migrate core domain, brew analytics and Compose theme to Kotlin Multiplatform

Web
• No changes in this release
