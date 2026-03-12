# Ghostty + Shannon 一体化 AI 终端管理器开发计划

## Summary

将产品定义为一个**单一安装、单一入口**的 AI 终端运维系统：

- `Ghostty` 作为终端宿主、窗口/标签/分屏 UI、tab/session 生命周期管理者与终端运行时。
- `Shannon` 作为**内嵌本地主脑 runtime**，负责任务调度、主控对话、审批、事件流、策略和工作流编排。

实现策略默认不是把 `shan` 的 TUI/CLI 前端嵌进 Ghostty，而是复用 `shan` 已有的 Shannon runtime 基础设施：

- `agent loop`
- 本地 daemon HTTP/SSE 接口
- session persistence
- permissions / audit / skills / MCP / tools

Ghostty 继续掌握 tab/session/terminal-state 的真实状态与原生控制；Shannon 掌握 task/plan/policy/approval/memory 的真实状态。

V1 目标不是做成完整分布式运维平台，而是先交付一个**高性能、可托管、可接管、可管理本地与 SSH 终端 tab 的 AI 终端管理器**，并为后续多机编排与深度 agent 集成留接口。

默认产品定位：**控制台优先，但保留 Ghostty 作为高性能终端的轻快体验**。

默认远程接入：**纯 SSH**。

默认主控权限：**全自动托管**，但通过显式规则、审批和托管状态机约束风险。

## Implemented Status (2026-03-10)

当前仓库内已经落地的是 **macOS Phase 1 可测试版本**，重点是让你先验证 `tab/session` 连接、选择、读取、发送输入、发送命令、关闭和基础托管流程。

同时已补上 **扩展版 macOS UI 国际化**：

- 新增 `macos/Sources/Helpers/AppLocalization.swift`
- 当前覆盖范围：
  - `AI Terminal Manager`
  - 命令面板中的 `Open: AI Terminal Manager`
  - `About`
  - `Settings`
  - `Update` 弹窗、状态提示和 release notes 标签
  - `Clipboard` / `Configuration Errors` / `Quick Terminal` 告警
  - terminal overlays、错误页、只读态、Secure Input 提示
  - Surface / Split 无障碍标签与辅助文案
  - tab / terminal context menu 与部分系统确认弹窗
  - Shortcuts 权限确认弹窗
- 当前支持语言：
  - English
  - 简体中文
- 当前支持应用内语言切换：
  - `System`
  - `English`
  - `简体中文`
- 当前支持应用内重启入口：
  - `Settings` → `App Language` → `Restart Now`
- 当前实现方式：
  - 代码内本地化表
  - `macos/Sources/zh-Hans.lproj/Localizable.strings`
  - `App Intents / AppEnum / TypeDisplayRepresentation` 改为依赖原生 bundle 本地化资源
  - 优先读取应用内语言 override，再回退系统语言
  - 未命中的 key 回退到英文，再回退到 key 本身

已实现文件：

- `macos/Sources/Helpers/AppLocalization.swift`
- `macos/Sources/zh-Hans.lproj/Localizable.strings`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerModels.swift`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerView.swift`
- `macos/Sources/Features/AI Terminal Manager/AITerminalManagerController.swift`
- `macos/Sources/Features/AI Terminal Manager/ShannonSupervisor.swift`
- `macos/Sources/App/macOS/AppDelegate+AITerminalManager.swift`
- `macos/Sources/App/macOS/AppDelegate.swift`
- `macos/Sources/Features/Command Palette/TerminalCommandPalette.swift`
- `macos/Sources/Features/App Intents/`
- `macos/Sources/Ghostty/Ghostty.Input.swift`
- `macos/Tests/AITerminalManager/AITerminalManagerTests.swift`
- `macos/Tests/Localization/AppLocalizationTests.swift`

### 当前可测试能力

- `AI Terminal Manager / Command Palette / About / Settings` 支持中英双语界面
- `Update / Clipboard / Configuration Errors / Terminal overlays / context menus`
  支持中英双语界面
- `Settings` 支持应用内语言切换，不必跟随系统语言
- `Settings` 支持 `Restart Now` 让语言变更完整生效
- 从 AI Terminal Manager 页面打开：
  - `Local Shell`
  - 已保存的 `Workspace`
  - 已配置的 `SSH Host`
