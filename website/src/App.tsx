import { useEffect, useRef, useState } from "react"
import {
  ArrowDown,
  ArrowRight,
  ArrowUpRight,
  Check,
  Copy,
  Download,
  GitBranch,
  Menu,
} from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  Carousel,
  CarouselContent,
  CarouselItem,
  CarouselNext,
  CarouselPrevious,
  type CarouselApi,
} from "@/components/ui/carousel"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion"
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet"

const github = "https://github.com/qp338113/TJ-Class-Schedule"
const download = "/downloads/TJ-Class-Schedule-v0.3.0-arm64-v8a.zip"
const counterEndpoint = "/api/download-count"

function readCount(value: unknown): number | null {
  if (!value || typeof value !== "object" || !("count" in value)) return null
  const count = value.count
  return typeof count === "number" && Number.isSafeInteger(count) && count >= 0 ? count : null
}

const slides = [
  { title: "本周课表", line: "今天与本周的课程，打开就能看。", src: "/assets/screenshots/main.webp", alt: "TJ Class Schedule 本周课表真实界面", width: 720, height: 1610 },
  { title: "定位寻物", line: "先保存位置，再跟着距离和方向找回去。", src: "/assets/screenshots/finder.webp", alt: "定位寻物应用界面，使用示例定位点展示直线距离和方向", width: 780, height: 1688 },
  { title: "导入课程", line: "登录同济 1 系统，直接读取课表。", src: "/assets/screenshots/import.webp", alt: "在 App 内打开同济统一认证的真实界面", width: 720, height: 1610 },
  { title: "桌面小组件", line: "下一节课、地点与倒计时，放在桌面。", src: "/assets/screenshots/widget.webp", alt: "显示下一节课的桌面小组件真实截图", width: 720, height: 1610 },
  { title: "调休补课", line: "选好要补哪一天，课表随之切换。", src: "/assets/screenshots/makeup.webp", alt: "调休补课提示与当天课程的真实界面", width: 720, height: 1610 },
  { title: "整周课表", line: "整学期的课程，放进一屏网格。", src: "/assets/screenshots/semester.webp", alt: "按星期和节次排列的整周课表真实截图", width: 1100, height: 1139 },
  { title: "外观设置", line: "主题色、小组件颜色和背景图可以自己调。", src: "/assets/screenshots/appearance.webp", alt: "外观设置真实界面", width: 720, height: 1610 },
] as const

const questions = [
  { question: "为什么只支持 64 位？", answer: "当前安装包仅支持 64 位 ARM 设备（arm64-v8a）；32 位老机型装不上或闪退。" },
  { question: "提示签名冲突怎么办？", answer: "请先覆盖安装以保留数据。若提示签名冲突，请先备份课表并联系反馈群；不要直接卸载或清除数据。当前安装包沿用前几次本地更新包的测试签名。" },
  { question: "小组件不动怎么办？", answer: "安装后先打开 App 一次；如果仍看不到变化，把小组件从桌面删掉重新添加。" },
  { question: "会上传我的课表吗？", answer: "课表、作业、学期和设置保存在手机；平台凭证由系统安全存储保存。读取课表、检查调休或连接 Canvas、好课时会访问对应平台，开启自动同步后也会在后台访问。数据和凭证不会上传到开发者服务器。" },
  { question: "为什么调休要自己选补哪一天？", answer: "国家调休通知只说明哪天上班，不含学校具体补课安排；学校校历以图片发布无法自动读取。因此需要手动选一个日期，App 会对应教学周与星期。" },
] as const

