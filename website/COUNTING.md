# 网站下载次数

当前线上网站为 <https://tjschedule.icu/>，Pages 项目已绑定 D1 数据库 `tj-class-schedule-count`，绑定名为 `DB`。数据库初始化脚本已执行，计数从 0 开始。以下步骤保留给重新建站或迁移时使用。

页面底部的「网站下载次数」统计的是**从本网站下载按钮发起的次数**，从数据库启用时的 0 开始。它不代表独立用户数、安装人数，也无法确认浏览器是否完成了下载。直接访问压缩包网址不会增加次数。

实现使用 Cloudflare Pages Function 和 D1，只保存一个汇总整数。没有统计 SDK、Cookie、账号或访客标识。三个下载按钮共用同一个计数入口；数据库未配置或暂时出错时，安装包仍可下载，页面显示「暂不可用」，不会编造数字。

## 在 Cloudflare Pages 启用

1. 注册或登录 Cloudflare，准备一个 Pages 项目。把本项目源码通过 Git 连接到 Pages，构建命令填 `npm run build`，输出目录填 `dist`；或者在项目根目录运行 `npx wrangler pages deploy dist --project-name=<你的 Pages 项目名>`。`functions/api/download-count.js` 必须与源码一起部署。
2. 在 Cloudflare 创建一个 D1 数据库，例如 `tj-class-schedule-count`。在项目根目录执行：

   ```powershell
   npx wrangler d1 execute tj-class-schedule-count --remote --file=migrations/0001_download_counter.sql
   ```

3. 把新数据库的 ID 写入 `wrangler.jsonc` 的 `d1_databases[0].database_id`，绑定名保持 `DB`，再部署网站。
4. 打开 `https://你的站点/api/download-count`，应得到 `{"count":0}` 或已有的累计数字。点击一次网页上的下载按钮，再刷新此接口，数字应增加 1；页面最下端也会显示新数字。

Cloudflare Pages 的控制台拖拽上传只会发布静态文件，**不会编译本项目的 `functions/`**。请使用 Git 连接或 Wrangler 部署。只有 `dist/` 的压缩包可预览页面和下载安装包，但不会启用共享计数。

本地 `npm run dev` 没有 D1 绑定，所以页脚显示「暂不可用」，下载仍可正常开始。运行 `npm test` 可检查计数接口的读数、递增和跨站请求拒绝逻辑。
