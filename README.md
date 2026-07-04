# Dankmail Unread — DMS plugin

Live unread-mail badge for the [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
bar, powered by [dankmail](https://github.com/arqueon/dankmail).

- **Live count, no polling**: subscribes to the dmail daemon's IPC
  socket and refreshes on its events (new mail, triage actions, snooze
  wakes).
- **Left click**: toggle the dankmail triage window (the daemon
  relaunches the UI if it was closed). If the daemon is down, the
  click starts the `dmail` systemd user service instead.
- **Right click**: sync now.
- **DND dot**: small indicator while dankmail's do-not-disturb is on.
- Settings: hide the pill at inbox zero, toggle the DND dot.

## Requires

[`dankmail`](https://github.com/arqueon/dankmail) (the `dmail` daemon)
installed and set up with at least one account.

## Install

Until it lands in the DMS plugin registry:

```sh
git clone https://github.com/arqueon/dms-dankmail \
  ~/.config/DankMaterialShell/plugins/dankmailUnread
```

Then enable **Dankmail Unread** in DMS Settings → Plugins and add the
widget to your bar layout.

## License

MIT.
