# Mac 与 iPhone 的 CloudKit 联动配置

## 目标

让现有 Mac 粘贴板把最近 50 条历史同步到 iPhone App。

## 当前代码状态

Mac 端已新增：

- CloudKit 上传服务
- 最新 50 条自动上传
- 文本元数据上传
- 文件 / 图片 / PDF 资源上传为 CloudKit 资产

iPhone 端已新增：

- CloudKit 拉取骨架
- 拉取后把文件资产落地到本地目录
- 文本复制
- 文件分享入口
- Widget 读取本地缓存

## CloudKit 容器建议

统一使用：

- `iCloud.com.liangweibin.clipboardboard`

## 你需要在 Xcode 中打开的能力

### Mac App Target

- iCloud
  - 勾选 CloudKit
- 如果后续要共享缓存给 Extension，可再加 App Groups

### iPhone App Target

- iCloud
  - 勾选 CloudKit
- App Groups
  - `group.com.liangweibin.clipboardboard`

### Widget / Share Extension

- App Groups
- 如需直接访问 CloudKit，再加 iCloud

## CloudKit Record 约定

Record Type：

- `ClipboardEntry`

主要字段：

- `id`
- `createdAt`
- `type`
- `title`
- `previewText`
- `fileName`
- `mimeType`
- `localRelativePath`
- `cloudAssetKey`
- `thumbnailRelativePath`
- `sourceDevice`
- `isPinned`
- `asset`

## 为什么建议转成 Xcode App 工程

当前仓库中的 Swift Package 代码已经能组织逻辑，但要让 CloudKit 真正工作，通常还需要：

- 正式的 App Target
- Signing
- Capabilities
- Entitlements

这些能力更适合在 Xcode App 工程里配置。

## 推荐落地方式

1. 保留当前仓库源码
2. 用 Xcode 新建 macOS App 和 iOS App 工程
3. 把这里的 Swift 文件拖入对应 Target
4. 在 Xcode 中配置 Signing & Capabilities
5. 再分别运行 Mac 与 iPhone 端

## 下一步最推荐

1. 先把 Mac App Target 建出来并开通 iCloud
2. 跑通 Mac 上传 CloudKit
3. 再跑通 iPhone 拉取与分享
4. 最后补 Widget 与 Share Extension
