# ClipboardBoard

[中文](#中文说明) | [English](#english)

---

## 中文说明

ClipboardBoard 是一个使用 Swift 开发的 macOS 剪贴板工具，用来快速查看、管理和粘贴常用内容。

### 安装与使用

直接使用 [dist/ClipboardBoard.dmg](dist/ClipboardBoard.dmg) 安装包即可使用，完全本地运行。

### 主要功能

- 最多保留 50 条剪贴板历史
- 支持文本、图片、PDF、音频、视频和常见文件
- 使用 `Option + Command + V` 快速唤醒面板
- 支持收藏、置顶、删除和自定义标签分组
- 点击条目后可快速恢复并粘贴内容
- 支持开机启动
- 本地持久化保存，重启后仍可继续使用

### 说明

- 本项目主要用于 macOS 本地使用
- 安装包目录： [dist](dist)
- 首次使用自动粘贴功能时，可能需要授予辅助功能权限

---

## English

ClipboardBoard is a macOS clipboard manager built with Swift for quickly viewing, organizing, and pasting frequently used content.

### Install and Use

Use the installer in [dist/ClipboardBoard.dmg](dist/ClipboardBoard.dmg) directly.
It runs fully locally on your Mac.

### Features

- Keeps up to 50 clipboard history items
- Supports text, images, PDF, audio, video, and common files
- Open the panel with `Option + Command + V`
- Supports favorites, pinning, deletion, and custom tag groups
- Click an item to restore and paste it quickly
- Supports launch at login
- History is stored locally and remains available after restart

### Notes

- This project is mainly designed for local macOS usage
- Installer output directory: [dist](dist)
- Accessibility permission may be required for auto-paste on first use
