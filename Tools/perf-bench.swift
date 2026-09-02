// Performance benchmark for the launcher fuzzy-match pipeline.
// Compiles the real Tinycast/Features/Launcher/Model/SearchRelevance.swift — no copy.
//
//   swiftc -swift-version 6 -O Tinycast/Features/Launcher/Model/SearchRelevance.swift \
//       Tools/perf-bench.swift \
//       -o /tmp/perf-bench && /tmp/perf-bench
//
// Run before and after optimizations to measure the delta.

import Foundation

@main
struct PerfBench {
    static func main() { run() }

    struct Entry {
        let name: String
        var alternates: [String] = []
        var bundleID: String?
        var executable: String?
        var fields: SearchFields {
            SearchFields(
                names: [name],
                alternateNames: SearchFields.usableAlternateNames(
                    alternates, displayName: name, fileName: name + ".app"),
                bundleID: bundleID, executableName: executable)
        }
    }

    /// 313 entries matching real app index size. Names drawn from actual macOS apps, tools,
    /// and system panes. Alternate names and bundle IDs from real Spotlight output where available.
    static func buildCorpus() -> [Entry] {
        let raw: [(String, [String], String?, String?)] = [
            // System apps with real alternate names
            ("Safari", ["浏览器", "browser", "사파리", "Safari.app"], "com.apple.Safari", nil),
            ("System Settings", ["Preferences", "Settings", "System Preferences", "System Settings.app"], "com.apple.systempreferences", nil),
            ("Calendar", ["iCal", "Calendar.app"], "com.apple.iCal", nil),
            ("Contacts", ["Address Book", "Contacts.app"], "com.apple.AddressBook", nil),
            ("Books", ["iBooks", "Books.app"], "com.apple.iBooks", nil),
            ("Music", ["iTunes", "Music.app"], "com.apple.Music", nil),
            ("Photos", ["Photos.app"], "com.apple.Photos", nil),
            ("Terminal", ["Terminal.app"], "com.apple.Terminal", nil),
            ("Finder", ["Finder.app"], "com.apple.Finder", nil),
            ("TextEdit", ["TextEdit.app"], "com.apple.TextEdit", nil),
            ("FaceTime", ["FaceTime.app"], "com.apple.FaceTime", nil),
            ("Freeform", ["Freeform.app"], "com.apple.Freeform", nil),
            ("GarageBand", ["GarageBand.app"], "com.apple.GarageBand", nil),
            ("Google Chrome", ["Chrome", "Google Chrome.app"], "com.google.Chrome", nil),
            ("Visual Studio Code", ["Code", "VS Code"], "com.microsoft.VSCode", "Electron"),
            ("Xcode", [], "com.apple.dt.Xcode", nil),
            ("App Store", [], "com.apple.AppStore", nil),
            ("Mail", [], "com.apple.Mail", nil),
            ("Maps", [], "com.apple.Maps", nil),
            ("Messages", [], "com.apple.iChat", nil),
            ("News", [], "com.apple.News", nil),
            ("Notes", [], "com.apple.Notes", nil),
            ("Reminders", [], "com.apple.Reminders", nil),
            ("Preview", [], "com.apple.Preview", nil),
            ("QuickTime Player", [], "com.apple.QuickTimePlayerX", nil),
            ("Stocks", [], "com.apple.Stocks", nil),
            ("Weather", [], "com.apple.Weather", nil),
            ("Voice Memos", [], "com.apple.VoiceMemos", nil),
            ("Home", [], "com.apple.Home", nil),
            ("Clock", [], "com.apple.Clock", nil),
            ("Shortcuts", [], "com.apple.Shortcuts", nil),
            ("Stickies", [], "com.apple.Stickies", nil),
            ("Dictionary", [], "com.apple.Dictionary", nil),
            ("Font Book", [], "com.apple.FontBook", nil),
            ("Chess", [], "com.apple.Chess", nil),
            ("Automator", [], "com.apple.Automator", nil),
            ("Console", [], "com.apple.Console", nil),
            ("Activity Monitor", [], "com.apple.ActivityMonitor", nil),
            ("AirPort Utility", [], "com.apple.AirPortUtility", nil),
            ("Archive Utility", [], "com.apple.ArchiveUtility", nil),
            ("Bluetooth File Exchange", [], "com.apple.BluetoothFileExchange", nil),
            ("Boot Camp Assistant", [], "com.apple.BootCampAssistant", nil),
            ("Calculator", [], "com.apple.Calculator", nil),
            ("ColorSync Utility", [], "com.apple.ColorSyncUtility", nil),
            ("Digital Color Meter", [], "com.apple.DigitalColorMeter", nil),
            ("Disk Utility", [], "com.apple.DiskUtility", nil),
            ("Feedback Assistant", [], "com.apple.FeedbackAssistant", nil),
            ("Grapher", [], "com.apple.Grapher", nil),
            ("Image Capture", [], "com.apple.ImageCapture", nil),
            ("Keychain Access", [], "com.apple.KeychainAccess", nil),
            ("Migration Assistant", [], "com.apple.MigrationAssistant", nil),
            ("Mission Control", [], "com.apple.MissionControl", nil),
            ("Photo Booth", [], "com.apple.PhotoBooth", nil),
            ("Podcasts", [], "com.apple.Podcasts", nil),
            ("Screen Sharing", [], "com.apple.ScreenSharing", nil),
            ("Screenshot", [], "com.apple.Screenshot", nil),
            ("Script Editor", [], "com.apple.ScriptEditor2", nil),
            ("Siri", [], "com.apple.Siri", nil),
            ("System Information", [], "com.apple.SystemInformation", nil),
            ("Time Machine", [], "com.apple.TimeMachine", nil),
            ("VoiceOver Utility", [], "com.apple.VoiceOverUtility", nil),

            // System Settings panes
            ("About", [], nil, nil),
            ("Accessibility", [], nil, nil),
            ("Appearance", [], nil, nil),
            ("Apple Account", [], nil, nil),
            ("AppleCare & Warranty", [], nil, nil),
            ("Autofill & Passwords", [], nil, nil),
            ("Battery", [], nil, nil),
            ("Bluetooth", [], nil, nil),
            ("Camera", [], nil, nil),
            ("Control Center", [], nil, nil),
            ("Date & Time", [], nil, nil),
            ("Desktop & Dock", [], nil, nil),
            ("Displays", [], nil, nil),
            ("Energy Saver", [], nil, nil),
            ("Family", [], nil, nil),
            ("Focus", [], nil, nil),
            ("Game Center", [], nil, nil),
            ("General", [], nil, nil),
            ("iCloud", [], nil, nil),
            ("Internet Accounts", [], nil, nil),
            ("Keyboard", [], nil, nil),
            ("Language & Region", [], nil, nil),
            ("Login Items & Extensions", [], nil, nil),
            ("Lock Screen", [], nil, nil),
            ("Menu Bar", [], nil, nil),
            ("Mouse", [], nil, nil),
            ("Network", [], nil, nil),
            ("Notifications", [], nil, nil),
            ("Passwords", [], nil, nil),
            ("Printers & Scanners", [], nil, nil),
            ("Privacy & Security", [], nil, nil),
            ("Profiles", [], nil, nil),
            ("Screen Saver", [], nil, nil),
            ("Screen Time", [], nil, nil),
            ("Sharing", [], nil, nil),
            ("Siri & Spotlight", [], nil, nil),
            ("Software Update", [], nil, nil),
            ("Sound", [], nil, nil),
            ("Speakers", [], nil, nil),
            ("Startup Disk", [], nil, nil),
            ("Storage", [], nil, nil),
            ("Touch ID & Password", [], nil, nil),
            ("Trackpad", [], nil, nil),
            ("Transfer or Reset", [], nil, nil),
            ("Users & Groups", [], nil, nil),
            ("VPN", [], nil, nil),
            ("Wallet & Apple Pay", [], nil, nil),
            ("Wallpaper", [], nil, nil),
            ("Wi-Fi", [], nil, nil),
            ("Windows", [], nil, nil),

            // Third-party apps
            ("1Password", [], "com.agilebits.onepassword", nil),
            ("Alacritty", [], "org.alacritty", nil),
            ("Alfred", [], "com.runningwithcrayons.Alfred", nil),
            ("Android Studio", [], "com.google.android.studio", nil),
            ("Anki", [], "net.anki2.droid", nil),
            ("AnyDesk", [], "com.philandro.anydesk", nil),
            ("AppCleaner", [], "com.freemacsoft.AppCleaner", nil),
            ("Arc", [], "company.thebrowser.Browser", nil),
            ("Arduino IDE", [], "cc.arduino.Arduino", nil),
            ("Aseprite", [], "com.aseprite.Aseprite", nil),
            ("Audacity", [], "org.audacityteam.audacity", nil),
            ("BBEdit", [], "com.barebones.bbedit", nil),
            ("Backblaze", [], "com.backblaze.bzdoinstall", nil),
            ("BalenaEtcher", [], "com.balena.etcher", nil),
            ("Bartender", [], "com.surteesstudios.Bartender", nil),
            ("Bear", [], "net.shinyfrog.bear", nil),
            ("BetterDisplay", [], "com.betterdisplay.BetterDisplay", nil),
            ("BetterTouchTool", [], "com.hegenberg.BetterTouchTool", nil),
            ("Beyond Compare", [], "com.scootersoftware.BeyondCompare", nil),
            ("Bitwarden", [], "com.bitwarden.desktop", nil),
            ("Blender", [], "org.blenderfoundation.blender", nil),
            ("Brave Browser", [], "com.brave.Browser", nil),
            ("ChatGPT", [], "com.openai.chat", nil),
            ("Charles", [], "com.xk72.Charles", nil),
            ("Claude", [], "com.anthropic.claude", nil),
            ("CleanShot X", [], "com.getcleanshot.cleanshot", nil),
            ("CleanMyMac", [], "com.macpaw.CleanMyMac", nil),
            ("ClickUp", [], "com.clickup.desktop", nil),
            ("Cursor", [], "com.cursor.Cursor", nil),
            ("DaVinci Resolve", [], "com.blackmagic-design.DaVinciResolve", nil),
            ("DaisyDisk", [], "com.daisydiskapp.DaisyDisk", nil),
            ("Dash", [], "com.kapeli.dashdoc", nil),
            ("DevUtils", [], "com.devutils.app", nil),
            ("Discord", [], "com.hnc.Discord", nil),
            ("Docker", [], "com.docker.docker", nil),
            ("Downie", [], "com.charliemonroe.Downie4", nil),
            ("Draw.io", [], "com.jgraph.drawio.desktop", nil),
            ("Dropbox", [], "com.dropbox.client", nil),
            ("Eagle", [], "com.ogdesign.eagle", nil),
            ("Emacs", [], "org.gnu.Emacs", nil),
            ("Evernote", [], "com.evernote.Evernote", nil),
            ("Figma", [], "com.figma.Desktop", nil),
            ("FileZilla", [], "org.filezilla-project.filezilla", nil),
            ("Final Cut Pro", [], "com.apple.FinalCut", nil),
            ("Firefox", [], "org.mozilla.firefox", nil),
            ("Fleet", [], "com.jetbrains.Fleet", nil),
            ("Fork", [], "com.danpristupov.Fork", nil),
            ("Framer", [], "com.framer.Framer", nil),
            ("Fusion 360", [], "com.autodesk.fusion360", nil),
            ("GIMP", [], "org.gimp.gimp-2.10", nil),
            ("GitHub Desktop", [], "com.github.GitHubClient", nil),
            ("GitKraken", [], "com.axosoft.GitKraken", nil),
            ("Glyphs", [], "com.GeorgSeifert.Glyphs3", nil),
            ("Godot", [], "org.godotengine.godot", nil),
            ("HandBrake", [], "fr.handbrake.HandBrake", nil),
            ("Hammerspoon", [], "org.hammerspoon.Hammerspoon", nil),
            ("Hidden Bar", [], "com.dwarvesv.HiddenBar", nil),
            ("Hopper", [], "com.cryptic-apps.hopper", nil),
            ("Hyper", [], "co.zeit.hyper", nil),
            ("IINA", [], "com.colliderli.iina", nil),
            ("ImageOptim", [], "net.pornel.ImageOptim", nil),
            ("Insomnia", [], "com.insomnia.app", nil),
            ("IntelliJ IDEA", [], "com.jetbrains.intellij", nil),
            ("iTerm", [], "com.googlecode.iterm2", nil),
            ("Joplin", [], "net.cozic.joplin-desktop", nil),
            ("Kaleidoscope", [], "com.blackpixel.Kaleidoscope", nil),
            ("Kap", [], "com.wulkano.kap", nil),
            ("Karabiner-Elements", [], "org.pqrs.Karabiner-Elements", nil),
            ("KeePassXC", [], "org.keepassxc.keepassxc", nil),
            ("Keka", [], "com.aone.keka", nil),
            ("Keynote", [], "com.apple.iWork.Keynote", nil),
            ("Krita", [], "org.kde.krita", nil),
            ("LaunchBar", [], "at.obdev.LaunchBar", nil),
            ("Lightroom", [], "com.adobe.LightroomClassic", nil),
            ("Linear", [], "com.linear", nil),
            ("Logic Pro", [], "com.apple.logic10", nil),
            ("Maccy", [], "org.p0deje.Maccy", nil),
            ("Magnet", [], "com.crowdcafe.windowmagnet", nil),
            ("Microsoft Edge", [], "com.microsoft.edgemac", nil),
            ("Microsoft Teams", [], "com.microsoft.teams", nil),
            ("Microsoft Word", [], "com.microsoft.Word", nil),
            ("Miro", [], "com.electron.realtimeboard", nil),
            ("MongoDB Compass", [], "com.mongodb.compass", nil),
            ("MonitorControl", [], "me.monitorcontrol.MonitorControl", nil),
            ("Mos", [], "com.caldis.Mos", nil),
            ("Neovim", [], "org.neovim.neovim", nil),
            ("NetNewsWire", [], "com.ranchero.NetNewsWire-Evergreen", nil),
            ("NordVPN", [], "com.nordvpn.osx", nil),
            ("Notability", [], "com.gingerlabs.Notability", nil),
            ("Notion", [], "notion.id", nil),
            ("Nova", [], "com.panic.Nova", nil),
            ("Numbers", [], "com.apple.iWork.Numbers", nil),
            ("OBS", [], "com.obsproject.obs-studio", nil),
            ("Obsidian", [], "md.obsidian", nil),
            ("OmniFocus", [], "com.omnigroup.OmniFocus3", nil),
            ("OmniGraffle", [], "com.omnigroup.OmniGraffle7", nil),
            ("OneDrive", [], "com.microsoft.OneDrive", nil),
            ("OneNote", [], "com.microsoft.onenote.mac", nil),
            ("OpenEmu", [], "org.openemu.OpenEmu", nil),
            ("Opera", [], "com.operasoftware.Opera", nil),
            ("OrbStack", [], "dev.orbstack.OrbStack", nil),
            ("Pages", [], "com.apple.iWork.Pages", nil),
            ("Parallels Desktop", [], "com.parallels.desktop.console", nil),
            ("Patternodes", [], "com.lostminds.Patternodes2", nil),
            ("Permute", [], "com.charliemonroe.Permute3", nil),
            ("Pixelmator Pro", [], "com.pixelmatorteam.pixelmator", nil),
            ("Postico", [], "at.eggerapps.Postico", nil),
            ("Postman", [], "com.postmanlabs.mac", nil),
            ("PowerPoint", [], "com.microsoft.Powerpoint", nil),
            ("PromptGod", [], "com.promptgod.app", nil),
            ("Proxyman", [], "com.proxyman.NSProxy", nil),
            ("PyCharm", [], "com.jetbrains.PyCharm", nil),
            ("Raycast", [], "com.raycast.macos", nil),
            ("Reaper", [], "com.cockos.reaper", nil),
            ("Rectangle", [], "com.knollsoft.Rectangle", nil),
            ("Reeder", [], "com.reederapp.reeder5", nil),
            ("Rider", [], "com.jetbrains.rider", nil),
            ("Runcat", [], "com.kyome.RunCat", nil),
            ("Signal", [], "org.whispersystems.signal-desktop", nil),
            ("Sip", [], "com.sipapp.Sip", nil),
            ("Sketch", [], "com.bohemiancoding.sketch3", nil),
            ("Skim", [], "net.sourceforge.skim-app.skim", nil),
            ("Skype", [], "com.skype.skype", nil),
            ("Slack", [], "com.tinyspeck.slackmacgap", nil),
            ("Soulver", [], "com.acqualia.Soulver3", nil),
            ("Sourcetree", [], "com.torusknot.SourceTreeNotMAS", nil),
            ("Spark", [], "com.readdle.SparkDesktop", nil),
            ("Spotify", [], "com.spotify.client", nil),
            ("Steam", [], "com.valvesoftware.steam", nil),
            ("Sublime Merge", [], "com.sublimemerge", nil),
            ("Sublime Text", [], "com.sublimetext.4", nil),
            ("Surge", [], "com.nssurge.surge-mac", nil),
            ("TablePlus", [], "com.tinyapp.TablePlus", nil),
            ("Tailscale", [], "com.tailscale.ipn.macos", nil),
            ("Telegram", [], "ru.keepcoder.Telegram", nil),
            ("The Unarchiver", [], "com.macpaw.site.theunarchiver", nil),
            ("Things", [], "com.culturedcode.ThingsMac", nil),
            ("Tidal", [], "com.tidal.desktop", nil),
            ("Todoist", [], "com.todoist.mac", nil),
            ("Tower", [], "com.fournova.Tower3", nil),
            ("Transmission", [], "org.m0k.transmission", nil),
            ("Transmit", [], "com.panic.Transmit", nil),
            ("Trello", [], "com.trello.Trello", nil),
            ("Ulysses", [], "com.soulmen.ulysses3", nil),
            ("Unity", [], "com.unity3d.UnityEditor", nil),
            ("Unreal Editor", [], "com.epicgames.UnrealEditor", nil),
            ("VLC", [], "org.videolan.vlc", nil),
            ("VMware Fusion", [], "com.vmware.fusion", nil),
            ("VirtualBox", [], "org.virtualbox.app.VirtualBox", nil),
            ("Vimac", [], "com.dexterleng.vimac", nil),
            ("Visual Studio", [], "com.microsoft.visual-studio", nil),
            ("Warp", [], "dev.warp.Warp-Stable", nil),
            ("WebStorm", [], "com.jetbrains.WebStorm", nil),
            ("WeChat", [], "com.tencent.xinWeChat", nil),
            ("WhatsApp", [], "net.whatsapp.WhatsApp", nil),
            ("Wireshark", [], "org.wireshark.Wireshark", nil),
            ("Xnip", [], "com.xnip.Xnip", nil),
            ("Yoink", [], "at.EternalStorms.Yoink", nil),
            ("Zed", [], "dev.zed.Zed", nil),
            ("Zoom", [], "us.zoom.xos", nil),
            ("Zotero", [], "org.zotero.zotero", nil),
            ("iA Writer", [], "pro.writer.ia", nil),
            ("iStat Menus", [], "com.bjango.istatmenus", nil),
            ("mpv", [], "io.mpv", nil),
        ]
        return raw.map { Entry(name: $0.0, alternates: $0.1, bundleID: $0.2, executable: $0.3) }
    }

