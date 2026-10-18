# 部署说明

当前官网使用 Vite + React + TypeScript 与 shadcn/ui。源码不能直接双击 `index.html` 预览；日常预览运行 `npm run dev`，正式托管使用 `npm run build` 生成的 `dist/`。

## 已上线

- 公开地址：<https://tjschedule.icu/>
- Cloudflare Pages 项目：`tj-class-schedule`，生产分支：`master`
- 下载次数使用 D1 数据库 `tj-class-schedule-count`，绑定名 `DB`；配置见 `wrangler.jsonc`。
- 更新网站：运行 `npm run build`，再运行 `npx wrangler pages deploy dist --project-name tj-class-schedule --branch master`。需先用 `npx wrangler login` 登录有 Pages 部署权限的账号。

## 本机预览与打包

```powershell
npm ci
npm run dev
```

打开命令输出的本机地址。确认页面后执行：

```powershell
npm run build
```

`dist/` 已包含页面、优化后的图标、原有六张截图、新增的寻物界面示例、群二维码和 release APK 压缩包。下载按钮会提供 ZIP，访客解压后安装其中的 APK。下载 ZIP 不提交到 Git，新克隆源码需先按 README 下载当前 Release 包放入 `public/downloads/`。共享下载次数由根目录 `functions/` 中的接口与 Cloudflare D1 保存；部署步骤见 [COUNTING.md](COUNTING.md)。

## 静态托管

| 平台 | 设置 |
| --- | --- |
| [Cloudflare Pages](https://developers.cloudflare.com/pages/) | 推荐。连接源码仓库或用 Wrangler 部署；构建命令 `npm run build`，输出目录 `dist`，并按 `COUNTING.md` 绑定 D1，下载次数才会生效。 |
| [GitHub Pages](https://docs.github.com/en/pages) | 可发布 `dist/` 静态页面；没有对应的 Pages Function，下载次数显示「暂不可用」。 |
| [Netlify](https://docs.netlify.com/) | 可发布 `dist/` 静态页面；没有对应的 Pages Function，下载次数显示「暂不可用」。 |

这是单页网站，没有客户端路由，以上平台不需要额外的回退规则。未使用第三方统计脚本或远程字体。只保存下载按钮的汇总点击次数。

## 上线前

1. 拿到域名后，按 [DOMAIN_DISCOVERY.md](DOMAIN_DISCOVERY.md) 设置自定义域名、分享卡片和搜索站点地图。
2. 上线后实际打开首页、轮播、群二维码、安装说明、下载链接和页脚计数；在手机和桌面浏览器各检查一次。

之前的纯 HTML 页面保存在 `legacy/index-previous.html`，上次的独立 HTML 文件仍是旧设计。Android 安装包构建记录在 [RELEASE.md](RELEASE.md)。
