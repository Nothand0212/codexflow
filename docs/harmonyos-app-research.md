# CodexFlow HarmonyOS App 方案研究

更新时间：2026-05-02  
范围：只评估 CodexFlow 后续构建 HarmonyOS / OpenHarmony App 的技术路线，不实现代码。

## 1. 结论摘要

推荐路线：先做 **原生 HarmonyOS ArkTS/ArkUI PoC**，同时保留 **Flutter Web + Tailscale/浏览器** 作为近期可用兜底；不建议马上把现有 Flutter App 全量鸿蒙化作为主路线。

原因：

- CodexFlow 的核心客户端能力主要是 HTTP JSON、SSE、multipart 图片上传、通知、后台轮询、Deep Link、本地缓存和 Markdown/代码渲染。除 Markdown/代码渲染生态外，ArkTS/ArkUI 与 HarmonyOS 系统能力基本可覆盖。
- CodexFlow 当前 Android 侧最有价值的差异能力是 `Mobile Background Monitoring`：通过 Android foreground service + persistent status notification 持续轮询 `/api/v1/dashboard`。HarmonyOS Stage 模型明确强调后台行为受系统管控，长时任务需要匹配系统认可的场景。CodexFlow 这种“用户配置 LAN/Tailscale 地址后持续监控 Agent”的后台常驻能力，是 PoC 必须优先验证的最大不确定项。
- Flutter 官方支持平台列表仍是 Android、iOS、Web、Windows、macOS、Linux，没有把 HarmonyOS/OpenHarmony 列为官方支持平台。OpenHarmony-SIG / 社区 Flutter 分支已能构建 `ohos` / `hap`，但它基于特定 Flutter 版本与 OpenHarmony 工具链，插件兼容性需要逐个确认。CodexFlow 当前依赖 `http`、`image_picker`、`shared_preferences`、`flutter_markdown`、`provider`、`intl`；纯 Dart 包风险低，平台插件和 Markdown 渲染细节需要验证。
- Web/PWA 方案与当前仓库最贴合：仓库已支持 Flutter Web，README 已写明 Tailscale Service 拓扑，Agent 已有 CORS。它不能替代系统通知和可靠后台监控，但可作为 HarmonyOS 手机上的低成本可用入口。

决策建议：

1. **PoC 选原生 ArkTS/ArkUI**：只做 dashboard、session detail、approval、SSE 或轮询、图片上传、通知/后台验证。目标是验证系统能力与审核风险。
2. **MVP 再决定是否继续原生**：如果后台监控和通知可接受，原生路线更稳；如果只是前台控制台，Web/PWA 已足够。
3. **Flutter 鸿蒙化作为备选实验**：适合验证 UI 复用率，但不应依赖它解决后台、通知、插件和上架问题。

## 2. 当前 CodexFlow 基线

仓库当前形态：

- `Go Agent`：`cmd/codexflow-agent`，对外提供稳定的 HTTP API 与 SSE。
- `Flutter App`：`flutter/codexflow`，用于 Android / Web / 桌面；当前依赖 `http`、`image_picker`、`shared_preferences`、`flutter_markdown`、`provider`、`intl`。
- `iOS App`：`ios/CodexFlow`，SwiftUI 客户端。
- Android 原生扩展：`flutter/codexflow/android/app/src/main/kotlin/.../monitor` 实现前台监控服务和通知。

关键接口：

- `GET /healthz`
- `GET /api/v1/dashboard`
- `GET /api/v1/sessions`
- `POST /api/v1/sessions`
- `GET /api/v1/sessions/:id`
- `POST /api/v1/sessions/:id/resume`
- `POST /api/v1/sessions/:id/end`
- `POST /api/v1/sessions/:id/archive`
- `POST /api/v1/sessions/:id/turns/start`
- `POST /api/v1/sessions/:id/turns/steer`
- `POST /api/v1/sessions/:id/turns/interrupt`
- `GET /api/v1/sessions/:id/media/:mediaId`
- `POST /api/v1/uploads/image`
- `GET /api/v1/skills`
- `GET /api/v1/approvals`
- `POST /api/v1/approvals/:id/resolve`
- `GET /api/v1/events`

对 HarmonyOS App 来说，Go Agent 不需要改架构；重点是客户端工程和系统能力适配。

## 3. 可选路线对比