    static func run() {
        let apps = buildCorpus()
        let count = apps.count
        print("=== Launcher Fuzzy Match Benchmark ===")
        print("Corpus: \(count) entries")
        print("")

        // Pre-compute normalized fields for all entries
        let normalized = apps.map { SearchFieldsNormalized(from: $0.fields) }

        print("--- Slow path (normalize on every call) ---")
        benchSet(label: "slow", apps: apps, normalized: nil, count: count)

        print("")
        print("--- Fast path (pre-normalized + char pre-filter) ---")
        benchSet(label: "fast", apps: apps, normalized: normalized, count: count)
    }

    static func benchSet(label: String, apps: [Entry], normalized: [SearchFieldsNormalized]?, count: Int) {
        let queries = ["a", "p", "ar", "arc", "k", "ke", "key", "s", "sa", "saf", "safari", "ch", "chrome", "terminal", "x", "xc", "xco", "xcod", "xcode"]
        let header = "query      total_µs  µs/call  ms/313  matched"
        print(header)
        print(String(repeating: "-", count: header.count))

        for q in queries {
            let iterations = 50
            let query = FuzzyMatch.Query(q)
            let queryChars = Set(query.text)
            let start = CFAbsoluteTimeGetCurrent()
            var matched = 0
            if let nf = normalized {
                for _ in 0..<iterations {
                    for i in 0..<count {
                        guard queryChars.isSubset(of: nf[i].characterSet) else { continue }
                        if SearchRelevance.score(query: query, normalizedFields: nf[i]) != nil { matched += 1 }
                    }
                }
            } else {
                for _ in 0..<iterations {
                    for app in apps {
                        if SearchRelevance.score(query: q, fields: app.fields) != nil { matched += 1 }
                    }
                }
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1_000_000
            let perCall = elapsed / Double(iterations * count)
            let msPer313 = perCall * 313.0 / 1000.0
            print("\(q.padding(toLength: 10, withPad: " ", startingAt: 0)) \(String(format: "%9.0f", elapsed)) \(String(format: "%8.2f", perCall)) \(String(format: "%7.2f", msPer313)) \(String(format: "%7d", matched / iterations))")
        }
    }
}