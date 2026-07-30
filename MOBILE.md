# Pesty for iPhone and iPad

这是 Pesty 的原生 SwiftUI 移动端，与同仓库的 macOS App 共用数据模型和 CloudKit 同步层。

## 已实现

- 历史记录、Pinboards、全文搜索、类型/来源/时间筛选
- 文本、富文本、链接、图片、文件和颜色
- App 在前台时监听剪贴板，也保留 Apple `PasteButton` 显式粘贴入口
- 图片 OCR 搜索、重命名、编辑、拖放、系统分享和 Spotlight
- 持久化 Paste Stack 队列与 Copy Next
- Pesty 自定义键盘：浏览 History/Pinboards，文本和链接直接插入
- Share Extension：从任意支持系统分享的 App 保存文本、链接、图片和文件
- App Group 本地缓存
- CloudKit 双向合并、冲突重试、删除墓碑
- CloudKit 共享 Pinboard：创建/接受共享，区分 Owner、Read Only、Read & Write
- 图片和文件通过 `CKAsset` 传输
- CloudKit 静默推送、Siri/App Intents
- Privacy Manifest、完整 App Icon、iPhone/iPad 方向与 Launch Screen 声明

## iOS 平台边界

iOS 不向第三方 App 提供 macOS 式全局剪贴板监听、全局快捷键或 Accessibility 自动粘贴。因此：

- Mac 继续自动捕获剪贴板。
- Pesty 在 iPhone/iPad 前台时可捕获剪贴板；后台通过系统 Paste 按钮、Share Sheet 或 Pesty Keyboard 显式采集。
- 键盘可直接插入文本和链接；图片、文件和富文本先复制，再由目标 App 的 Paste 操作完成。
- 密码等 Secure Text Field 会强制使用 Apple 系统键盘。

这些是 iOS 公共 API 的限制，不是 Pesty 设置项。

## 本地运行

要求：

- Xcode 26 或更新版本
- XcodeGen
- jq
- 已安装 iOS Simulator runtime

安装构建工具：

```bash
brew install xcodegen jq
```

运行：

```bash
./script/build_and_run.sh
```

验证：

```bash
./script/build_and_run.sh --verify
```

该命令会生成 Xcode 项目、签署本地模拟器构建、安装、启动并输出 App Container。它验证的是 Simulator smoke test，不是 iCloud 真机 E2E。

## 真机和 iCloud 配置

模拟器无需 Apple Developer 账号。真机与 CloudKit 需要你自己的 Apple Developer Team，并且 Mac 与 iOS targets 必须属于同一 Team。

在 `project.yml` 与 Mac packaging entitlements 中统一配置：

- Development Team：当前为 `H3WXHVTP97`
- 主 App：`com.greycorelabs.pesty`
- Keyboard：`com.greycorelabs.pesty.keyboard`
- Share Extension：`com.greycorelabs.pesty.share`
- App Group：`group.com.greycorelabs.pesty`
- CloudKit container：`iCloud.com.greycorelabs.pesty`
- Push Notifications 与 iCloud/CloudKit capabilities

如果你的 Team 不拥有这些标识符，需要在 `project.yml`、三个 entitlements、Mac packaging entitlements，以及源码中的 container/App Group 常量中一起替换。随后让 Xcode 生成三套 provisioning profiles。

CloudKit Development 环境首次运行后，在 CloudKit Console 创建并部署 Production schema：

- `PestySnapshot`
  - `payloadAsset`: Asset
  - `payload`: Bytes，兼容旧快照
  - `schemaVersion`: Int(64)
  - `updatedAt`: Date/Time
- `PestyAsset`
  - `asset`: Asset
  - `kind`: String
  - `fileName`: String
  - `clipID`: String
  - `index`: Int(64)

共享 Pinboard 使用自定义 zone `PestySharedPinboards` 和 `CKShare`。当前版本可创建、接受并按 CloudKit 权限读写；共享成员管理、撤销/退出、权限降级后的本地引用清理仍需真机双账号验收后再作为发布功能开放。

App 已带 `PrivacyInfo.xcprivacy`。App Group `UserDefaults` 声明 required-reason code `1C8F.1`；未声明跟踪或由 Pesty 收集的数据。

## 从现有 Mac 数据迁移

升级后的 Mac App 会继续读取现有 `store.json`。开启 Pesty 的 iCloud Sync 后，它会把历史记录、Pinboards、删除状态和图片/文件资产迁移到共同的 CloudKit container。之前从 Paste 导入到 Mac Pesty 的分类会随同该快照进入移动端。

## 发布验收

本地已通过：

- `PestyShared`：19 tests / 5 suites
- iOS：3 tests / 1 suite，从全新 DerivedData 构建
- macOS：严格警告构建
- Simulator：安装、启动、前台剪贴板采集、App Group 落盘和重启恢复

提交 TestFlight 前必须用真实 iCloud 账号完成：

1. Mac → iPhone：文本、富文本、链接、图片、文件、颜色和导入后的 Paste 分类。
2. iPhone → Mac：PasteButton、前台捕获、Share Extension、Keyboard 和 Stack。
3. 双向新增/改名/移动/删除、离线并发冲突、推送唤醒。
4. 两个 Apple ID：Read Only、Read & Write、权限降级、撤销和退出共享。
5. 大文件 `CKAsset`、扩展内存压力、网络中断恢复和生产 schema。

未完成这套真机矩阵前，模拟器成功不能表述为“Paste 的所有跨设备功能已发布可用”。
