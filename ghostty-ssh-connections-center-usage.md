# Ghostty SSH Connections Center Usage

## Open Connections

- Menu: `Ghostty -> Connections…`
- Command Palette: `Open: Connections`
- 已有 Ghostty 终端窗口时，`Connections` 会优先作为同一窗口内的原生 macOS tab 打开
- 如果当前没有可用 Ghostty 窗口，或当前窗口禁用了 tabs，则会退回为单独窗口

## Save an SSH connection

1. 打开 `Connections`
2. 点击 `New Connection`
3. 填写：
   - `Display Name`（可选）
   - `SSH Alias` 或 `Hostname`
   - `User`（可选）
   - `Port`（可选）
   - `Default Directory`（可选）
4. 选择认证方式：
   - `System SSH`
   - `Saved Password`
5. 如果是 `Saved Password`，输入密码并保存到 Keychain
6. 点击 `Save Connection`

## Manage saved hosts

- 左侧分组为：
  - `Favorites`
  - `Recent`
  - `Saved`
  - `Imported`
- 连接详情页支持：
  - `Connect`
  - `Edit`
  - `Delete`
  - `Duplicate`
  - `Favorite / Unfavorite`
- 双击侧边栏中的连接会直接发起连接

## Imported hosts

- `Reload SSH Config` 会重新读取 `~/.ssh/config`
- `Imported` 分组展示导入的 SSH host
- 编辑 imported host 只会生成本地 override，不会回写 `~/.ssh/config`
- `Reset Override` 会移除本地 override，恢复为导入值

## Open a new tab

- 点击 tab 栏 `+`，或按 `Cmd+N`，会打开 Ghostty 内置的 `New Tab` 选择器
- 选择器会展示：
  - `Local`
  - 可直接连接的 `Favorites`
  - 可直接连接的 `Recent`
  - 可直接连接的 `Saved`
  - 可直接连接的 `Imported`

### Search

- 搜索会匹配：
  - 连接名称
  - `SSH Alias`
  - `Hostname`
  - `User`
  - 副标题

### Shortcuts

- `↑ / ↓`：切换条目
- `Enter`：打开当前条目
- `Esc`：关闭选择器
- `Cmd+1 ... Cmd+9`：直接连接对应条目
- 当输入框聚焦时，裸数字继续输入搜索，不会触发连接

## Active remote sessions

- 右侧详情区会显示当前活动中的远程会话
- `Focus`：跳回对应 terminal tab/window
- `Reconnect`：按原连接配置再开一个新 tab/window

## Current limits

- 仍然使用系统 `ssh`
- 密码只保存在 macOS Keychain，不写入 JSON 配置
- 自动密码提交只处理常见 SSH 密码提示
- 当前仍不支持：
  - SFTP
  - 端口转发
  - Jump Host / Proxy UI
  - known-hosts 审批 UI
