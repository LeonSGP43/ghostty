# Ghostty SSH Connections Center V1 Spec

## Summary

- 目标：在 Ghostty 内提供一个独立的 `Connections` 页面，对齐 Termius 最核心的 SSH 连接体验：`保存连接 / 编辑 / 删除 / 搜索 / 最近连接 / 一键连接 / 已连接会话回到对应 tab`。
- 范围：本期只解决 `SSH 连接资料管理 + 快速连接成功`，不做文件传输、团队协作、端口转发、跳板可视化、云同步。
- 实现策略：继续复用系统 `ssh`，并把密码保存在 macOS Keychain；Ghostty 负责保存连接配置、启动连接、在检测到密码提示时自动注入已保存密码。
- 合并策略：优先只改 `macos/`，复用现有 AI Terminal Manager 的底层模型与会话读写能力，不碰 `src/` Zig 核心，降低未来与 Ghostty upstream 合并成本。

## Product Goal

用户应当可以在 Ghostty 里完成下面这条闭环：

1. 打开 `Connections` 页面。
2. 新建一个 SSH 连接，例如 `leon@192.168.3.38`。
3. 选择认证方式：
   - `System SSH`：完全交给系统 ssh/agent。
   - `Saved Password`：密码保存在 Keychain，下次一键连接。
4. 保存连接。
5. 在连接列表中一键连接，Ghostty 新开 tab 或窗口。
6. 如果该连接使用 `Saved Password`，Ghostty 在检测到 `password:` 提示时自动输入密码。
7. 连接建立后，`Connections` 页面能看到当前活动中的远程会话，并可以直接聚焦回对应 tab。
8. 最近连接列表保留最近状态，便于再次进入。

## Non-Goals

以下能力不进入 V1：

- SFTP
- 端口转发
- Jump Host / Proxy UI
- Known Hosts 审批 UI
- 云同步 / Vault
- 团队协作
- 密钥托管
- 自研 SSH transport / libssh
- 会话运行中的认证重试策略编排

## Architecture

### 1. Dedicated Connections Window

新增独立窗口：`Connections`。

页面信息架构：

- Toolbar
  - `New Connection`
  - `Reload SSH Config`
  - `Launch Target`（Tab / Window）
- Sidebar
  - Search
  - Recent
  - Saved
  - Imported
- Detail Pane
  - Connection details
  - Editor form
- Active Pane
  - Active Remote Sessions
  - Focus / Reconnect actions

AI Terminal Manager 保留为后续主控台，不再承担 SSH 连接中心主入口职责。

### 2. Connection Model

继续复用并扩展 `AITerminalHost`，新增 SSH 认证相关字段：

- `authMode`
  - `system`
  - `password`

V1 不在配置里保存明文密码。

密码存储规则：

- 配置文件只保存 `authMode`
- 密码本体保存在 macOS Keychain
- Keychain item key 使用稳定 `host.id`

### 3. Imported Host Override

从 `~/.ssh/config` 导入的 host 继续保持只读源配置。

如果用户在 `Connections` 页面为 imported host 设置：

- display name
- hostname
- user
- port
- default directory
- auth mode

则这些变更进入 `importedHostOverrides`，不会回写 `~/.ssh/config`。

### 4. Launch and Auto-Auth

连接发起流程：

1. 使用结构化 `AITerminalHost` 生成 `ssh` 启动命令。
2. 打开新 tab/window。
3. 注册该 surface 与 `host.id` 的绑定。
4. 如果 host 的 `authMode == .password`：
   - 从 Keychain 读取密码
   - 将该 session 标记为 `awaitingPasswordPrompt`
5. 轮询可见文本
6. 检测到 SSH 密码提示时，自动发送密码并回车

V1 只识别最常见提示：

- `password:`
- `user@host's password:`

自动注入约束：

- 仅对本应用刚刚通过 `Connections` 页面发起的 SSH 会话生效
- 每个连接会话默认只自动发送一次密码
- 未检测到密码提示时不盲发

### 5. Active Session Linkage

`Connections` 页面需要展示当前活动中的远程会话：

- Session title
- Connection name
- Host target
- Working directory
- Last observed auth state

用户可以：

- `Focus`：跳回对应 tab/window
- `Reconnect`：按原连接重新开一个新 tab/window

## UX Specification

### Sidebar Sections

#### Recent

- 最多展示最近 8 个连接
- 每项展示：名称、目标、最近状态、最近时间

#### Saved

- 展示用户手动保存的连接
- 支持 `Connect / Edit / Delete`

#### Imported

- 展示从 `~/.ssh/config` 导入的连接
- 支持 `Connect / Edit / Duplicate`
- 若已存在本地 override，显示 `Reset Override`

### Editor Form

字段：

- Display Name
- SSH Alias
- Hostname
- User
- Port
- Default Directory
- Authentication
  - System SSH
  - Saved Password
- Password
  - 仅在 `Saved Password` 模式下显示

校验规则：

- Display Name 必填
- SSH Alias / Hostname 至少一个必填
- Port 若填写必须为整数
- `Saved Password` 模式下密码允许留空，但保存时给出错误提示

### Active Sessions

只展示带有 `hostID` 且非本地 shell 的会话。

状态最小集：

- `connecting`
- `awaiting_password`
- `authenticating`
- `connected`
- `failed`

V1 这些状态主要用于 UI 展示，不做复杂状态机恢复。

## Persistence

配置文件继续使用当前 AI Terminal Manager 配置路径。

新增/扩展字段：

- `savedHosts[].authMode`
- `importedHostOverrides[].authMode`

Keychain：

- Service: `com.mitchellh.ghostty.ssh`
- Account: `host.id`

## Validation Rules

### Save Connection

- 名称不能为空
- alias 和 hostname 不能同时为空
- 端口必须为整数（若填写）
- `Saved Password` 模式需要非空密码

### Connect

- 若 `Saved Password` 模式但 Keychain 无密码，阻止连接并提示用户重新保存密码
- 若 SSH 目标无法生成，阻止连接并提示

## Test Plan

### Unit Tests

- 配置向后兼容时 `authMode` 默认为 `system`
- 保存 `Saved Password` 连接时会写入 Keychain 抽象层
- 切回 `System SSH` 时会删除已保存密码
- imported override 合并 `authMode`
- SSH 密码提示识别
- 自动注入状态在发送一次密码后不再重复发送

### Integration Tests

- `Connections` store 保存连接后，配置文件落盘正确
- active remote session 过滤结果正确

### Manual Verification

- 新建 `Saved Password` 连接后可一键连接成功
- 再次打开 `Connections` 页面仍能看到连接资料
- 点击活动会话的 `Focus` 可以回到对应 terminal tab/window
- imported host 可以设置本地密码并直接连接，不影响 `~/.ssh/config`

## Rollout Plan

### Phase 1

- 新增 spec
- 扩展 host model 与存储结构支持 `authMode`
- 加入 Keychain 凭据服务抽象

### Phase 2

- 新增独立 `Connections` 控制器与 SwiftUI 页面
- 将现有 SSH host 管理 UI 迁移为连接工作台布局

### Phase 3

- 加入 `Saved Password` 连接流程
- 增加活动远程会话列表与 `Focus / Reconnect`

### Phase 4

- 文档、测试、手工验证收尾
