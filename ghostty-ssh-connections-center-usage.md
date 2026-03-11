# Ghostty SSH Connections Center Usage

## Open the Connections page

- Menu: `Ghostty -> Connections…`
- Command Palette: `Open: Connections`
- 默认会作为当前 Ghostty 终端窗口中的一个原生 macOS tab 打开。
- 如果当前没有任何 Ghostty 终端窗口，则会退回为单独窗口。
- 如果当前终端窗口禁用了 tab，`Connections` 也会退回为单独窗口。

## Expected behavior

- 已经存在 Ghostty 终端窗口时，打开 `Connections` 后应直接在同一窗口的 tab 栏中出现 `Connections`。
- 不应因为 `Connections` 窗口此前尚未加入任何 tab group，而被误判为“已经和当前终端在同一个 tab group”。

## Save a new SSH connection

1. Open `Connections`.
2. Click `New Connection`.
3. Fill in:
   - optional `Display Name`
   - `SSH Alias` or `Hostname`
   - optional `User`
   - optional `Port`
   - optional `Default Directory`
4. Choose `Authentication`:
   - `System SSH`: use your system ssh / ssh-agent flow.
   - `Saved Password`: store the password in macOS Keychain and auto-fill it on the next connection.
5. Click `Save Connection`.

## Updated interaction model

- 左侧是更简化的连接侧边栏，只负责搜索、筛选和选择连接。
- 右侧只展示当前连接的详情、主操作和该连接对应的活动会话。
- `New Connection` / `Edit` / `Duplicate` 现在通过独立弹窗编辑，不再把大表单常驻在主界面里。
- 如果 `Display Name` 留空，Ghostty 会优先使用 `SSH Alias`，否则回退为 `user@hostname` 作为连接名。
- 在侧边栏中双击某个连接，会直接发起连接。

## Connect quickly

- Click `Connect` on any saved/imported/recent host.
- Ghostty opens a new tab or window depending on the `Launch` picker in the top-right corner.
- If the connection uses `Saved Password`, Ghostty waits for the SSH password prompt and sends the saved password once.

## Imported SSH config hosts

- `Reload SSH Config` reloads `~/.ssh/config`.
- Imported hosts are shown in the `Imported` section.
- Editing an imported host creates a local override only.
- `Reset Override` removes the local override and returns the host to the imported values.

## Active remote sessions

- The right-side panel shows current active remote sessions opened through Ghostty.
- `Focus` jumps back to the corresponding terminal tab/window.
- `Reconnect` opens another session using the same saved host profile.

## Current V1 limits

- Uses system `ssh`.
- Passwords are stored in macOS Keychain only, never in the JSON config.
- Auto password submission only handles common SSH password prompts.
- No SFTP, port forwarding, jump host UI, or known-host approval UI yet.
