# TJ Class Schedule：iOS 移植、构建与安装

基于你提供的 0.3.1+13 源码制作；本工程版本为 **0.3.3+18**。

0.3.3+18 已通过 Xcode 27.1 设备编译及 iOS 27.0 模拟器编译，已生成未签名 IPA；498 项 Flutter 测试通过。右上角采用内置扁平图标，底部保留 UIKit 液态玻璃。**尚未完成真机或全机型验收，原生 XCTest 结果见验证记录。**

## 工程中已添加什么

| 功能 | 本工程中的 iOS 实现 | 验收重点 |
| --- | --- | --- |
| 学期、课程、备忘录、单双周与调休 | 复用 Flutter 与 SQLite 逻辑 | 与 Android 数据、日期显示一致 |
| 同济 1 系统课表导入 | 内置 WebView，沿用原解析器 | 学校统一认证、跳转和真实课表 |
| CSV、XLSX、图片识别 | 复用导入流程；iOS 使用 Apple Vision 识别中文/英文，Android 保留 ML Kit 中文模型 | 中文截图识别、文件选择与导入预览 |
| 作业与好课、Canvas、卓越星同步 | 复用原业务逻辑，接入 iOS 后台任务 | 用户自己的平台登录、续期与同步 |
| Canvas 会话维护 | WKWebView + 本机钥匙串，复用 Android 的轮换脚本 | 前台令牌续期、账号切换与中断恢复 |
| 课程和作业通知 | iOS 通知权限、统一排程队列 | 锁屏、静音、专注模式、点击跳转 |
| 下一节课、作业倒计时小组件 | 独立 WidgetKit 扩展，App Group 共享必要展示数据 | 主屏幕和锁屏、跨时刻切换、冷启动跳转 |
| 定位点、距离与方向 | Core Location；只在前台定位会话采样 | 权限拒绝、近似位置、指南针不可用 |
| 本地备份与恢复、外观与背景 | 保留原有 Flutter 流程 | 文件导出、换机、图片裁剪与主题 |

Runner 和组件的设备类别均为 iPhone + iPad；最低部署版本设为 iOS 17，未按机型设置白名单，因此没有人为排除任何 iOS 27 设备。**这属于工程配置，不能代替设备测试。** iPad 还需按 iPadOS 27 验收。

已修复原有的夏令时日期偏移：换周、学期日期、未来提醒和组件的逐日计算使用日历日期，不再把“下一天”简单视为再过 24 小时。

## iOS 上必须知道的行为

- 后台同步使用系统 Background App Refresh。15 分钟是提交给系统的调度提示，不能保证固定间隔；低电量、关闭后台刷新或强制退出可能暂停更新。打开 App 仍可更新。
- WidgetKit 决定组件刷新时机。本工程预生成课程和截止时刻的时间线，使用系统计时文本显示倒计时；Android 的强制每秒刷新选项不在 iOS 中显示。
- 课程、备忘录、锁屏提示和作业共用最近 **60 条**预约通知。更远的候选提醒保存在本机，打开 App 或同步后重新排程；长时间不打开且系统不执行后台更新时，不能保证无限期补排。
- iOS 的震动、静音、专注模式及通知摘要受系统控制。应用不能独立保证“只震动”或强制响铃。“锁屏显示下一节课”在此版本中对应一次无声通知和可选锁屏组件，不等同于 Android 持续通知。
- Canvas 轮换由前台 WKWebView 执行。后台复用最后一次验证过的令牌；需要学校重新登录或前台轮换时，必须再次打开 App 完成恢复。没有宣称网页续期能在 iOS 挂起时持续运行。
- 定位被拒绝时仍可查看本地列表；定位有效但指南针不可用时仍可显示距离。进入后台停止采样，不申请持续后台定位。
- 钥匙串凭据使用“首次解锁后、仅本设备”保护，不加入应用的 JSON 备份。课表等普通本地文件的系统备份由 iOS 设置决定。

## 在 Mac 上构建