- 自动从 `~/.ssh/config` 导入 SSH host 候选
- 手动维护 host / workspace 配置并持久化到本地 JSON
- 已保存 SSH host 支持编辑与删除
- 导入自 `~/.ssh/config` 的 SSH host 支持编辑并保存为本地覆盖配置
- 枚举 Ghostty 当前打开的 terminal session
- 对 session 执行：
  - `Select`
  - `Focus`
  - `Read Visible Buffer`
  - `Read Screen Buffer`
  - `Send Command`
  - `Send Raw Input`
  - `Close Tab`
- 对 session 执行基础托管动作：
  - `Observe`
  - `Manage`
  - `Pause`
  - `Resume`
  - `Need Approval`
  - `Complete`
  - `Fail`

### 当前测试入口

- 菜单入口：`Ghostty` → `AI Terminal Manager…`
- 命令面板入口：`Open: AI Terminal Manager`
- 测试文件：`macos/Tests/AITerminalManager/AITerminalManagerTests.swift`
- 测试文件：`macos/Tests/Localization/AppLocalizationTests.swift`

### 构建目录约定

- 标准 macOS 构建输出目录：`macos/build`
- 不要在仓库根目录直接执行 `xcodebuild ... SYMROOT=macos/build`
- 若必须直接使用 `xcodebuild`，应先进入 `macos/` 目录，再使用 `SYMROOT=build`
- 推荐统一入口：`nu macos/build.nu`

### 已验证结果

- 已安装并验证本机构建链路：
  - `zig`
  - `nushell`
  - `swiftlint`
  - `Metal Toolchain`
- 已成功执行：
  - `zig build -Demit-macos-app=false`
  - `swiftlint lint 'macos/Sources/App/macOS/AppDelegate.swift' 'macos/Sources/Features/AI Terminal Manager/AITerminalManagerStore.swift' 'macos/Sources/Features/AI Terminal Manager/AITerminalManagerView.swift' 'macos/Tests/AITerminalManager/AITerminalManagerTests.swift'`
  - `nu macos/build.nu --scheme Ghostty --configuration Debug --action test`
  - 如需直跑：`cd macos && env -i HOME="$HOME" PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" xcodebuild -project Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT=build -skip-testing GhosttyUITests test`
- 当前这轮国际化改动已验证：
  - `swiftlint` 通过
  - `macos/build.nu --action test` 已完成构建与链接
  - 测试运行阶段在当前环境会卡在启动的 `Ghostty.app` 进程，需本机交互式收尾
  - `AppLocalizationTests` 已覆盖扩展后的原始文本映射与动态文案

### 新增实现状态（2026-03-12）

- `Ghostty` 现在默认把 `Shannon` 当作**内嵌本地主脑 runtime**：
  - 若未配置外部 `binaryPath`，会进入 embedded runtime 模式
  - 仍保留外部 bridge/runtime 作为兼容路径
- `AI Terminal Manager` 已新增 Shannon 运行时状态面板：
  - runtime endpoint
  - health
  - version
  - active agent
  - uptime
- `AI Terminal Manager` 已新增 Shannon 请求与审批 UI：
  - prompt 输入
  - 流式 response 区
  - 待审批动作卡片
  - 批准 / 拒绝入口
- 已落地 `Ghostty Native Bridge` 的第一批原生动作：
  - `create_local_tab`
  - `create_remote_tab`
  - `read_tab`
  - `close_tab`
  - 同时保留 `send_command` / `send_input` / `focus_session`
- 当前动作闭环已改为：
  - Shannon runtime 先规划动作
  - 需要提权的动作先进入 Ghostty 审批
  - Ghostty 原生执行动作
  - 执行结果再回传给 embedded Shannon runtime
- 当前 `create_*_tab` 动作已支持托管交接：
  - 新建 tab 后会把原 Shannon task binding 迁移到新 tab
  - 主控选中态会切到新 tab
  - 后续 Shannon 动作会继续以新 tab 为目标
- 当前 embedded Shannon runtime 已支持最小多步动作链：
  - `create_remote_tab -> send_command`
  - `create_remote_tab -> read_tab`
  - `send_command -> read_tab`
  - 多步链中的状态变更动作仍逐步走审批
- 当前已新增的新建 tab 入口：
  - `New Tab Picker`
  - 支持本地 shell、recent host、saved host、imported host
  - 与现有 SSH Connections 数据源复用
