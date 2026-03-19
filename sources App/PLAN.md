# iOS 粘贴板 App 规划

## 目标

新增一个 iPhone App，与现有 Mac 粘贴板联动，实现：

1. Mac 端复制历史同步到 iPhone App
2. iPhone App 以列表展示剪贴板历史
3. 支持文本、图片、PDF、DOC、常见文件
4. 提供 iOS 小组件，桌面可查看最近若干条内容
5. 文本支持一键复制
6. 文件支持系统分享，转发到微信等 App

## 先说限制

### iOS 无法完全后台监听所有“输入法粘贴”动作

苹果系统限制较多，以下能力不能按 macOS 的方式完全实现：

- 不能在后台持续监听所有 App 的剪贴板变化
- 不能监听所有输入法内部的粘贴行为
- 不能直接读取 Mac 本地路径文件

### 可行替代方案

可采用以下组合：

1. Mac 端作为主采集端，负责记录复制历史
2. 使用 CloudKit 把历史同步到 iPhone
3. iPhone App 只负责展示、复制、分享
4. 如需 iPhone 侧补充内容，可增加：
   - Share Extension
   - 自定义 Keyboard Extension（仅限自己键盘场景）
   - App 前台读取系统剪贴板

## 推荐架构

### 1. 数据同步

推荐：CloudKit + 私有数据库

- 优点：苹果生态内稳定、免自建服务器、支持个人使用
- 同步内容：
  - 文本内容
  - 预览信息
  - 文件元数据
  - 文件二进制或文件云端引用

### 2. 数据模型

统一一份 `ClipboardEntry`：

- `id`
- `createdAt`
- `type`：text / image / pdf / doc / file / audio / video
- `title`
- `previewText`
- `fileName`
- `mimeType`
- `localPath`
- `cloudAssetKey`
- `thumbnailPath`
- `sourceDevice`
- `isPinned`

### 3. Mac 到 iPhone 同步链路

1. Mac 监听复制内容
2. 转成统一模型
3. 文本直接同步
4. 文件/图片/PDF 上传为 CloudKit 资源
5. iPhone 拉取最近 50 条并本地缓存

### 4. iOS App 页面

#### 首页列表

- 顶部：同步状态、搜索、筛选
- 中间：历史列表
- 每项内容：
  - 左侧预览
  - 中间标题/摘要
  - 右侧按钮
    - 文本：复制
    - 文件：分享

#### 文件项交互

- 图片/PDF/DOC：点开预览
- 右侧按钮：调用系统分享面板
- 分享目标可选微信、企业微信、邮件等

## 小组件规划

使用 WidgetKit

### 展示方式

- 显示最近 3~6 条
- 每条只显示一小段摘要
- 右侧放按钮

### 交互建议

#### 文本项

- iOS 17+ 可做交互式按钮
- 更稳妥方式：点击后打开 App 并立即复制

#### 文件项

- 小组件不能直接弹系统分享面板
- 建议点击后打开 App 的详情页，再分享给微信

## 微信分享说明

### 文本

- 可复制后手动粘贴到微信
- 或打开 App 后调系统分享面板

### 文件

可以，但前提是文件已经在 iPhone 本地可访问：

- 不能直接访问 Mac 本地路径
- 必须先把文件同步到 iPhone 沙盒 / App Group / iCloud 下载目录
- 然后通过 `UIActivityViewController` 调系统分享
- 微信若支持该文件类型，就可以转发给微信好友

## 推荐实现阶段

### 阶段 1：基础同步版

- 建 iOS App
- CloudKit 同步最近 50 条
- 列表展示文本/图片/PDF/文件
- 文本复制
- 文件分享

### 阶段 2：小组件版

- Widget 展示最近若干条
- 点击跳转 App
- 文本快速复制

### 阶段 3：iPhone 补充采集

- Share Extension
- 前台读取系统剪贴板
- 可选 Keyboard Extension

## 目录建议

当前已创建目录：

- `sources App/`

后续建议结构：

- `sources App/iOSApp/`
- `sources App/WidgetExtension/`
- `sources App/ShareExtension/`
- `sources App/Shared/`
- `sources App/Docs/`

## 打包到自己手机且不想 7 天失效

### 唯一稳定方案

加入 Apple Developer Program 付费开发者账号。

原因：

- 免费 Apple ID 签名，安装到真机通常 7 天左右需要重新签
- 想长期自己使用，又不上架 App Store，最稳妥就是付费开发者账号

### 推荐方式

1. 开通 Apple Developer Program
2. 用 Xcode 真机签名安装
3. 使用自己的 Team、Bundle ID、Provisioning Profile
4. 安装到自己的 iPhone
5. 有效期通常为 1 年，到期后重新签名一次即可

### 不上架 App Store 也能长期自己用吗

可以，但前提是：

- 你有付费开发者账号
- 用开发/Ad Hoc 方式签名到自己的设备

### 无法做到的点

- 不付费
- 不上架
- 还永久不限期

这三者通常不能同时成立。

## 下一步建议

优先做：

1. iOS App 主体
2. CloudKit 同步层
3. Widget
4. 文件分享到微信
5. Share Extension
