# 自定义背景修复测试包

日期：2026-10-18。保持 `pubspec.yaml` 的 **0.3.0+12**，arm64 APK 的 versionName 为 **0.3.0**、versionCode 为 **2012**。只生成本地测试安装包，不创建 GitHub Release、不更新官网或版本号。

## 参考来源

- 项目：[leo802001/HITable](https://github.com/leo802001/HITable)。
- 固定提交：`dc2e4be897c484b7768137134db41896d5c1f6f3`。
- 主要参考：[lib/presentation/app_background.dart](https://github.com/leo802001/HITable/blob/dc2e4be897c484b7768137134db41896d5c1f6f3/lib/presentation/app_background.dart)，同时查看其主页卡片分层。
- 采用主题底色 → 图片 → 随深浅模式变化的蒙层 → 清晰前景这一结构；图片独立模糊、裁切边缘并略微放大。未引入原项目的账号、导入或其他业务。
- `Copyright (c) 2026 Leocy` 及完整 MIT 许可保留在 `assets/LICENSE_HITable.txt`，已加入 Flutter assets 随 APK 分发。

## 修复内容

1. 浅色模式用浅色蒙层，深色模式用暗色蒙层；新增「背景柔化」0–20 调节，默认 6、设为 0 保留原图。文字和按钮不经过模糊。
2. 图片验证与预解码集中处理，损坏或丢失图片时恢复完整纯色界面；限制背景解码尺寸为 1440×2560 内，避免每张卡片反复查询磁盘。
3. 每次换图写入独立文件并原子提交，避免旧缓存不刷新。数据库保存失败时保留旧图和旧设置，只清理未提交的新图；成功后回收旧图。
4. 今日、本周与整周网格使用一致的背景和卡片透明度。修复整周页实色底遮住背景；原有缩放、拖动和点击逻辑保留。
5. 裁剪框按实际剩余空间保持屏幕比例，确认时使用真实取景尺寸；横屏和大字体下缩放课表示意，避免溢出。模糊与蒙层不烧进原始图片，便于以后调节。
6. 底部署名单独预留空间，避免悬浮按钮遮挡；背景留在固定底层，不随日期切换动画晃动。

## 验证与产物

针对换图、保存失败、损坏图、移除图、透明度、深浅模式、整周导航、小屏/横屏大字体裁剪增加回归检查；真实组件渲染图见 `artifacts/preview-background-*.png`（使用程序绘制的测试图，未使用用户照片）。

构建命令：`tools/build-local.ps1`，参数 `-ArtifactSuffix '-background-test'`。脚本执行离线依赖解析、静态检查、全量 Flutter 测试、Android 单元测试和 arm64 Release 构建。最终结果记录在 `artifacts/verification-background-test.json`。

安装包：`artifacts/TJ-Class-Schedule-v0.3.0-background-test-arm64.apk`。原来的 `TJ-Class-Schedule-v0.3.0-arm64.apk` 保留。测试包沿用原包名、版本和签名，可用于覆盖安装测试。

最终验证：静态检查无问题；387 项 Flutter 测试、9 项 Canvas 脚本回归、5 项 Android 单元测试通过。arm64 Release 构建成功，权限未增加，签名与旧包一致，133 个源文件/测试/依赖包/资源及版本文件与构建暂存区一致；APK 内 MIT 许可、Canvas 和作业脚本与源文件一致。安装包 36,155,354 字节，SHA256 为 `1e9f62ca109ea07a4ad7dff00d8454023363be2eed5706bb133def200cf39bf3`。交付副本已核对相同哈希。

尚未在实体 Android 手机上验证相册选图、不同厂商系统栏和长时间滑动表现。建议手机上分别试亮图/暗图、连续换两张图、切换深浅模式、整周缩放、横屏裁剪和移除背景。