- 当前针对新增动作链已验证：
  - `swiftlint` 通过
  - `embeddedRuntimeRequestsReadTabWithoutApproval` 单测通过
  - `embeddedRuntimeRequestsApprovalBeforeRemoteTabCreation` 单测通过
  - `embeddedRuntimeChainsRemoteTabCreationIntoCommand` 单测通过
  - `embeddedRuntimeChainsCommandIntoReadWithoutExtraApproval` 单测通过
  - `shannonSessionHandoffMovesTaskBindingToNewTab` 单测通过
  - `AITerminalManagerTests` 全量已可通过 `xcodebuild` 稳定退出

### 当前限制

- Shannon 已不再只是 supervisor scaffold，但当前 embedded runtime 仍是**本地实现版 Shannon 主脑骨架**，还不是完整 production-grade Shannon workflow
- `Ghostty Native Bridge + Shannon Runtime` 的真实接线已经启动，但仍只覆盖第一批动作和单 tab 为主的执行链
- `shan` 仅作为参考实现，不再作为当前代码路径的必改依赖
- 远程 tab 当前通过 shell 启动后发送 `ssh ...` 初始输入完成，不是深度 SSH transport
- tab 输出读取目前以 Ghostty 已有文本缓存为主，尚未引入更细粒度事件流建模
- embedded Shannon runtime 当前是规则驱动的最小多步 planner，仍未达到完整 Shannon agent loop 深度
- 环境若缺少完整 macOS/Xcode 测试条件，则运行时验证需要你本机手动启动 app 检查

## Key Changes

### 1. 产品架构与进程模型

- 采用**单产品、分层实现**：
  - `Ghostty App`：终端 UI、tab/pane 生命周期、主控页、托管入口、终端读取器、动作执行者。
  - `Ghostty Native Bridge`：将 Ghostty 的 tab/session/host/runtime 事件映射到 Shannon 的 task/session/event 模型，并负责执行 Shannon 下发的动作。
  - `Embedded Shannon Runtime`：本地主脑服务进程，基于 `shan` 的 runtime 能力构建，随 Ghostty 启动并受其管理。
- 对用户保持**一体安装与一体启动**：
  - 启动 Ghostty 时自动确保 Shannon 本地服务可用。
  - 用户不需要单独安装或手动运行 Shannon。
- 进程隔离为默认实现：
  - Ghostty 崩溃不应带崩 Shannon。
  - Shannon 卡住不应阻塞终端渲染或输入。
- 本地通信默认使用**本机 loopback HTTP/WebSocket 或 Unix domain socket**，由桥接层统一封装，Ghostty UI 不直接散落调用 Shannon API。
- 第一阶段默认采用**混合内嵌模式**：
  - Ghostty 启动并管理独立本地 Shannon runtime 进程
  - 复用 `shan` 的 agent/daemon/session/tools 基础设施
  - 不把 `shan` 的 TUI/CLI 命令层直接嵌进 Ghostty

### 2. 终端资源模型

- 在 Ghostty 内新增一等资源模型：
  - `Host`：本地或远程机器。
  - `Workspace`：本地项目目录或远程目录模板。
  - `Terminal Session`：一个可交互 shell/SSH 终端实例。
  - `Managed Tab`：绑定到 Ghostty tab/pane 的终端实体，拥有可读、可控、可托管状态。
  - `Control Task`：由主控发起、绑定一个或多个 Managed Tab 的任务。
- 每个 tab/pane 必须拥有稳定 ID，并可映射到：
  - Host
  - Workspace
  - 当前工作目录
  - 连接方式（local/ssh）
  - 托管状态
  - 最近事件摘要
- Tab 与 Shannon 的映射规则：
  - 一个 tab/pane 可绑定 0 或 1 个活动控制任务。
  - 一个任务可管理 1 到多个 tab，但 V1 默认先优化单 tab 与少量多 tab 协作。
  - Ghostty 作为 tab 的事实来源；Shannon 作为任务与策略状态来源。

### 3. 新建 Tab 与远程接入

- 重构“新建 tab”入口，新增资源选择器：
  - `Local Shell`
  - `Local Project`
  - `Remote Host Default Directory`
  - `Remote Host Specific Directory`
- 新增主机配置模型：
  - 机器名称
  - SSH 地址/用户/端口
  - 默认目录
  - 可选目录模板列表
  - 认证方式引用（系统 SSH 配置/密钥别名）