| 路线 | 适合程度 | 优点 | 主要代价 | 结论 |
| --- | --- | --- | --- | --- |
| 原生 HarmonyOS ArkTS/ArkUI | 高 | 系统 API、通知、后台、权限、Deep Link、签名上架路径最直接；符合 HarmonyOS NEXT 主推 Stage 模型 | 需要新写 UI 与 API client；Markdown/代码高亮生态需选型；后台常驻仍需验证 | 推荐 PoC/MVP 主路线 |
| Flutter 迁移/鸿蒙化 | 中 | 可能复用现有 Flutter UI、状态模型、HTTP client 思路；当前 App 已跨端 | Flutter 官方未列 HarmonyOS 为支持平台；OpenHarmony Flutter 分支、engine、插件、DevEco/HAP 构建链要额外维护；`image_picker`、`shared_preferences` 等插件需确认 ohos 实现 | 作为并行技术 Spike，不作为首选交付路线 |
| Web/PWA/Tailscale 浏览器方案 | 中高（短期） | 当前仓库已有 Flutter Web、Agent CORS、Tailscale Service 拓扑；开发和发布成本最低；跨设备访问安全边界清晰 | 无可靠系统级后台监控；通知能力受浏览器和系统限制；文件选择/上传、PWA 安装体验不如原生 | 作为近期可用兜底和 Beta 分发入口 |

### 3.1 原生 ArkTS/ArkUI

原生路线建议使用 HarmonyOS Stage 模型、ArkTS、ArkUI。ArkUI 是 HarmonyOS 的声明式 UI 框架，Stage 模型是 HarmonyOS NEXT 主推并长期演进的应用模型，适合从一开始按手机/平板多窗口适配组织代码。

CodexFlow 原生项目建议结构：

```text
harmonyos/CodexFlow/
  AppScope/
  entry/
    src/main/ets/
      entryability/EntryAbility.ets
      pages/
        DashboardPage.ets
        SessionBrowserPage.ets
        SessionDetailPage.ets
        ApprovalPage.ets
        SettingsPage.ets
      services/
        ApiClient.ets
        EventStreamClient.ets
        UploadClient.ets
        NotificationService.ets
        MonitorService.ets
      models/
      storage/
      ui/
    src/main/module.json5
```

实现策略：

- 先复刻 Flutter App 的信息架构：Session Overview Home、Session Browser、Chat Timeline、Approval Center、Settings。
- ArkTS `ApiClient` 对齐 `flutter/codexflow/lib/services/api_client.dart` 的方法名和 DTO，降低接口理解成本。
- SSE 可优先用 Network Kit 流式响应能力验证；如 SSE 在后台或特定系统版本不稳定，MVP 可退回 dashboard 轮询。
- 图片上传用系统文件/照片 Picker 拿 URI，再复制到应用沙箱或读取为 `ArrayBuffer`，通过 multipart 提交 `/api/v1/uploads/image`。
- 通知与后台监控不照搬 Android foreground service，而按 Background Tasks Kit / Notification Kit 的约束重新设计。

### 3.2 Flutter 迁移/鸿蒙化

OpenHarmony-SIG / 社区 Flutter 分支提供 `ohos` 平台构建能力，文档显示可通过 `flutter create --platforms ohos` 和 `flutter build hap` 产出 HAP，并要求 DevEco Studio / command-line-tools、HarmonyOS SDK、Java 17、ohpm、hvigor 等环境。

对 CodexFlow 的迁移判断：

- `http`：纯 Dart，理论风险低，但 SSE 仍需自己实现或继续轮询。
- `provider`、`intl`：纯 Dart，风险低。
- `flutter_markdown`：纯 Dart + Flutter 渲染，风险中；需验证长聊天、代码块、图片和复制交互性能。
- `shared_preferences`：需要 ohos 插件实现或替代。
- `image_picker`：需要 ohos 插件实现；否则必须写平台通道接 HarmonyOS PhotoViewPicker。
- Android Kotlin 前台服务和通知逻辑不能复用，需要重新写 ohos 原生侧。

因此 Flutter 鸿蒙化的真实收益主要是复用 UI 与 Dart 模型，不是复用系统能力。若目标是快速上架可靠 HarmonyOS App，原生 PoC 更能提前暴露系统限制。

### 3.3 Web/PWA/Tailscale 浏览器方案

CodexFlow 已经具备 Web 路线基础：