准备能够运行 **Xcode 27.1 或更新版本**的 Mac，安装 iOS 27 SDK、Flutter 3.47.7 和 CocoaPods。环境要求以 Apple 与 Flutter 的当前官方文档为准。

在工程根目录执行：

```bash
bash scripts/build_ios.sh
```

脚本依次检查工程配置、获取依赖、执行 Flutter 静态分析和测试、编译设备版本，并把实际编译出的应用及组件打包。iOS 使用系统 Vision 框架，不再下载 Google ML Kit iOS 二进制。

成功后会得到：

```text
dist/TJ-Class-Schedule-iOS-unsigned.ipa
```

这是**未签名**包。普通 iPhone/iPad 安装前仍需要有效签名；文件扩展名为 IPA 并不代表已经可以安装，也不代表能够长期免签名使用。打包脚本在设备应用或组件缺失时会直接失败，不会用源码伪造安装包。

## 配置签名并安装

1. 在 Xcode 的账户设置中加入自己的 Apple 开发者账户，找到对应 Team ID。
2. 使用自己团队拥有的 App ID，例如将下面的占位符换成自己的值：

```bash
python3 scripts/configure_ios.py \
  --team YOURTEAMID \
  --bundle-id com.yourname.tjschedule
```

`YOURTEAMID` 必须替换为实际的 10 位 Team ID。脚本统一修改应用、组件所使用的 Bundle ID、Team 和 App Group 设置；不要使用上游作者的标识进行正式分发。

3. 运行 `flutter pub get`，然后打开 **`ios/Runner.xcworkspace`**。
4. 在 Runner 和 TJWidgets 两个 target 的 Signing & Capabilities 中选择同一团队，确认两者的 App Groups 都包含同一个组，例如 `group.com.yourname.tjschedule`。组必须在团队中正确注册并授权。
5. 选择自己的设备，运行 Runner。按 iOS 提示开启开发者模式及必要权限。
6. 正式分发时在 Xcode 中选择 Product → Archive，并按开发者账户实际支持的方式导出或通过 TestFlight 分发。

App Groups 等能力取决于开发者账户与签名配置。如果所用签名方式不保留主应用和组件的共同 App Group 权限，**小组件不能完整工作**；不能仅给主程序重签名就认定完成全部移植。

## 没有 Mac 时通过 GitHub 构建

工程内已添加 `.github/workflows/ios.yml`：

1. 将解压后的工程内容放入自己的 GitHub 仓库根目录，保留 `.github`、`ios`、`packages` 等文件夹。
2. 在 Actions 中选择“iOS 编译与验证”，点击 Run workflow。
3. 流程使用 `xcode-27` 托管构建机并选取已安装的 Xcode 27.1+，执行检查、编译设备包及模拟器版本，再在该构建机上一个 iOS 27 iPhone 和一个 iPad 模拟器（设置 `IOS_TEST_ALL=1` 可检查所有已安装机型）运行原生测试。
4. 流程成功后下载 `TJ-Class-Schedule-iOS-unsigned` 构建产物。