- V1 默认**复用用户已有 SSH 配置**：
  - 优先读取 `~/.ssh/config`
  - Ghostty 内允许补充别名、默认目录和显示名
- 远程 tab 的行为要求：
  - 创建时可直接进入指定目录
  - UI 上明确显示本地/远程身份
  - 主控可区分远程 tab 与本地 tab
- 不在 V1 引入远端 agent 安装流程；后续版本再加入“SSH + 轻量代理”升级路径。

### 4. 主控页面（AI 管家页）

- 在 Ghostty 内新增独立主控页面，作为产品主中枢 UI：
  - 对话区
  - 当前任务区
  - tab/host 资源区
  - 托管队列区
  - 审批与异常区
- 主控页能力：
  - 读取当前已打开 tab 的状态与摘要
  - 创建任务并选择目标 tab/host/workspace
  - 让主控自动创建 tab 并启动 local/ssh 会话
  - 将某个手动 tab 加入托管队列
  - 对需要确认的动作显示审批卡片
  - 展示运行中、等待确认、已完成、失败的任务
- 主控页必须能表达“它在做什么”：
  - 当前分析的 tab
  - 当前计划的下一步动作
  - 最近写入的输入
  - 当前等待的人类决策

### 5. Tab 读取器与终端观察模型

- 为每个 managed tab 增加读取器，至少采集三类数据：
  - 可见屏幕内容快照
  - 滚动缓冲文本摘要
  - 输入/输出事件流元数据
- V1 读取目标以**文本与结构化终端状态**为主，不以 OCR 或截图理解为主。
- 读取器要支持：
  - 周期性快照
  - 关键事件驱动采样（提示符出现、命令完成、交互停滞、报错模式）
  - 主控按需拉取最新状态
- 读取结果需暴露给桥接层，转换为 Shannon 可消费的事件：
  - `tab.output.updated`
  - `tab.prompt.detected`
  - `tab.command.finished`
  - `tab.needs_attention`
  - `tab.idle`
- V1 不要求完整 ANSI 语义理解，但必须保证纯文本提取稳定，避免主控只看到残缺输出。

### 6. 托管 / 接管状态机

- 所有 tab 的控制状态统一定义为：
  - `manual`
  - `observed`
  - `managed_active`
  - `managed_waiting_approval`
  - `managed_paused`
  - `managed_completed`
  - `managed_failed`
- 托管规则：
  - 用户可手动将任意 tab 从 `manual` 切换为 `observed` 或 `managed_active`
  - 主控创建的 tab 默认进入 `managed_active`
  - 主控不得静默接管未授权 tab
- 接管规则：
  - 用户可对托管中的 tab 触发“人工接管”
  - 接管后主控停止发送输入，但继续观察，除非用户完全移除监控
- 托管中的关键动作必须有审批策略钩子：
  - 高风险命令
  - 提权
  - 删除/覆盖/远程写入
  - 外部发布动作
- V1 默认支持“配置规则范围内全自动”，但策略引擎必须能拦截高风险操作。

### 7. Shannon 中枢复用方式

- Shannon 在该产品中承担完整中枢职责：
  - 任务创建与编排
  - session 管理
  - SSE/WS 事件流
  - human approval
  - policy 执行
  - 历史与观测
- `shan` 项目提供可直接复用的 Shannon runtime 基础设施：
  - `agent loop`
  - streaming / tool-call / approval hook
  - 本地 daemon HTTP API
  - session persistence
  - agent config / memory / skills
  - permissions / audit
  - MCP / gateway integration
- 新增 Ghostty 专用桥接层，而非把 Ghostty 直接当成一个普通 Shannon client：
  - Ghostty tab/session/host 要映射为 Shannon 的 domain objects
  - 主控页的对话提交要带上目标 tab/workspace 选择
  - Shannon 输出的动作计划要转换成 Ghostty 可执行动作
- 复用边界必须明确：
  - 直接复用：`shan/internal/agent`、`shan/internal/daemon`、`shan/internal/session`、`shan/internal/permissions`、`shan/internal/audit`、与 Ghostty 无关的通用 tools
  - 仅作参考：`shan/internal/tools/ghostty*.go`、`shan ghostty workspace`、`shan` TUI / CLI 命令层
