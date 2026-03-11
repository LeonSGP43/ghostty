# Ghostty SSH Connections Center Usage

## Open the Connections window

- Menu: `Ghostty -> Connections…`
- Command Palette: `Open: Connections`

## Save a new SSH connection

1. Open `Connections`.
2. Click `New Connection`.
3. Fill in:
   - `Display Name`
   - `SSH Alias` or `Hostname`
   - optional `User`
   - optional `Port`
   - optional `Default Directory`
4. Choose `Authentication`:
   - `System SSH`: use your system ssh / ssh-agent flow.
   - `Saved Password`: store the password in macOS Keychain and auto-fill it on the next connection.
5. Click `Save Connection`.

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