- Flutter Web 构建产物可作为静态站点部署。
- Go Agent 已支持 CORS。
- README 已建议通过 Tailscale Service 暴露：
  - `/healthz -> http://127.0.0.1:4318/healthz`
  - `/api -> http://127.0.0.1:4318/api`
  - `/ -> http://127.0.0.1:8088`

HarmonyOS 手机上的浏览器访问该入口，能覆盖 dashboard、session、approval、prompt、图片上传等前台工作流。它的限制是后台监控和通知不可作为核心承诺。适合 PoC 期间作为“无需安装原生 App 的可用方案”，也适合 Beta 阶段给用户试用。

## 4. CodexFlow 能力映射

| CodexFlow 能力 | 当前实现 | HarmonyOS 原生映射 | 风险等级 | 建议 |
| --- | --- | --- | --- | --- |
| HTTP JSON | Flutter `http` 调 Agent API | Network Kit `http.createHttp().request()`；声明 `ohos.permission.INTERNET` | 低 | 直接实现统一 `ApiClient` |
| SSE `/api/v1/events` | Go Agent 已提供；Flutter 目前主要还可轮询 | Network Kit `requestInStream()` 与 `dataReceive` / `dataEnd` 类事件可验证 SSE | 中 | PoC 必测；失败则保留轮询 |
| 图片选择 | Flutter `image_picker` | `PhotoViewPicker` / FilePicker；Picker URI 通常是临时授权 | 中 | 选择后立即复制/读取到沙箱再上传 |
| 图片上传 | `POST /api/v1/uploads/image` multipart，15MB 限制 | Network Kit multipart 或手工构造 multipart body | 中 | 先测 1-5MB JPEG/PNG，再测 15MB 边界 |
| 前台/后台保活 | Android foreground service + persistent notification，10s/30s 轮询 | Background Tasks Kit 长时任务、短时任务、代理提醒、WorkScheduler；系统会管控不匹配场景 | 高 | 最大 PoC 风险；不要承诺 Android 等价后台常驻 |
| 通知 | Android notification channels：persistent/manual/turn result | Notification Kit；可能需用户授权 `requestEnableNotification` | 中高 | 区分状态通知与提醒通知；验证权限、静音、点击跳转 |
| Deep Link | Android 通知 route intent；未来可接 App Linking | App Linking 或 `module.json5` skills URI | 中 | MVP 支持 `codexflow://session/:id` 或 App Linking |
| 权限 | Android `INTERNET`、`POST_NOTIFICATIONS`、FGS 权限 | `ohos.permission.INTERNET`、通知授权、后台/提醒相关权限 | 中 | 权限最小化，写入审核说明 |
| 文件缓存 | Flutter `shared_preferences` + 图片由后端持久化 | Preferences 保存 base URL/token；`cacheDir/filesDir` 缓存缩略图 | 低中 | 不缓存敏感审批结果；缓存可重建数据 |
| Markdown/代码渲染 | `flutter_markdown` | ArkUI `RichText`/`Text` 组合或 ohpm Markdown 库；代码高亮需单独选型 | 中 | MVP 先支持 Markdown 子集和等宽代码块 |
| 状态轮询 | Android monitor service 轮询 dashboard | 前台 10s、后台按系统允许降频；或用户打开时刷新 | 中高 | 如果后台不可控，定义为前台可靠、后台尽力而为 |

## 5. 工程落地步骤

### 5.1 开发环境

1. 安装 HUAWEI DevEco Studio 和 HarmonyOS SDK。
2. 使用 Stage 模型创建 ArkTS / ArkUI 空应用，目标 API 版本优先选当前 DevEco 推荐稳定版本。
3. 配置 `hdc` 真机调试，准备至少一台 HarmonyOS NEXT 真机；模拟器不足以验证后台、通知和省电管控。
4. 建立单独目录 `harmonyos/CodexFlow`，不要混入现有 Flutter 工程。

### 5.2 项目结构与接口复用

1. 从 `flutter/codexflow/lib/models/app_models.dart` 和 iOS `APIModels.swift` 梳理 DTO 字段，生成 ArkTS models。
2. 以 `flutter/codexflow/lib/services/api_client.dart` 为行为蓝本写 ArkTS `ApiClient`：
   - `dashboard()`
   - `skills()`
   - `sessionDetail(id, turnOffset, turnLimit)`
   - `refreshSessions()`
   - `startSession()`
   - `resumeSession()`
   - `startTurn()`
   - `steerTurn()`
   - `interruptTurn()`
   - `resolveApproval()`
   - `uploadImage()`