- 新增 Ghostty 专用工具/动作类型：
  - `create_local_tab`
  - `create_remote_tab`
  - `focus_tab`
  - `read_tab`
  - `write_tab_input`
  - `pause_task`
  - `request_user_approval`
  - `handoff_to_user`
  - `resume_managed_tab`
- 正式产品链路中，Shannon 不直接通过 AppleScript 或外部 UI automation 操作 Ghostty 内部 tab；正式控制路径统一走 `Ghostty Native Bridge`。
- 默认不修改 Shannon 的通用任务抽象语义，只新增 Ghostty adapter 和少量扩展字段。

### 8. 调度器与任务队列

- V1 调度器核心目标：**持续推进 tab 相关任务直到完成或等待人工**。
- 调度循环需要支持：
  - 从 Shannon runtime 的 agent loop 接收流式动作请求、审批请求和任务推进结果
  - 从 Ghostty 获取目标 tab 最新状态
  - 判断是否可继续执行
  - 写入终端输入或创建/聚焦 tab
  - 发现等待确认条件时挂起
  - 发现完成条件时进入验收
- Ghostty bridge 负责执行动作并把执行结果回灌给 Shannon runtime。
- 队列最小字段：
  - task id
  - target tab ids
  - owner session
  - current state
  - last observation
  - next action
  - approval status
- Ghostty 当前的 task queue/state UI 可以保留，但后续应切换为由 Shannon runtime 驱动的数据源，而不是本地假状态容器。
- V1 不追求复杂分布式公平调度；先实现**单用户桌面内的稳定托管队列**。

### 9. Shell / SSH 执行动作

- V1 主控最重要的接管对象是**通用 shell + SSH**，不是先围绕 Codex/Claude Code 做特化。
- 同时，Ghostty 内每一个 tab 都必须是 Shannon 可观测、可控制、可接管的一等对象；Shannon 不是偶尔帮忙开 tab 的工具，而是 Ghostty 的全局 AI 主控。
- 但设计上需兼容未来 AI TUI：
  - 允许定义“工具型终端 profile”
  - 为 Claude Code / Codex 预留 prompt-detection 与状态识别插件接口
- Shell/SSH 行为要求：
  - 主控可发送命令、确认输入、导航目录
  - 可检测典型 prompt 与命令完成
  - 对明显卡住、无输出、等待输入做状态标记
- `shan` 当前已有的 Ghostty 控制代码仅证明 Shannon 侧已有 Ghostty domain 经验，但正式产品实现必须切换到 Ghostty 原生控制链路。
- 不在 V1 承诺对所有 TUI 稳定自动操作；V1 只需保证 shell 与 SSH 会话可靠。

### 10. 配置、规则与权限

- 新增一组 Ghostty AI 配置：
  - Shannon 服务启用与连接方式
  - Shannon runtime binary path / local port or socket / endpoint / API key 引用方式 / config root
  - Host 列表与目录模板
  - 默认托管策略
  - 审批规则
  - 主控技能/知识源引用
- 用户可以配置主控权限范围，例如：
  - 允许创建 tab
  - 允许本地命令
  - 允许远程 ssh 命令
  - 高风险命令必须审批
- 默认规则：
  - 主控拥有广泛终端控制权
  - 但 destructive 与 privileged 动作默认需要审批
- 所有主控写入动作必须记录审计事件，至少包含：
  - 来源任务
  - 目标 tab
  - 输入内容摘要
  - 时间
  - 是否经审批

### 11. UI 与交互要求

- Tab 上要能直接看到：
  - 本地/远程标识
  - 当前托管状态
  - 当前任务摘要
- 右键或 tab 菜单新增：
  - 托管此 tab
  - 仅观察
  - 暂停托管
  - 人工接管
  - 在主控页打开关联任务
- 主控页要支持从任务跳转到对应 tab，也能从 tab 跳到对应任务。
- Ghostty 终端核心体验不能明显退化：
  - 未使用 AI/托管时，普通终端体验保持原样
  - 主控相关 UI 不应强占默认终端使用路径

## Public Interfaces / API Additions

- Ghostty 内部新增稳定 domain types：
  - `HostConfig`
  - `WorkspaceTemplate`
  - `ManagedTerminalSession`
  - `ManagedState`
  - `ControlTaskBinding`
- Ghostty 内部新增本地 bridge client 能力：
  - runtime 启动/停止/健康检查
  - task 提交与流式订阅
  - approval 提交
  - task 状态查询
