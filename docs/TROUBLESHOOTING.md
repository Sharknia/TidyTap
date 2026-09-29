# Troubleshooting

[Back to README](../README.md)



- **Mouse or Finder feature does nothing:** Check Accessibility permission for TidyTap, return to its settings, and read the status at the bottom. Input Monitoring is not a separate requirement.
- **Scrolling feels wrong:** Disable overlapping settings in other mouse utilities. Try wheel reversal and wheel step size separately.
- **Caps Lock does not switch languages:** Check that your two input sources are configured in macOS and that another tool has not remapped Caps Lock. TidyTap does not manage your input-source list.
- **A feature stopped or a change failed:** Reopen TidyTap and check its status. The helper does not automatically restart after a failure. Do not delete the app while restoration is unresolved.
- **Clipboard history does not open:** Confirm its switch is on and a shortcut is saved. Check TidyTap's Accessibility access, then try another shortcut if an existing app intercepts the current one. Settings suggests `⌥V` but does not register it automatically. Clipboard read access is checked separately when you enable the feature.
- **A history item does not paste:** Return to the original input field and try again. The app stops if that app or input focus changed; note the exact error text when reporting a repeat failure. The success response currently confirms that the paste key event was posted, not that the destination accepted the content.
- **Paste diagnostic log:** `~/Library/Logs/TidyTap/clipboard-paste.log` records the selected item's original position, activation state, Accessibility error codes, search term, and a short preview of selected text. Long text and queries include a prefix, full length, and SHA-256 hash; images include type, size, and hash only. The files are private to your user account, and the current and previous logs together use at most 256 KiB.
- **A second copy will not open or updates are unavailable:** Run the installed `/Applications/TidyTap.app`; a DMG or other copy is blocked. Quit an older running TidyTap before the first manual replacement. Version 0.1.4 and earlier cannot update themselves. In 0.2.0, opening Settings after the clipboard shortcut first launched the app may leave **Check for Updates** disabled; quit TidyTap and reopen it from Applications. Version 0.2.1 fixes this path.

Still stuck? **[Open an issue](https://github.com/Sharknia/TidyTap/issues/new)** with your macOS and TidyTap versions, Mac/mouse model, enabled features, and the exact error or steps to reproduce. Please exclude private information from screenshots. You can also email [zel@kakao.com](mailto:zel@kakao.com).


## Check shutdown and restoration


1. Open TidyTap and turn off **all five input features**, including wheel step size, **clipboard history**, and **Start at login**. If you want to erase saved history, use **Clear all history** before turning that feature off.
2. Wait for the app to report that changes were applied. Check that Caps Lock and your input-source shortcut behave as they did before TidyTap. If an error appears, resolve it before deleting the app.
3. Open **Activity Monitor**, search for `TidyTapHelper`, and confirm it has exited. Then quit TidyTap with `⌘Q`.
4. To uninstall, move **TidyTap.app** from Applications to the Trash. This does not erase `~/Library/Application Support/com.sharknia.TidyTap/clipboard-history`; remove that directory separately if you want to delete saved entries after uninstalling. To pause use, keep the app installed.

TidyTap restores the Caps Lock settings it backed up. It does not reset changes owned by other input utilities or include a dedicated uninstaller.


## Device compatibility



Testing used a MacBook Pro with Apple M3 Pro on macOS 26.5.2. TidyTap does not filter mice by brand. Compatibility depends on event reporting; these checks do not establish that every feature works on every device.

The 0.1.3 release notes record Finder move/copy checks in list, icon, column, and gallery views. Full integrated checks for wheel behavior, Caps Lock backup/restoration, permission changes, login/helper lifetime, and removal remain separate. See [development and validation notes](DEVELOPMENT.md) and [release notes](https://github.com/Sharknia/TidyTap/releases/tag/v0.1.3).

The [0.1.4 release notes](RELEASE_NOTES_0.1.4.md) record the earlier fresh-install toggle fix and VM checks. The clipboard and updater changes are in the [0.2.0 release notes](RELEASE_NOTES_0.2.0.md).
