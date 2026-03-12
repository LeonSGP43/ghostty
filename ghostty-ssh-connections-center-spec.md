# Ghostty SSH Connections Center Spec

## Summary

- 目标：在 Ghostty 内提供一个原生风格的 SSH 连接工作台，对齐高频使用场景：`保存连接 / 编辑 / 删除 / 最近连接 / 收藏连接 / 搜索 / 一键连接 / 回到活动远程 tab`。
- 配套新增 `New Tab` 选择器：统一接管 tab 栏 `+` 与 `Cmd+N`，让用户在创建新 tab 时直接选择 `local` 或可直接连接的 SSH。
- 当前策略：继续复用系统 `ssh` 与 macOS Keychain，只在 `macos/` 内扩展，降低未来与 Ghostty upstream 合并冲突。

## Scope

### In Scope

- `Connections` 连接中心
- 本地保存 SSH 连接信息
- 从 `~/.ssh/config` 导入连接
- imported host 的本地 override
- `Saved Password` 认证模式
- 活动远程会话的回跳与重连
- `New Tab` picker 的搜索、收藏、分组去重与快捷连接

### Out of Scope

- SFTP
- 端口转发
- Jump Host / Proxy UI
- Known Hosts 审批 UI
- 云同步 / Vault / 团队协作
- 密钥托管
- 自研 SSH transport / libssh
- 会话中复杂认证恢复与自动重试

## Current Product Flow

用户现在应当可以在 Ghostty 内完成以下闭环：

1. 打开 `Connections`
2. 新建或编辑一个 SSH 连接
3. 选择 `System SSH` 或 `Saved Password`
4. 保存连接资料
5. 在 `Connections` 中点击连接，或在 `New Tab` picker 中直接选择连接
6. Ghostty 新开 tab 或 window 并发起 SSH
7. 如果为 `Saved Password`，Ghostty 在检测到密码提示后自动发送一次密码
8. 回到 `Connections` 时可以看到最近连接、收藏连接与活动远程会话

## Information Architecture

### Connections

- Toolbar
  - `New Connection`
  - `Reload SSH Config`
  - `Launch Target` (`Tab / Window`)
- Sidebar
  - `Favorites`
  - `Recent`
  - `Saved`
  - `Imported`
- Detail Pane
  - 连接详情
  - 主操作区
  - 活动会话区

### New Tab Picker

- 数据源
  - `Local`
  - `Favorites`
  - `Recent`
  - `Saved`
  - `Imported`
- 行为
  - 搜索过滤
  - 方向键移动
  - `Enter` 打开
  - `Cmd+1...Cmd+9` 快速连接

## Data Model

### Host

继续复用 `AITerminalHost`，当前 SSH 相关核心字段包括：

- `sshAlias`
- `hostname`
- `user`
- `port`
- `defaultDirectory`
- `authMode`

### Configuration

继续复用 `AITerminalManagerConfiguration`，当前与 SSH 工作台相关的持久化字段包括：

- `savedHosts`
- `importedHostOverrides`
- `recentHosts`
- `favoriteHostIDs`

### Password Storage

- 配置文件中只保存 `authMode`
- 密码本体保存在 macOS Keychain
- Keychain item:
  - Service: `com.mitchellh.ghostty.ssh`
  - Account: `host.id`

## Current UX Rules

### Sidebar Grouping

- `Favorites` 优先展示用户收藏的 SSH host
- `Recent` 不重复显示已收藏 host
- `Saved` 不重复显示已收藏或最近连接中的 host
- `Imported` 不重复显示已在其他分组出现的 host

### Host Editing

字段：

- `Display Name`
- `SSH Alias`
- `Hostname`
- `User`
- `Port`
- `Default Directory`
- `Authentication`
  - `System SSH`
  - `Saved Password`
- `Password`

规则：

- `SSH Alias / Hostname` 至少一个必填
- `Port` 若填写必须为整数
- `Saved Password` 模式需要可保存到 Keychain 的密码
- imported host 的修改只写入本地 override，不回写 `~/.ssh/config`

### New Tab Picker

- 搜索匹配以下字段：
  - 连接名称
  - subtitle
  - `sshAlias`
  - `hostname`
  - `user`
- 只展示“可直接连接”的 SSH：
  - 目标信息完整
  - 若是 `Saved Password`，必须已有 Keychain 密码
- 当输入框聚焦时：
  - 裸数字继续输入搜索
  - `Cmd+1...Cmd+9` 仍然直接连接对应项

## Connection Launch

连接发起流程：

1. 由结构化 `AITerminalHost` 生成 `ssh` 启动命令
2. 打开新 tab 或 window
3. 注册 session 与 `host.id`
4. 若 `authMode == .password`：
   - 从 Keychain 取密码
   - 标记为等待密码提示
5. 轮询可见文本
6. 命中 SSH 密码提示后自动发送一次密码

当前只识别最常见密码提示：

- `password:`
- `user@host's password:`

## Activity Linkage

`Connections` 页面需要展示当前活动中的远程会话：

- Session title
- Connection name
- Host target
- Working directory
- Last observed auth state

用户可以：

- `Focus`：跳回对应 tab/window
- `Reconnect`：按原连接重新开一个新 tab/window

## Validation

### Save Connection

- `SSH Alias` 和 `Hostname` 不能同时为空
- `Port` 必须为整数（若填写）
- `Saved Password` 模式必须提供可保存密码

### Connect

- 若 `Saved Password` 模式但 Keychain 无密码，则阻止连接
- 若 SSH 目标无法生成，则阻止连接
- 本地 shell 不能加入收藏

## Current Test Coverage

### Unit Tests

- 旧配置解码兼容
- `authMode` 默认值兼容
- `Saved Password` 写入 / 删除 Keychain 抽象层
- imported override 合并
- SSH 密码提示识别
- `favoriteHostIDs` 清理与去重
- `New Tab` picker 顺序、过滤与分组去重

### Manual Verification

- 新建 `Saved Password` 连接后可一键连接
- `Connections` 可展示最近连接、收藏连接与活动远程会话
- `Cmd+N` / `+` 能打开内置 `New Tab` picker
- `Cmd+1...Cmd+9` 能在 picker 中直接连接

## Next Phase

下一阶段优先做：

1. 连接中心更接近 Termius 的信息架构与视觉质感
2. 更简单的连接编辑与保存体验
3. 更丰富的 SSH 状态反馈与错误诊断
4. 后续再评估端口转发、跳板、known-hosts 等能力
