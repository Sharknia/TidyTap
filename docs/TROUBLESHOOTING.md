# Troubleshooting

[Back to README](../README.md)



- **Mouse or Finder feature does nothing:** Check Accessibility permission for TidyTap, return to its settings, and read the status at the bottom. Input Monitoring is not a separate requirement.
- **Scrolling feels wrong:** Disable overlapping settings in other mouse utilities. Try wheel reversal and wheel step size separately.
- **Caps Lock does not switch languages:** Check that your two input sources are configured in macOS and that another tool has not remapped Caps Lock. TidyTap does not manage your input-source list.
- **A feature stopped or a change failed:** Reopen TidyTap and check its status. The helper does not automatically restart after a failure. Do not delete the app while restoration is unresolved.

Still stuck? **[Open an issue](https://github.com/Sharknia/TidyTap/issues/new)** with your macOS and TidyTap versions, Mac/mouse model, enabled features, and the exact error or steps to reproduce. Please exclude private information from screenshots. You can also email [zel@kakao.com](mailto:zel@kakao.com).


## Check shutdown and restoration


1. Open TidyTap and turn off **all five input features**, including wheel step size, and **Start at login**.
2. Wait for the app to report that changes were applied. Check that Caps Lock and your input-source shortcut behave as they did before TidyTap. If an error appears, resolve it before deleting the app.
3. Open **Activity Monitor**, search for `TidyTapHelper`, and confirm it has exited. Then quit TidyTap with `⌘Q`.
4. To uninstall, move **TidyTap.app** from Applications to the Trash. To pause use, keep the app installed.

TidyTap restores the Caps Lock settings it backed up. It does not reset changes owned by other input utilities or include a dedicated uninstaller.


## Device compatibility



Testing used a MacBook Pro with Apple M3 Pro on macOS 26.5.2. TidyTap does not filter mice by brand. Compatibility depends on event reporting; these checks do not establish that every feature works on every device.

The 0.1.3 release notes record Finder move/copy checks in list, icon, column, and gallery views. Full integrated checks for wheel behavior, Caps Lock backup/restoration, permission changes, login/helper lifetime, and removal remain separate. See [development and validation notes](DEVELOPMENT.md) and [release notes](https://github.com/Sharknia/TidyTap/releases/tag/v0.1.3).

