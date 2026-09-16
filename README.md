# TaskExplorer

See everything that's running on your Mac.

TaskExplorer shows every process, live, along with its code signing status, VirusTotal results, loaded dylibs, open files, and network connections. Version 3 is a ground-up rewrite built on Apple's Endpoint Security framework, with a built-in AI assistant.

<p align="center"><img src="https://objective-see.com/images/TE/te_main.png" width="800"></p>

**Documentation:** \
Full details and usage instructions can be found [here](https://objective-see.com/products/taskexplorer.html).

**To Support:** \
&#x2764;&nbsp; Love this product and want to support it? Please check out my [patreon page](https://www.patreon.com/objective_see).

<p align="center">
<a class="inlineLink" href="https://www.patreon.com/objective_see">
		<img src="https://objective-see.com/patreon/images/patreon.jpg" width="700" style="display:block; margin:auto;"/>
</a>
</p>

## Features

* **Live, via Endpoint Security:** a system extension monitors the system, so processes appear the moment they start, vanish when they exit, and their dylibs, files, and connections are refreshed as they change. No password prompt.
* **Code signing & VirusTotal:** spot unsigned or ad-hoc signed code, Apple vs. third-party binaries, and (with your own free VirusTotal API key) known malware, shown in red.
* **Built-in AI assistant:** ask "what's listening on the network?" or "which processes are ad-hoc signed?". It queries TaskExplorer's live data and can drive the UI. Runs on-device via Apple Intelligence, or with your own Claude or ChatGPT API key.
* **Search & filter:** text and `#keyword` filters (`#3rdparty`, `#adhoc`, `#flagged`, `#listening`, `#root`, …); add `#everything` to search dylibs, files, and connections too.
* **Shared cache dylibs:** dylibs that live in the dyld shared cache, per process or indexed for all.
* **Export:** save everything as JSON, from the app or the command line.

## Requirements

macOS 14 (Sonoma) or newer, Apple silicon or Intel. The on-device assistant needs macOS 26 with Apple Intelligence enabled; elsewhere it works with a Claude or ChatGPT key. [TaskExplorer 2.1.0](https://github.com/objective-see/TaskExplorer/releases/tag/v2.1.0) supports macOS 11–13.

## Command line

```
$ /Applications/TaskExplorer.app/Contents/MacOS/TaskExplorer -h

TASKEXPLORER USAGE:
 -h or -help  display this usage info
 -explore     enumerate all tasks and dylibs (JSON)
 -scan        list tasks and dylibs flagged by VirusTotal (JSON; requires an API key)

options:
 -pid [pid]   just the specified task
 -detailed    for each task, include its dylibs, files, & network connections
 -apple       include Apple (platform) tasks in '-explore' output (default: 3rd-party only)
 -key [key]   VirusTotal API key (default: the key saved via the app's Settings)
 -skipVT      don't query VirusTotal ('-explore' only)
 -pretty      pretty-print the JSON
```

The command line talks to the system extension, so run the app once first (to install and approve the extension). No root required.

## Building

Open `TaskExplorer.xcodeproj` in Xcode (26 or newer) and build the `TaskExplorer` scheme; the app embeds the `com.objective-see.taskexplorer.extension` system extension. The extension's Endpoint Security entitlement requires a provisioning profile, so building requires an Apple Developer account with that entitlement (or your own extension approved via `systemextensionsctl developer on`).

`release.sh` archives, signs, notarizes, and staples a release build (Developer ID; the extension is checked for a correct signature, entitlement, and profile, as macOS refuses to load one that isn't notarized).

## License

TaskExplorer is released under the [GPL v3](LICENSE).
