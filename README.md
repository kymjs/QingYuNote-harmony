# 轻羽云笔记

轻羽云笔记是一个运行在 HarmonyOS 手机上的本地优先云笔记应用。笔记正文保存在应用沙箱文件中，元数据保存在关系型数据库中，并在后台按策略同步到用户配置的 WebDAV 服务器。

## 特性

- 本地优先：笔记创建、编辑、删除全部先落本地。
- Markdown 编辑：支持标题、段落、引用、列表、代码块等基础语法实时预览。
- WebDAV 同步：支持手动立即同步、编辑后延迟同步、应用存活期间定时同步。
- 冲突处理：严格以最后操作时间较新的版本胜出，不做人工合并。
- 设置持久化：同步策略和 WebDAV 配置使用 Preferences 保存，密码通过 `cryptoFramework` 加密后写入本地。

## 目录结构

```text
entry/src/main/ets/
  common/
    model/        核心数据模型
    utils/        日志、时间、Markdown、路径等工具
  pages/          Index、NoteEdit、Settings 页面
  services/       DatabaseService、WebDAVClient、SyncService 等服务层
```

## 编译运行

1. 使用 DevEco Studio 打开项目。
2. 确认本机安装 HarmonyOS SDK 6.0.0(20) 或兼容版本。
3. 选择 `entry` 模块并运行到 HarmonyOS 真机或模拟器。
4. 首次进入应用后，在设置页填写 WebDAV 地址、账号、密码与远端目录。

## 同步规则

- 本地新增且远端不存在：上传本地笔记。
- 本地删除且远端存在：比较 `deletedAt` 与远端修改时间，较新的操作胜出。
- 本地与远端都存在：比较 `lastOperationAt` 与远端时间，较新者覆盖较旧者。
- 时间差在 1000ms 以内视为相同，直接跳过。

## 已知限制

- HarmonyOS 当前 `@ohos.net.http` 对 WebDAV 自定义方法支持有限，首版主要依赖标准 HTTP 能力和响应头时间信息。
- 后台每小时同步在不同设备上的系统支持程度可能不同，当前实现默认保证“应用存活期间定时同步 + 回前台补偿同步”。
- 首版 Markdown 预览聚焦基础语法，不包含表格、数学公式和复杂插件语法。
