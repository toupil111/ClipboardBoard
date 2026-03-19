# iPhone 真机安装与长期自用说明

## 先回答一个关键问题

### 不配置 Xcode 工程，能不能直接安装到 iPhone？

通常不行。

原因是 iPhone 真机安装不仅需要源码，还需要：

- iOS App Target
- Signing 签名
- Bundle Identifier
- Provisioning Profile
- Capabilities
- Entitlements

这些都不是单纯放几份 Swift 文件就能完成的。

所以当前仓库里的 [sources App](../README.md) 是“源码骨架”，真正装到 iPhone 上，仍然需要生成并打开一个 Xcode 工程。

## 当前最低系统版本

当前已按 `iOS 18+` 规划：

- Xcode 工程配置目标：iOS 18.0
- Widget / App / Share Extension 统一按 iOS 18.0 处理

## 一、创建 Xcode 工程

### 先确认你装的是完整 Xcode，不只是 Command Line Tools

如果只有 Command Line Tools，`xcodebuild` 无法构建 iOS App。

你需要：

1. 从 App Store 安装完整 Xcode
2. 首次打开一次 Xcode 完成组件安装
3. 必要时切换开发者目录到 Xcode

常见检查方式：

- `xcode-select -p`

如果看到的是：

- `/Library/Developer/CommandLineTools`

说明当前还不是完整 Xcode 环境。

当前已经补好了 XcodeGen 配置文件：

- [sources App/Config/project.yml](../Config/project.yml)

你可以用两种方式：

### 方式 A：直接用 Xcode 手工建工程

适合你想自己完全掌控 Target。

### 方式 B：用 XcodeGen 自动生成工程

这是我更推荐的方式，因为当前目录已经帮你配好了：

- App Target
- Widget Extension Target
- Share Extension Target
- Info.plist
- entitlements
- iOS 18 部署版本

#### 用 XcodeGen 生成工程

1. 安装 XcodeGen
2. 进入 [sources App](../README.md)
3. 使用 [sources App/Config/project.yml](../Config/project.yml) 生成 `.xcodeproj`
4. 用 Xcode 打开生成后的工程

如果你本机装了 Homebrew，一般就是：

- `brew install xcodegen`
- 在 `sources App` 目录下执行 `xcodegen generate -s Config/project.yml`

当前目录中我已经生成好了工程文件：

- [sources App/Config/ClipboardMobile.xcodeproj](../Config/ClipboardMobile.xcodeproj)
- [ClipboardSuite.xcworkspace](../../ClipboardSuite.xcworkspace)

如果你同时要联调 Mac 和 iPhone，优先建议打开 Workspace：

- [ClipboardSuite.xcworkspace](../../ClipboardSuite.xcworkspace)

如果你仍想手工创建，建议在 Xcode 中新建 Workspace 或 Project：

1. 打开 Xcode
2. New Project
3. 选择 iOS App
4. Product Name 填：`ClipboardMobile`
5. Interface 选 `SwiftUI`
6. Language 选 `Swift`
7. 勾选 iPhone

然后把以下目录中的源码拖入工程：

- [sources App/iOSApp](../iOSApp)
- [sources App/Shared](../Shared)
- [sources App/WidgetExtension](../WidgetExtension)
- [sources App/ShareExtension](../ShareExtension)

## 二、Target 建议

当前已按以下 Target 规划好：

1. `ClipboardMobile`
2. `ClipboardWidgetExtension`
3. `ClipboardShareExtension`

并确保它们共用：

- 同一个 Team
- 同一个 App Group
- 同一个 iCloud / CloudKit 容器

## 三、Capabilities 配置

### App 主 Target

打开 Signing & Capabilities，添加：

- iCloud
  - 勾选 CloudKit
- App Groups
  - 添加：`group.com.liangweibin.clipboardboard`
- Associated Domains（如果后续要扩展）可选

### Widget 与 Share Extension

同样添加：

- App Groups
- 如需直连 CloudKit，再添加 iCloud

## 四、Bundle Identifier 建议

- App：`com.liangweibin.clipboardmobile`
- Widget：`com.liangweibin.clipboardmobile.widget`
- Share Extension：`com.liangweibin.clipboardmobile.share`

CloudKit 容器建议：

- `iCloud.com.liangweibin.clipboardboard`

## 五、如何安装到自己的 iPhone

1. iPhone 用数据线连接 Mac
2. 在 Xcode 顶部选择你的 iPhone 作为运行目标
3. 在 Signing 中选择你的开发者 Team
4. 首次运行时，手机上到“设置 -> 通用 -> VPN 与设备管理”中信任证书
5. 再次运行即可安装到手机

## 六、如何避免 7 天失效

### 结论

要长期稳定使用，请使用付费 Apple Developer Program。

### 原因

- 免费 Apple ID 开发签名，真机安装通常约 7 天失效
- 付费开发者账号后，开发配置文件有效期通常约 1 年
- 这才是“不上架 App Store 但长期自己使用”的稳定方案

## 七、如果不想上架 App Store

你仍可以：

- 只在自己的设备安装
- 不公开分发
- 用 Xcode 本地签名运行

但前提是：

- 你有付费开发者账号
- 你接受每年续一次开发者资格

## 八、微信分享文件说明

如果文件需要分享到微信：

1. 先把文件同步到 iPhone 本地可访问目录
2. 在 App 中通过系统分享面板发起分享
3. 微信若支持该类型，会出现在分享目标中

注意：

- 不能直接引用 Mac 的本地路径
- 必须是 iPhone 本地或 iCloud 已下载文件

## 九、推荐开发顺序

1. 先跑通主 App 列表
2. 再接 CloudKit 拉取真实数据
3. 再做 Widget
4. 最后做 Share Extension 与文件分享