3. UI 状态命名沿用仓库 glossary：Session Overview Home、Session Browser、Chat Timeline、Manual Action Required、Mobile Background Monitoring。

### 5.3 认证与安全

当前 Agent 没有内置登录和设备配对。HarmonyOS App 不应扩大暴露面：

- 默认只允许用户填写 LAN/Tailscale HTTPS 地址，不鼓励公网 HTTP。
- Settings 中明确标识当前 Agent 地址、协议、最后连接时间。
- MVP 前建议为 Agent 增加最小 token 认证或设备配对；否则 AppGallery 上架时，远程控制本机 Codex 的安全说明会很难写。
- 本地只持久化 base URL、token、UI 偏好；不要缓存 prompt、审批内容或会话媒体的敏感副本，除非有明确清除策略。

### 5.4 测试

PoC 测试矩阵：

- 网络：LAN HTTP、Tailscale HTTPS、断网、DNS 失败、Agent 关闭。
- SSE：前台持续 30 分钟、锁屏、切后台、网络切换。
- 轮询：前台 10s、后台 30s/60s，观察系统是否挂起。
- 图片：相册 JPEG/PNG、截图、大图、超过 15MB、无权限/取消选择。
- 通知：首次授权、拒绝授权、点击跳转 dashboard/approval/session、静音状态通知。
- Deep Link：冷启动、热启动、已在 session detail 时跳转。
- 长聊天：100/500/1000 turns，分页加载和滚动到底部性能。

### 5.5 打包签名与分发

1. DevEco Studio 生成 debug 签名，先保证真机安装和调试。
2. AppGallery Connect 创建 HarmonyOS 应用，确认 bundle name、应用分类、隐私政策和权限声明。
3. 配置 release 证书、Profile、签名信息，产出 HAP / App Pack。
4. Beta 用 AppGallery Connect 测试分发或企业内测渠道；不要把未认证 Agent 控制能力直接公开给大规模用户。
5. 上架前补齐隐私政策：
   - 说明连接用户自有 Agent 地址。
   - 说明图片上传到用户自有 CodexFlow Agent，而非第三方云。
   - 说明通知只用于 pending approval、turn result、Agent 状态。

## 6. 风险与未知项

- 系统版本风险：HarmonyOS / HarmonyOS NEXT / OpenHarmony API 版本差异会影响 Network Kit、Background Tasks Kit、Notification Kit、Picker 和签名流程。必须以目标真机 API 为准。
- 后台限制风险：CodexFlow 的 Android 设计依赖 foreground service。HarmonyOS Stage 模型对后台驻留有明确管控，长时任务需符合系统类型和用户可感知场景；“持续轮询开发机 Agent”可能不被视为合规长时任务。
- 通知权限风险：通知需要用户授权，用户拒绝后 Manual Action Required 只能在前台显示，不能作为可靠提醒。
- Flutter 鸿蒙生态成熟度：社区 Flutter 分支可构建 HAP，但版本、engine、插件、ohpm/DevEco 集成与官方 Flutter 主线存在距离。后续维护成本不可忽略。
- 上架限制：CodexFlow 是远程控制本机 AI coding agent 的客户端，涉及执行命令、审批文件修改、上传图片。AppGallery 审核可能关注远程控制、安全告知、隐私政策、后台运行理由和通知用途。
- Markdown/代码渲染风险：聊天时间线需要可读代码块、列表、链接、图片。ArkUI 原生没有现成等价于 `flutter_markdown` 的官方高级组件，需要选库或先实现子集。
- Tailscale 依赖风险：Web/Tailscale 方案安全性好，但依赖用户已有 tailnet 和浏览器体验；不等同于面向普通用户的一键 App。
- Agent 认证风险：当前 README 明确提醒不要公网暴露 Agent。HarmonyOS App 如果进入 Beta，应把 token/配对列为前置需求。

## 7. 里程碑建议

### PoC：2-3 周

目标：验证“能不能做”和最大风险。

- ArkTS 原生壳：Settings 配 Agent URL，Dashboard 拉取真实数据。
- Session Browser + Session Detail 只读，支持分页。
- Approval Center 支持 resolve。
- 图片选择 + 上传 + startTurn。
- SSE 与轮询二选一验证。
- 后台监控 + 通知做系统能力验证，不承诺产品体验。

