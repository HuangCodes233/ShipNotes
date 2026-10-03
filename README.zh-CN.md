# ShipNotes

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

[![CI](https://github.com/HuangCodes233/ShipNotes/actions/workflows/ci.yml/badge.svg)](https://github.com/HuangCodes233/ShipNotes/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

ShipNotes 是一款原生 macOS 应用，用于从本地文件准备、预览和同步多语言 App Store 更新说明、商店文案与截图。

**项目状态：早期开发者预览。** 请从源码构建，并先使用演示账号。签名安装包分发及真实服务流程仍有待验证。

## 功能

- **更新说明**：导入 Markdown、YAML、JSON 和变更日志，映射语言区域，查看差异，并在同步前校验草稿。
- **商店文案**：按语言编辑描述、关键词、副标题、宣传文本和商店链接。
- **截图**：扫描文件夹，检查设备尺寸和语言覆盖，预览上传或替换内容。
- **可选 AI**：使用自己的 OpenAI 兼容服务或 Anthropic 凭据，进行解析、翻译、文案优化和截图语言识别。
- **Apple Ads**：使用独立凭据查看报告，管理广告活动和关键词。
- **原生界面**：支持英语、简体中文和日语；macOS 26 及以上使用 Liquid Glass，较早系统使用材质回退。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| 部署目标 | macOS 14 及以上；macOS 14/15 的实际运行表现仍待验证 |
| 构建工具 | Xcode 26 及以上、macOS 26 或更新的 SDK，以及 Swift 6 支持 |
| 演示账号 | 全新安装无需 Apple 或 AI 凭据 |
| 真实 App Store 访问 | 自己的 App Store Connect API 凭据，以及对应应用的必要权限 |
| 可选服务 | 分别配置 AI API Key 和 Apple Ads 凭据 |

请使用完整的 Xcode 安装。项目没有第三方 Swift 包依赖。

## 快速开始

构建使用临时签名的本地应用：

```sh
git clone https://github.com/HuangCodes233/ShipNotes.git
cd ShipNotes
CONFIG=debug SIGN_IDENTITY=- ./scripts/build-app.sh
open dist/ShipNotes.app
```

首次启动时选择 **先体验示例**（Explore the demo first）：

1. 选择示例应用和可编辑版本。
2. 在“发布说明”中，以文件夹方式导入 `Examples/release-notes/1.4.0/`，或以文件方式导入 `Examples/release-notes/1.5.0.yaml`。
3. 选择语言，编辑草稿，检查差异，然后执行“试运行”（Dry Run）。
4. 查看商店文案、截图和 Apple Ads 工作区。

已配置过的安装可能在启动时恢复保存的凭据并连接真实服务。同步前请检查连接状态及所选应用、版本。

## 更新说明文件

可以按语言分别保存 Markdown 文件，例如 `1.4.0/en-US.md`；也可以使用包含版本号和语言映射的 YAML/JSON 文档。以下是 YAML 示例：

```yaml
version: 1.5.0
locales:
  en-US: |
    • Added folder watching.
  zh-Hans: |
    • 新增文件夹监听。
  ja: |
    • フォルダ監視を追加しました。
```

[示例目录](Examples/release-notes/)包含多语言 Markdown 和 YAML 文件。应用也支持变更日志和合并的元数据文档；内容存在歧义时，会提供导入预览供你确认。

## 服务连接与隐私

在“设置 → 账号”中填写 App Store Connect 的 Issuer ID、Key ID 和 `.p8` 私钥。需要 AI 或 Apple Ads 时，分别配置对应凭据。向真实服务写入前，请核对目标应用、版本、语言和待提交内容。

凭据保存在 macOS 钥匙串中；偏好设置、路径和同步历史保存在本机。AI 操作会将输入文本或截图缩略图发送给配置的服务商；自定义端点会收到该配置的请求和凭据。处理私密素材前，请阅读[凭据与数据流说明](docs/privacy-and-data.md)。

## 开发

在 Xcode 中打开 `Package.swift`，或使用 SwiftPM。统一执行格式检查、功能测试和空白字符检查：

```sh
./scripts/check.sh
```

开发时构建并启动应用：

```sh
./scripts/run-app.sh
```

运行脚本默认使用 debug 构建和临时签名，启动前会停止已有的 ShipNotes 进程。脚本还支持 `--verify`、`--debug`、`--logs` 和 `--telemetry`。Codex Run 使用同一个入口。

CI 在 Xcode 26.3 和 Xcode 27 上运行测试，在 Xcode 27 上检查 Swift 格式，并使用 Gitleaks 扫描 Git 历史。[开发指南](docs/development.md)介绍目录职责与检查方式，[性能探针说明](docs/performance.md)提供可选基准测试命令。

## 打包与当前限制

构建 release 配置的本地应用包：

```sh
CONFIG=release VERSION=0.1.0 BUILD=1 SIGN_IDENTITY=- ./scripts/build-app.sh
```

输出为 `dist/ShipNotes.app`。打包脚本支持 Developer ID 签名及可选公证；临时签名用于本地开发。

目前仍有以下验证缺口：

- App Store Connect、Apple Ads 和 AI 操作主要由测试替身覆盖，尚未完成真实服务的端到端验证。
- Developer ID 分发、公证和另一台 Mac 上的安装尚未验证。
- 尚未实现 Mac App Store 沙盒权限及持久化的安全作用域书签。
- 较早 macOS 版本的实际运行和自动化 UI 覆盖仍需补充。

持续维护的后续工作清单见[开发状态](docs/development-status.md)。

## 贡献与安全

提交 PR 前请阅读[贡献指南](CONTRIBUTING.md)。报告问题时，请提供最小复现、提交版本、macOS/Xcode 版本及脱敏样例。较大的改动建议先在 Issue 中讨论。

请按[安全报告说明](SECURITY.md)私下报告漏洞。公开 Issue、截图和日志中不要包含凭据、客户数据或个人路径。

## 许可证

代码、脚本和文档采用 [MIT 许可证](LICENSE)。AI 生成图标也在维护者有权许可的范围内按 MIT 提供，来源说明见[素材许可](docs/asset-licensing.md)。ShipNotes 名称和图标不授权你将衍生版本标示为官方发布。