- Ghostty ↔ Shannon 桥接接口新增动作/事件协议：
  - Shannon -> Ghostty：tab 创建、聚焦、读取、写入、暂停、恢复、关闭
  - Ghostty -> Shannon：tab 输出更新、等待输入、命令完成、异常、断开、approval.response
- Shannon 扩展字段：
  - task 与 session 可附带 `ghostty_tab_ids`
  - 可附带 `host_id`、`workspace_id`、`terminal_mode`
- UI 侧新增主控页入口、新建 tab 资源选择器、tab 托管菜单。

## Test Plan

- **资源创建**
  - 创建本地 shell tab
  - 创建本地项目目录 tab
  - 创建远程 host 默认目录 tab
  - 创建远程 host 指定目录 tab
- **桥接正确性**
  - tab 创建后稳定映射到 Shannon session/task
  - tab 关闭、断连、重连时状态正确更新
  - Ghostty 事件能稳定进入 Shannon 流
  - Ghostty 打开后可自动拉起 Shannon runtime，并在主控页显示健康状态
- **读取器**
  - 普通 shell 输出能被提取
  - 长输出与滚动缓冲可读
  - prompt、命令完成、等待输入可被识别
- **托管状态机**
  - manual → observed → managed_active 正常转换
  - 托管中人工接管可生效
  - 等待审批时禁止继续自动输入
  - 完成、失败、暂停状态都能回到 UI
- **审批与策略**
  - 高风险命令进入审批
  - 批准后继续执行
  - 拒绝后任务挂起并保留上下文
  - 用户在主控页批准/拒绝后，Shannon task 状态和 Ghostty 托管状态保持一致
- **远程会话**
  - SSH 成功建立并进入默认/指定目录
  - 远程断开后状态正确标记
  - 主控不会把远程断线误判为成功
- **性能与回归**
  - 用户可把任意现有 tab 纳入托管，并被正确映射到 Shannon task/session
  - Shannon 能基于 tab 当前缓冲区内容决定下一步动作
  - 某个 tab 被用户手动接管后，Shannon 停止写入但继续观察
  - 未托管 tab 的输入延迟和渲染性能无明显退化
  - 大量 tab 观察时 UI 不冻结
  - Shannon 服务异常时 Ghostty 仍能作为普通终端使用
  - 不启用 Shannon 时，Ghostty 普通终端行为无回归

## Delivery Plan

- **Phase 1 — 一体化底座**
  - 基于 `shan` runtime 的本地 Shannon 服务启动/健康检查
  - Ghostty-Shannon bridge 基础通信
  - Host/Workspace 配置模型
  - 新建 local/remote tab 入口
- **Phase 2 — 可观察终端**
  - Managed tab ID 与运行时模型
  - Tab 读取器
  - 事件映射与主控页基础列表
- **Phase 3 — 托管闭环**
  - 托管/接管状态机
  - 主控页对话绑定 tab
  - 任务队列与审批链路
- **Phase 4 — 稳定化与 UX**
  - tab/任务双向跳转
  - 审计与异常恢复
  - 性能优化与大规模 tab 观察稳定性
- **Phase 5 — AI TUI 适配准备**
  - Codex/Claude Code profile 接口
  - 特定 prompt / pause / handoff 识别扩展点

## Assumptions

- 产品作为**一个一体化 Ghostty 发行版**发布，而不是两个独立产品拼装。
- `shan` 作为 Shannon runtime 的代码基础被复用，但其 TUI/CLI 前端不进入 Ghostty 产品面。
- Shannon 以**本地内嵌服务**方式集成，默认由 Ghostty 自动管理生命周期。
- Ghostty 是 tab/session/terminal-state 的事实来源。
- Shannon 是 task/plan/policy/approval/memory 的事实来源。
- 正式产品链路不依赖 `shan` 当前基于 AppleScript 的 Ghostty 控制实现。
- V1 远程连接仅依赖 SSH，不要求在远端安装 agent。
- V1 优先支持**通用 shell/SSH 托管**；Claude Code / Codex 的深度 TUI 接管放在后续适配层。
- 主控默认拥有较高权限，但高风险动作必须通过策略/审批链路控制。
- 普通终端用户路径必须保持可用，AI 能力是增强层，不得破坏 Ghostty 作为终端的基础体验。
