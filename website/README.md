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