function App() {
  const [carouselApi, setCarouselApi] = useState<CarouselApi>()
  const [selectedSlide, setSelectedSlide] = useState(0)
  const [qrOpen, setQrOpen] = useState(false)
  const [copyMessage, setCopyMessage] = useState("")
  const [downloadBusy, setDownloadBusy] = useState(false)
  const [downloadCount, setDownloadCount] = useState<number | null>(null)
  const [counterStatus, setCounterStatus] = useState<"loading" | "ready" | "unavailable">("loading")
  const groupRef = useRef<HTMLSpanElement>(null)

  useEffect(() => {
    if (!carouselApi) return
    const update = () => setSelectedSlide(carouselApi.selectedScrollSnap())
    update()
    carouselApi.on("select", update)
    carouselApi.on("reInit", update)
    return () => {
      carouselApi.off("select", update)
      carouselApi.off("reInit", update)
    }
  }, [carouselApi])

  useEffect(() => {
    if (!("IntersectionObserver" in window) || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
    const sections = [...document.querySelectorAll<HTMLElement>("[data-reveal]")]
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue
        entry.target.classList.add("is-visible")
        observer.unobserve(entry.target)
      }
    }, { threshold: 0.08, rootMargin: "0px 0px -5% 0px" })
    sections.forEach((section) => {
      section.classList.add("reveal-ready")
      observer.observe(section)
    })
    return () => {
      observer.disconnect()
      sections.forEach((section) => section.classList.remove("reveal-ready"))
    }
  }, [])

  useEffect(() => {
    const controller = new AbortController()
    fetch(counterEndpoint, { cache: "no-store", signal: controller.signal })
      .then(async (response) => {
        if (!response.ok) throw new Error("统计暂不可用")
        const count = readCount(await response.json())
        if (count === null) throw new Error("统计数据无效")
        setDownloadCount((previous) => Math.max(previous ?? 0, count))
        setCounterStatus("ready")
      })
      .catch(() => {
        if (!controller.signal.aborted) setCounterStatus("unavailable")
      })
    return () => controller.abort()
  }, [])

  async function startDownload() {
    if (downloadBusy) return
    setDownloadBusy(true)
    const link = document.createElement("a")
    link.href = download
    link.download = "TJ-Class-Schedule-arm64-v8a.zip"
    document.body.appendChild(link)
    link.click()
    link.remove()

    const controller = new AbortController()
    const timeout = window.setTimeout(() => controller.abort(), 2500)
    try {
      const response = await fetch(counterEndpoint, {
        method: "POST",
        cache: "no-store",
        credentials: "same-origin",
        keepalive: true,
        signal: controller.signal,
      })
      if (!response.ok) throw new Error("统计暂不可用")
      const count = readCount(await response.json())
      if (count === null) throw new Error("统计数据无效")
      setDownloadCount((previous) => Math.max(previous ?? 0, count))
      setCounterStatus("ready")
    } catch {
      setCounterStatus((previous) => previous === "ready" ? previous : "unavailable")
    } finally {
      window.clearTimeout(timeout)
      setDownloadBusy(false)
    }
  }

  async function copyGroup() {
    try {
      if (!navigator.clipboard?.writeText) throw new Error("剪贴板不可用")
      await navigator.clipboard.writeText("1103397369")
      setCopyMessage("已复制")
    } catch {
      if (groupRef.current) {
        const range = document.createRange()
        range.selectNodeContents(groupRef.current)
        const selection = window.getSelection()
        selection?.removeAllRanges()
        selection?.addRange(range)
      }
      setCopyMessage("已选中群号，请手动复制")
    }
  }

  return (
    <>
      <a className="skip-link" href="#main">跳到主要内容</a>
      <header className="site-header">
        <nav className="nav-shell" aria-label="主导航">
          <a className="brand" href="#top" aria-label="TJ Class Schedule，返回顶部">
            <img src="/assets/icon/app-icon-64.webp" alt="" width="32" height="32" />
            <span>TJ Class Schedule</span>
          </a>
          <div className="desktop-nav">
            <a href="#features">功能</a>
            <a href="#privacy">隐私</a>
            <a href="#install">下载</a>
            <a href="#community">交流群</a>
          </div>
          <Button type="button" size="sm" className="nav-download" onClick={startDownload} disabled={downloadBusy} aria-busy={downloadBusy}>
            {downloadBusy ? "已开始下载" : "获取安装包"} <ArrowUpRight aria-hidden="true" />
          </Button>
          <Sheet>
            <SheetTrigger asChild>
              <Button className="mobile-menu" variant="outline" size="icon" aria-label="打开菜单"><Menu aria-hidden="true" /></Button>
            </SheetTrigger>
            <SheetContent side="right" className="mobile-sheet">
              <SheetHeader><SheetTitle>TJ Class Schedule</SheetTitle></SheetHeader>
              <div className="mobile-links">
                <SheetClose asChild><a href="#features">功能</a></SheetClose>
                <SheetClose asChild><a href="#privacy">隐私</a></SheetClose>
                <SheetClose asChild><a href="#install">下载</a></SheetClose>
                <SheetClose asChild><a href="#community">交流群</a></SheetClose>
              </div>
            </SheetContent>
          </Sheet>
        </nav>
      </header>

      <main id="main">
        <section className="hero page-width" id="top" aria-labelledby="hero-title">
          <span className="eyebrow">TJ CLASS SCHEDULE · ANDROID</span>
          <h1 id="hero-title">课表留在手机里</h1>
          <p className="hero-description">为同济学生做的离线优先课表与作业 App。</p>
            <p className="hero-release">0.3.0 · 新增定位寻物</p>
          <div className="hero-actions">
            <Button type="button" size="lg" onClick={startDownload} disabled={downloadBusy} aria-busy={downloadBusy}>{downloadBusy ? "已开始下载" : "获取安装包"} <Download aria-hidden="true" /></Button>
            <Button asChild variant="outline" size="lg"><a href="#community">加入交流群 <ArrowRight aria-hidden="true" /></a></Button>
          </div>
          <a href="#features" className="hero-next">看看界面 <ArrowDown aria-hidden="true" size={15} /></a>
          <div className="hero-gallery" aria-label="应用真实界面预览">
            <img className="hero-phone hero-phone-left" src="/assets/screenshots/import.webp" alt="导入课程界面" width="720" height="1610" loading="lazy" />
            <img className="hero-phone hero-phone-main" src="/assets/screenshots/main.webp" alt="本周课表界面" width="720" height="1610" fetchPriority="high" />
            <img className="hero-phone hero-phone-right" src="/assets/screenshots/finder.webp" alt="定位寻物界面，示例定位点" width="780" height="1688" loading="lazy" />
            <span className="hero-preview-note">定位寻物使用示例位置展示</span>
          </div>
        </section>

        <section className="privacy-section" id="privacy" aria-labelledby="privacy-title">
          <div className="page-width section-center reveal-section" data-reveal>
            <span className="eyebrow">数据与隐私</span>
            <h2 id="privacy-title">自己的课表，留在自己的手机</h2>
            <p className="section-line">没有账号、没有广告、没有云同步。</p>
            <Dialog>
              <DialogTrigger asChild><Button variant="outline" className="text-link-button">查看隐私说明 <ArrowUpRight aria-hidden="true" /></Button></DialogTrigger>
              <DialogContent className="info-dialog">
                <DialogHeader>
                  <DialogTitle>数据与联网</DialogTitle>
                  <DialogDescription>数据在自己手机里。</DialogDescription>
                </DialogHeader>
                <p>无需注册开发者账号，没有广告、统计 SDK 或云同步。课表、作业、定位点和设置保存在手机，平台凭证由系统安全存储保存。位置只在保存和寻找时使用，退出或切到后台后停止。</p>
                <p>读取课表、检查调休、登录并同步 Canvas 或好课时访问对应平台。开启自动同步后，也会约每半小时在后台访问。数据和凭证不会上传到开发者服务器。</p>
                <a className="dialog-link" href={github} target="_blank" rel="noopener noreferrer">MIT 协议，代码公开可查 <ArrowUpRight aria-hidden="true" size={16} /></a>
              </DialogContent>
            </Dialog>
          </div>
        </section>

        <section className="features-section page-width reveal-section" id="features" aria-labelledby="features-title" data-reveal>
          <div className="section-center">
            <span className="eyebrow">真实界面</span>
            <h2 id="features-title">看看它怎么用</h2>
          </div>
          <Carousel className="feature-carousel" opts={{ align: "center", loop: false }} setApi={setCarouselApi} aria-label="功能截图轮播">
            <CarouselContent className="feature-track">
              {slides.map((slide, index) => (
                <CarouselItem className="feature-slide" key={slide.title} data-active={selectedSlide === index}>
                  <figure>
                    <div className="feature-image-stage">
                      <img src={slide.src} alt={slide.alt} width={slide.width} height={slide.height} loading="lazy" />
                    </div>
                    <figcaption>
                      <h3>{slide.title}</h3>
                      <p>{slide.line}</p>
                    </figcaption>
                  </figure>
                </CarouselItem>
              ))}
            </CarouselContent>
            <div className="carousel-controls">
              <div className="slide-count"><strong>{String(selectedSlide + 1).padStart(2, "0")}</strong><span> / {String(slides.length).padStart(2, "0")}</span></div>
              <div className="carousel-arrows">
                <CarouselPrevious className="carousel-arrow" aria-label="上一张截图" />
                <CarouselNext className="carousel-arrow" aria-label="下一张截图" />
              </div>
            </div>
          </Carousel>
        </section>

        <section className="install-section" id="install" aria-labelledby="install-title">
          <div className="page-width section-center reveal-section" data-reveal>
            <span className="eyebrow">开始使用</span>
            <h2 id="install-title">下载到 Android 手机</h2>
            <p className="section-line">版本 0.3.0 · Android 8.0 及以上 · 64 位 ARM。</p>
            <Dialog>
              <DialogTrigger asChild><Button variant="link" className="faq-link">查看新版更新说明</Button></DialogTrigger>
              <DialogContent className="info-dialog">
                <DialogHeader><DialogTitle>0.3.0 · 定位寻物与使用体验改进</DialogTitle><DialogDescription>2026 年 10 月 18 日更新</DialogDescription></DialogHeader>
                <ul className="info-list">
                  <li>课表右上角打开定位，保存多个位置，寻找时查看直线距离和动态方向。</li>
                  <li>改善背景图与课表的融合，新增背景柔化，修复换图和裁剪问题。</li>
                  <li>一次性备忘录只填开始时间即可，结束时刻可选。</li>
                  <li>支持 Canvas 自动续期和好课定期登录；好课临时网络失败后有限补试。</li>
                  <li>减少同步弹窗，简化错误提示，恢复后清除对应提示。</li>
                </ul>
                <p>396 项 Flutter 测试、5 项 Android 测试及构建检查通过。熄屏同步仍受手机省电设置影响，尚未在全部机型验证。</p>
                <a className="dialog-link" href="/updates/v0.3.0.txt" target="_blank" rel="noopener noreferrer">阅读完整更新公告</a>
              </DialogContent>
            </Dialog>
            <div className="section-actions">
              <Button type="button" size="lg" onClick={startDownload} disabled={downloadBusy} aria-busy={downloadBusy}>{downloadBusy ? "已开始下载" : "获取安装包"} <Download aria-hidden="true" /></Button>
              <Dialog>
                <DialogTrigger asChild><Button variant="outline" size="lg">安装须知 <ArrowUpRight aria-hidden="true" /></Button></DialogTrigger>
                <DialogContent className="info-dialog">
                  <DialogHeader><DialogTitle>安装须知</DialogTitle><DialogDescription>安装前先确认设备和签名。</DialogDescription></DialogHeader>
                  <ul className="info-list">
                    <li>适配 Android 8.0 及以上。</li>
                    <li>安装包仅支持 64 位 ARM 设备（arm64-v8a）；32 位老机型装不上或闪退。</li>
                    <li>请先覆盖安装保留数据。若提示签名冲突，请先备份并联系反馈群，不要直接卸载或清除数据。</li>
                    <li>安装后请打开 App 一次，桌面小组件才会同步数据。</li>
                    <li>小组件如果看不到变化，把它从桌面删掉重新添加。</li>
                  </ul>
                  <p className="dialog-note">下载得到 ZIP 压缩包，解压后安装其中的 APK。</p>
                </DialogContent>
              </Dialog>
            </div>
            <Dialog>
              <DialogTrigger asChild><Button variant="link" className="faq-link">常见问题 <ArrowRight aria-hidden="true" /></Button></DialogTrigger>
              <DialogContent className="info-dialog faq-dialog">
                <DialogHeader><DialogTitle>常见问题</DialogTitle><DialogDescription>安装与使用时可能遇到的问题。</DialogDescription></DialogHeader>
                <Accordion type="single" collapsible>
                  {questions.map((item, index) => (
                    <AccordionItem value={`item-${index}`} key={item.question}>
                      <AccordionTrigger>{item.question}</AccordionTrigger>
                      <AccordionContent>{item.answer}</AccordionContent>
                    </AccordionItem>
                  ))}
                </Accordion>
              </DialogContent>
            </Dialog>
          </div>
        </section>

        <section className="community-section page-width" id="community" aria-labelledby="community-title">
          <div className="section-center reveal-section" data-reveal>
            <span className="eyebrow">交流群</span>
            <h2 id="community-title">欢迎来群里反馈</h2>
            <p className="section-line">获取新版本、反馈问题、提功能建议。</p>
            <div className="group-number" aria-label="QQ 群号 1103397369">
              <span ref={groupRef}>1103397369</span>
              <Button variant="outline" size="sm" onClick={copyGroup}>{copyMessage === "已复制" ? <Check aria-hidden="true" /> : <Copy aria-hidden="true" />}复制群号</Button>
            </div>
            <p className="copy-message" role="status" aria-live="polite">{copyMessage}</p>
            <Dialog open={qrOpen} onOpenChange={setQrOpen}>
              <DialogTrigger asChild><Button variant="link" className="faq-link">查看群二维码 <ArrowUpRight aria-hidden="true" /></Button></DialogTrigger>
              <DialogContent className="qr-dialog">
                <DialogHeader><DialogTitle>扫码加入交流群</DialogTitle><DialogDescription>QQ 群：1103397369</DialogDescription></DialogHeader>
                {qrOpen && <img src="/assets/qr/qq-group.webp" alt="QQ群 1103397369 的入群二维码" width="965" height="965" loading="lazy" />}
              </DialogContent>
            </Dialog>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <div className="page-width footer-main">
          <div className="footer-brand">
            <img src="/assets/icon/app-icon-64.webp" alt="" width="30" height="30" loading="lazy" />
            <span>TJ Class Schedule</span>
          </div>
          <div className="footer-links">
            <a href={github} target="_blank" rel="noopener noreferrer"><GitBranch aria-hidden="true" size={15} /> GitHub</a>
            <span>MIT</span>
            <span>作者：Algernon</span>
            <span>QQ群：1103397369</span>
            <span>作者 QQ：22725876</span>
            <span>微信：LJ-QWQ1144</span>
          </div>
          <p className="footer-disclaimer">本应用为非同济官方应用，不代表学校提供服务，不代学校发布信息。课程与考试安排请以学校教务通知及实际教学安排为准。</p>
          <p className="footer-meta">版本 0.3.0+12 · 更新日期 2026/10/18</p>
          <p className="footer-download-count" role="status" aria-live="polite">
            <span>网站下载次数</span>
            <strong>{counterStatus === "ready" ? downloadCount?.toLocaleString("zh-CN") : counterStatus === "loading" ? "读取中…" : "暂不可用"}</strong>
          </p>
        </div>
      </footer>
    </>
  )
}

export default App