如果托管构建机尚未安装所需 Xcode 或 iOS 27 模拟器，流程会明确失败，需更新构建环境或使用自己的 Mac。没有将“工作流已写好”当作“工作流已经成功执行”。本项目的移植代码和构建记录见 [PR #1](https://github.com/QwertyMi233/TJ-Class-Schedule-iOS/pull/1)。

## 如何验收“所有 iOS 27 设备”

先在 Mac 上完成设备编译和原生测试：

```bash
python3 scripts/test_ios_simulators.py
```

脚本记录构建机实际安装且可用的 iOS 27 模拟器及每台结果，输出至 `dist/ios-tests/`。模拟器集合并不等于 Apple 全部支持的真实硬件，也不验证真实定位、耗电、学校登录或通知可靠性。

发布前至少补齐以下记录，并逐项登记机型、系统小版本和通过日期：

- 最小和最大 iPhone 屏幕；横竖屏；如有可变屏幕形态，覆盖各可用布局状态。
- iPad 小屏、大屏，以及分屏和窗口尺寸变化。
- 真实学校账号的统一认证、Canvas、好课和卓越星；令牌失效、换账号与断网恢复。
- 中文课表截图与备份导入导出；合并、替换和撤销。
- 通知权限拒绝后恢复、后台刷新关闭、低电量、强制退出、重启、静音与专注模式。
- 两种组件的各支持尺寸、跨上课/截止时刻切换、作业点击冷启动和热启动。
- 定位拒绝、近似位置、设备没有可用方向数据，以及退出定位页后不继续采样。
- 至少一个夏令时地区、跨月与跨年、系统时区变化。

在这些记录完成前，适当的状态是“iOS 移植已编译，待签名后真机验收”，不应标为“已保证全机型正常”。

## 相关官方资料

- [Apple：Xcode 系统和 SDK 要求](https://developer.apple.com/xcode/system-requirements/)
- [Apple：在模拟器和设备上运行应用](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [Apple：配置 App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Apple：保持 WidgetKit 组件更新](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Flutter：iOS 开发环境](https://docs.flutter.dev/platform-integration/ios/setup)
- [Workmanager：iOS 设置](https://docs.page/fluttercommunity/flutter_workmanager/quickstart)
- [通知插件：iOS 容量及配置限制](https://pub.dev/packages/flutter_local_notifications)
- [Apple Vision：图片文字识别](https://developer.apple.com/documentation/vision/recognizing-text-in-images)


## 0.3.2 的 iOS 界面与小组件修复

- 0.3.2 曾使用 UIKit 导航栏和菜单；0.3.3 将导航操作改为内置扁平图标，底部胶囊操作继续使用真实 UIKit 控件。iOS 26+ 的按钮采用系统 `glass()`，由系统处理深浅色、交互与降低透明度；不在内容卡片上堆叠玻璃。
- 表单、日期/时间选择、确认弹窗和分段切换使用 Cupertino。iOS 正文采用 Cupertino 系统字体来源，中文由系统回退到相应字体，并跟随系统文字大小。
- 课程与作业分别写入 App Group 内的原子 JSON 快照，组件每次读取文件，避免进程间偏好设置缓存；旧版偏好数据保留作迁移回退。外观更新同时重载两个组件。
- 如果签名工具改了共享组名称，只使用主应用和扩展描述文件共同授权、且 iOS 允许访问的容器。不能通过代码补发签名权限。

如果仍显示“打开 App 后更新课表”：

1. 打开 App 右上角菜单 → **小组件同步** → **立即同步课表与作业**，查看数据条数和写入时间。
2. 若显示“共享权限未授权”，重新签名时同时保留主应用和 `TJWidgets.appex`，给两者配置同一个有效 App Group。证书和描述文件也必须授权该组；仅修改 Info.plist 或重新打开 App 无效。
3. 若共享连接、写入时间和条数均正常，先等待系统刷新；必要时移除桌面上的小组件并重新添加。不要为此删除应用或课表数据。
4. 小组件内容更新和后台同步由 iOS 调度，不能承诺固定秒级刷新。倒计时文本则由系统绘制。


## 0.3.3 的图标与按键比例

- 右上角操作使用随 App 打包的 Cupertino 图标字体，离线可用。没有匹配的图标保留其原始图形，不再变成“更多”。
- 导航栏操作使用扁平图标，不加独立玻璃底座；只有真正的更多菜单显示省略号。底部主要操作继续使用系统液态玻璃。
- 同济 1 导入页分别提供电脑/手机模式切换、重新加载、退出登录三个图标；退出前确认，不删除已导入的课表。
- 工具栏默认图标 20 点、点击区域至少 44×44 点；底部胶囊按钮默认文字 16 点、图标 20 点、高度 48 点，大字体下按内容增高。
- 新增六种屏幕尺寸、深浅色和大字体布局回归，检查三个功能的点击回调及按键边界；本版 498 项完整回归通过，结果见构建记录。
