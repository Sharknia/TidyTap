# TidyTap

Switch languages with Caps Lock, adjust your mouse wheel, use side buttons in Safari and Finder, and cut files with `⌘X`. TidyTap is a free, open-source Mac app. Turn on the features you want and leave the rest off.

**[Download for Mac](https://github.com/Sharknia/TidyTap/releases/latest)** · [한국어](README.ko.md)

Apple silicon · macOS 15.1+ · English & Korean · [MIT license](LICENSE)

<p align="center">
  <img src="docs/images/settings-ko.png" alt="TidyTap settings in Korean, with separate switches for Caps Lock, Finder cut and paste, scrolling, and side buttons" width="420">
</p>

<p align="center"><em>Shown in Korean. English is also available.</em></p>

## What can it do?

| Feature | How it works |
| --- | --- |
| Caps Lock language switch | Switch between two input sources, such as English and Korean, instead of enabling Caps Lock. |
| Reverse mouse scrolling | Reverse vertical mouse scrolling. Your trackpad stays the same. |
| Wheel scroll amount | Adjust ordinary single wheel steps to scroll 1 to 10 lines. |
| Side buttons | Go back and forward in Safari and Finder. |
| Finder cut & paste | Press `⌘X`, open the destination folder, then press `⌘V` to move files. `⌘C` still copies. |

> **Closing the window or quitting with `⌘Q` keeps enabled features running.** To stop them, turn off all features in the app. [How to stop or uninstall](#stopping-or-uninstalling)

## Install

1. Under **Assets**, download the `.dmg` file from the [latest release](https://github.com/Sharknia/TidyTap/releases/latest).
2. Open the DMG, drag TidyTap into Applications, then open it from there.
3. Turn on the features you want. If the app asks for permission, use its permission button to allow Accessibility access for TidyTap.

Enable "Start at login" to use your settings after signing in. There is no Intel Mac build. TidyTap targets macOS 15.1 or later; testing has been on macOS 26.5.2.

## A few things to know

- Side buttons work only in the Safari or Finder window you are using.
- Finder cut & paste does not work on the desktop, in other file managers, or through context-menu paste. If you cancel a move, press `⌘X` again.
- If you also use an app like Scroll Reverser, turn off overlapping features in one of the apps.
- If VIA or another tool already remaps Caps Lock, leave TidyTap's Caps Lock feature off.
- There is no menu-bar icon. Open TidyTap from Applications to change your settings.

## Questions

<details>
<summary>Why does it need Accessibility access? Does it collect my input?</summary>

macOS requires Accessibility access to handle scrolling, side buttons, and Finder shortcuts. Caps Lock switching alone needs no permission. You do not need to add TidyTap separately to Input Monitoring.

TidyTap does not record or transmit keystrokes or mouse activity. It processes input on your Mac and keeps settings and restoration backups there too. It has no analytics or automatic update checks.

You can change the permission in System Settings → Privacy & Security → Accessibility.

</details>

<details>
<summary>Can I use other mice? Will it affect my trackpad?</summary>

TidyTap leaves your trackpad's scroll direction alone. It does not restrict mice by brand, but behavior can vary with how a mouse reports input. Fast wheel scrolling may move farther than your chosen line count. Horizontal scrolling is unchanged.

Compatibility depends on how your mouse reports input. See [compatibility notes](docs/TROUBLESHOOTING.md#device-compatibility).

</details>

<details>
<summary>How do I update? Can I install with Homebrew?</summary>

There is no automatic updater or official Homebrew installation. Stop TidyTap using the steps below, download the latest DMG, and replace the app in Applications. Reopen it and turn on your preferred features.

</details>

## Stopping or uninstalling

1. Turn off all five input features and "Start at login".
2. Wait for the app to report that changes were applied. Check that Caps Lock and language switching work as they did before, then quit with `⌘Q`.
3. To uninstall, move TidyTap from Applications to the Trash.

**Deleting the app first will not automatically restore your settings.** If you see an error or features keep running, follow [the shutdown and restoration checks](docs/TROUBLESHOOTING.md#check-shutdown-and-restoration). There is no dedicated uninstaller.

## Need help?

Check the status message at the bottom of the app and its Accessibility permission first. If scrolling feels wrong, check whether another mouse app is adjusting it too.

If the [troubleshooting guide](docs/TROUBLESHOOTING.md) does not help, [report a bug](https://github.com/Sharknia/TidyTap/issues/new) with your macOS and app versions, mouse model, and steps to reproduce it. You can also email [zel@kakao.com](mailto:zel@kakao.com).

Build commands, tests, and implementation details are in [Development](docs/DEVELOPMENT.md).
