# 免费 Apple ID 安装到 iPhone 真机

如果在 Xcode 里选择团队时出现以下错误：

- `No profiles for 'com.liangweibin.clipboardmobile.share' were found`
- `Your team has no devices from which to generate a provisioning profile`

通常是因为当前工程包含：

- Share Extension
- Widget Extension
- CloudKit / App Groups 等能力

这些在免费 Apple ID 下更容易卡住。

## 最稳妥做法

先只安装一个“精简主 App”到真机，不带：

- Widget
- Share Extension
- 复杂 capability

## 已提供的精简工程配置

- [sources App/Config/project-free.yml](../Config/project-free.yml)

生成命令：

- `cd "sources App"`
- `xcodegen generate -s Config/project-free.yml`

生成后打开：

- `sources App/Config/ClipboardMobileFree.xcodeproj`

## 在 Xcode 中这样配

1. 选 `ClipboardMobileFree` target
2. `Signing & Capabilities`
3. 勾 `Automatically manage signing`
4. `Team` 选你的免费 Apple ID
5. 如有冲突，把 Bundle Identifier 改成你自己的唯一值

例如：

- `com.yourname.clipboardmobile.free`

## 真机运行

1. 顶部运行目标选择你的 iPhone
2. 点击 Run
3. 如果提示开发者模式，去手机开启
4. 如果提示未受信任开发者，去手机信任证书

## 说明

这个精简版优先解决“先装上手机”问题。

装上之后，再逐步回到完整工程：

- [sources App/Config/ClipboardMobile.xcodeproj](../Config/ClipboardMobile.xcodeproj)
