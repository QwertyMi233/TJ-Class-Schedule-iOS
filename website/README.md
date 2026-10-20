# TJ Class Schedule 官网

使用 React、Vite、TypeScript、Tailwind CSS、shadcn/ui 和 lucide-react 的单页官网。页面使用用户提供的真实应用截图与 QQ 群二维码。

```powershell
npm ci
npm run dev
```

生产构建：

```powershell
npm run build
```

输出在 `dist/`。页面布局、组件和短文案约束见 [SITE_SPEC.md](SITE_SPEC.md)；托管步骤见 [DEPLOY.md](DEPLOY.md)。共享下载次数需要 Cloudflare Pages Function 与 D1，配置见 [COUNTING.md](COUNTING.md)；本地 Vite 预览会显示「暂不可用」。

旧版 HTML 保存在 `legacy/index-previous.html`；`TJ-Class-Schedule-standalone.html` 是旧版的独立预览文件，不属于当前 React 版。

0.3.0 首页和轮播新增定位寻物展示，图片由实际 App 页面渲染，使用示例定位点。官网源码同时保存在应用仓库的 `website/` 目录。

当前官网下载版本为 `0.3.1+13`，新增好课密码恢复与卓越星活动同步。Git 仓库不保存下载用的二进制 ZIP。重新部署前，请下载[官网 0.3.1 安装包](https://tjschedule.icu/downloads/TJ-Class-Schedule-v0.3.1-arm64-v8a.zip)，放入 `public/downloads/`；再复制一份命名为 `TJ-Class-Schedule-arm64-v8a.zip`，供旧下载入口使用。APK 的 SHA256 为 `80c5566100d6a1a135a3842dab911e6a6a2090ede9c72f2d8e965ad416e9f2ed`。