验收：

- 真机能通过 LAN/Tailscale 访问 Go Agent。
- 处理一次真实 pending approval。
- 发送一次带图片的 prompt。
- 切后台/锁屏后记录系统是否继续轮询和通知。

### MVP：4-6 周

目标：可供项目自用。

- 完整四页：首页、会话列表、聊天详情、审批中心、设置。
- Chat Timeline 支持 Markdown 子集、代码块、图片缩略图/预览。
- Deep Link/通知点击跳转。
- 稳定错误态、重试、超时、离线提示。
- 权限说明、隐私说明、基础日志。
- 若后台不可持续，改为“前台实时 + 后台尽力提醒”的明确产品定义。

验收：

- 真实开发日使用 1 周，覆盖 Codex 和 Claude Code 会话。
- 长会话滚动无明显卡顿。
- Agent 离线/重启/地址变更不会卡死。

### Beta：6-10 周

目标：小范围分发和审核准备。

- 加入 Agent token/设备配对。
- AppGallery Connect 测试分发。
- 完成 release 签名、隐私政策、权限用途说明。
- 增加崩溃/日志导出路径。
- 梳理不支持项：后台常驻、通知可靠性、Tailscale 要求。

验收：

- 5-10 台 HarmonyOS 真机覆盖不同系统版本。
- 安装、升级、清除数据、权限拒绝、通知禁用路径均可恢复。
- 审核材料能解释后台、通知、网络和图片权限。

## 8. 参考链接

官方 / 可信资料：

- Huawei ArkUI：<https://developer.huawei.com/consumer/cn/arkui/>
- Huawei Stage 模型开发概述：<https://developer.huawei.com/consumer/cn/arkui/arkui-stage/>
- Huawei HarmonyOS 开发入口：<https://www.harmonyos.com/en/develop>
- Huawei DevEco Studio：<https://developer.huawei.com/consumer/en/deveco-studio/>
- Huawei HarmonyOS HTTP 数据请求指南：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/http-request-V5>
- Huawei HarmonyOS HTTP API 参考：<https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-http-V5>
- Huawei HarmonyOS PhotoViewPicker：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/photoaccesshelper-photoviewpicker-V5>
- Huawei HarmonyOS 权限声明：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/declare-permissions-V5>
- Huawei HarmonyOS 通知概述：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/notification-overview-V5>
- Huawei HarmonyOS NotificationManager API：<https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-notificationmanager-V5>
- Huawei HarmonyOS 后台任务概述：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/background-task-overview-V5>
- Huawei HarmonyOS 长时任务：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/continuous-task-V5>
- Huawei HarmonyOS 文件管理 fs API：<https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-file-fs-V5>
- Huawei AppGallery Connect：<https://developer.huawei.com/consumer/en/agconnect/>
- Huawei App Linking HarmonyOS Codelab：<https://developer.huawei.com/consumer/en/codelab/AppLinking-HarmonyOS/>
- Flutter 官方支持平台：<https://docs.flutter.dev/reference/supported-platforms>
- Flutter 多平台集成：<https://docs.flutter.dev/platform-integration>
- OpenHarmony-SIG Flutter 仓库：<https://gitee.com/openharmony-sig/flutter_flutter>
- OpenHarmony-SIG Flutter Samples 文档：<https://gitee.com/openharmony-sig/flutter_samples/tree/master/ohos/docs>
- OpenHarmony Preferences API 文档：<https://gitee.com/openharmony/docs/blob/11de65f7c5cef042ad815f42a174f1bba02be3da/en/application-dev/reference/apis-arkdata/js-apis-data-preferences.md>
- OpenHarmony ArkTS UI 开发概述：<https://gitee.com/openharmony/docs/blob/ca6c3667fc6aec1ef95fc7438d8de4fd3b552d68/en/application-dev/ui/arkts-ui-development-overview.md>
- Tailscale Serve 文档：<https://tailscale.com/kb/1242/tailscale-serve>

仓库内参考：

- `README.md`
- `CONTEXT.md`
- `docs/architecture.md`
- `docs/adr/0001-persistent-chat-media-attachments.md`
- `flutter/codexflow/lib/services/api_client.dart`
- `flutter/codexflow/pubspec.yaml`
- `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/CodexFlowMonitorService.kt`
- `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/CodexFlowNotifications.kt`
- `internal/httpapi/server.go`
