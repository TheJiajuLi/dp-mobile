# 极梦 DreamingPolar — 项目完整上下文
更新时间：2026年7月15日

---

## 名字与品牌

**极梦**为什么叫极梦：
- 极 — 极致、极地、极限
- 梦 — 梦想、梦境、Dreaming
- 英文名 Dreaming Polar：Dreaming=梦想中/创造中，Polar=极地/极点
- Logo：紫色 #6366F1 圆角方块 + 白色「极」字
- Slogan：**极梦，为创造而生**

**产品定位**：知乎的深度 + 小红书的轻量 + Nature的专业质感
覆盖领域：科学 / 经济 / 时事 / 生活 / 数据 / 编程 / 宇宙 / 生命科学

---

## 基础信息

| 项目 | 极梦 DreamingPolar |
|------|-------------------|
| 公司 | 上海既白观海科技有限公司（办理中） |
| 域名 | dreamingpolar.com |
| 品牌色 | #6366F1 |
| 深色背景 | #0A0A0F（AppColors.darkBg，见下方深色系统） |
| 浅色背景 | #FAFAF8（米白，2026-07中旬起全局改用，见下方"颜色规范"更新说明） |
| Apple账号 | 个人账号，审核中 |
| 企业邮箱 | 腾讯企业邮箱，dreamingpolar.com |
| 账号 | lijiaju@ / contact@ / creator@ / support@ |

---

## 技术栈

### 移动端
- Flutter 3.x + Dart（目标：iOS App Store + Android）
- 两个仓库：`dp-flutter`（Flutter 1，维护/重构）/ `dp-flutter-2`（Flutter 2，新功能）
- 状态管理：Riverpod（currentUserProvider 存登录用户）
- 路由：GoRouter
- 网络：ApiClient（封装 Dio，自动注入 Bearer token，返回 ApiResponse 不抛异常）
- 本地存储：flutter_secure_storage + shared_preferences
- 图片：cached_network_image + flutter_svg
- LaTeX：flutter_math_fork
- WebView（Notebook运行Python）：flutter_inappwebview

### 后端
- Node.js + TypeScript + Express
- 服务器：150.109.77.250，端口 3001，后端路径：/root/dp-auth-backend
- PM2服务：dp-auth
- 数据库：MySQL，内网 10.5.0.6:3306，库名 dp_users
- 对象存储：腾讯云 COS，ap-hongkong，Bucket: dp-1317483118
- COS URL: https://dp-1317483118.cos.ap-hongkong.myqcloud.com/${cosKey}

### 部署命令
```bash
cd /root/dp-auth-backend && git pull && npm run build && pm2 restart dp-auth && echo "Done"
```

---

## 设计语言（必读）

### 颜色规范
- 浅色背景：**`#FAFAF8`（米白）— 全局统一**，2026-07中旬起大规模替换了原来的
  `AppColors.bg`（冷灰白`#F7F7FB`）。首页最早用的就是`#FAFAF8`，后来陆续把
  消息页/极索/Notebook/发布页/群聊/设置类页面等全部对齐成同一个米白，
  不再用`#F7F7FB`或纯白`#FFFFFF`当页面背景。新页面直接用`#FAFAF8`（浅色）/
  `Theme.of(context).scaffoldBackgroundColor`或`AppColors.darkBg`（深色），
  不要再引用旧的`AppColors.bg`
- 主文字：#1A1A1A，次要：#999，辅助：#6366F1
- 无阴影，无渐变，用 0.5px #F0F0F0 细线分区
- 卡片：白色 #FFF，border-radius:14px，border:0.5px solid #F0F0F0
- 发布/主操作按钮：#1A1A1A 黑色（不用紫色）
- 紫色 #6366F1 只用于：链接/角标/选中态点缀
- **例外**：个人主页头图区用深色玻璃拟态（不代表全局转向）

### Badge 配色规则
```
数据科学 → bg:#EEF0FF color:#6366F1
生命科学 → bg:#E8F8F0 color:#16A34A
经济     → bg:#FFF7E6 color:#D97706
宇宙天文 → bg:#FDF0F8 color:#C026D3
编程     → bg:#E6F0FF color:#2563EB
时事     → bg:#F5F5F5 color:#555555
```

### 深色主题颜色系统（2026版，已升级）
```dart
// 背景层级（从深到浅）
darkBg       = Color(0xFF0A0A0F)   // 最底层背景（带蓝调）
darkCard     = Color(0xFF111118)   // 普通卡片
darkCardHero = Color(0xFF141427)   // Hero大卡
darkCardList = Color(0xFF101017)   // 小列表卡片
darkSurface  = Color(0xFF17171F)   // 分类chip底色
darkBorder   = rgba(255,255,255,.06) // 卡片边框
darkDivider  = Color(0xFF1A1A28)   // 分割线

// AI对话页气泡（决策B：跟随App主题）
bubble       = Color(0xFF23233A)   // 比背景亮一档

// 毛玻璃（只用于个人主页/侧边栏等刻意场景）
glassLight   = rgba(255,255,255,0.10)
glassMid     = rgba(255,255,255,0.08)
glassBorder  = rgba(255,255,255,0.06)
```

### Feed布局原则（已确认）
- **无边框沉浸式**，内容直接浮在背景上
- 条目之间只用 0.5px 分割线，无卡片背景色和边框
- 每条结构：来源行 → 标题（bold）→ 作者行 → 摘要（2行）→ 图片（可选）→ 操作行（点赞/收藏/评论/×）
- 深色：#000000底，主文字#FFFFFF，次要#666666，分割线#1A1A1A
- 浅色：#FAFAF8底，主文字#1A1A1A，分割线#F0F0F0
- 首页**不放**小梦AI入口条（极索里已有）

### iOS HIG 交互设计原则
1. 原生风格浮层菜单替代常驻图标行（低频操作收进「...」菜单）
2. 模态操作用 Bottom Sheet，不用 Dialog（AlertDialog 只用于真正二选一阻断）
3. Safe Area 自己管，不整体套一层（防止露出灰色缝隙）
4. 毛玻璃只用在刻意选定的深色语境（头图区/侧边栏/底部导航）
5. 拖拽热区精确绑定到手柄图标（ReorderableDragStartListener）
6. 一次性反馈用 SnackBar，不打断操作
7. 图标统一线性/outline 风格，不用 emoji
8. 渐进式披露（内容多的区块默认最少信息，需要时展开）

---

## 后端 API

base: https://api.dreamingpolar.com

### 认证
```
POST /auth/login → {accessToken, username}
POST /auth/refresh → {accessToken, user}（走 HttpOnly Cookie dp_refresh）
POST /auth/register → 不返回token，需再调/auth/login
GET  /auth/me → 完整用户信息
PATCH /auth/me → 更新资料（birthday传裸"YYYY-MM-DD"）
PUT  /auth/users/privacy → body驼峰bool
POST /auth/change-password
DELETE /auth/account → 注销（级联清理所有COS文件）
```

### 内容
```
GET  /auth/tutorials?status=published&author=xxx&page=1&limit=12
POST /auth/tutorials → {title,summary,cover_image,tags,blocks,status}
PUT  /auth/tutorials/:id
DELETE /auth/tutorials/:id
POST /auth/tutorials/:id/like
DELETE /auth/tutorials/:id/like
GET  /auth/tutorials/:id/comments
POST /auth/tutorials/:id/comments
```

### 用户
```
GET /auth/users/profile/:identifier → 主页信息（403=对方隐私）
POST /auth/users/:targetId/follow
DELETE /auth/users/:targetId/follow
GET  /auth/users/:targetId/follow-status → {isFollowing}
GET  /auth/users/:userId/followers
GET  /auth/users/:userId/following
GET  /auth/users/:userId/liked → {tutorials}
GET  /auth/users/:userId/saves → {saves, total, page}
GET  /auth/me/saves → 自己的收藏
GET  /auth/friends → 互相关注的好友列表
```

### 文件/存储
```
POST /auth/files/upload (multipart, field='file') → {id,filename,file_type,cos_key,url}
  注意：file_type 永远是 "other"，按文件名后缀判断类型
DELETE /auth/files/:id
GET  /auth/storage/usage → {quota,membership,categories}
POST /auth/update-avatar (multipart, field='avatar')
```

### 搜索/通知/消息
```
GET  /auth/search?q=xxx → 全类型搜索
POST /auth/search/history → {keyword} 保存搜索历史
GET  /auth/search/history → {history:[{keyword,...}]}（最多20条）
DELETE /auth/search/history → 清空
GET  /auth/notifications
POST /auth/notifications/:id/read
PUT  /auth/notifications/read-all
GET  /auth/conversations
GET  /auth/conversations/:id/messages
POST /auth/messages → {toUserId,content,type}
```

### 群组/论坛/极索
```
群组：GET/POST /auth/groups，群消息收发，群成员管理
论坛：GET/POST /auth/forums，发帖/回复
极索：GET/POST /auth/questions，提问/回答/采纳/邀请
专栏：GET /auth/columns/mine，POST /auth/columns
```

### 小梦AI
```
POST /auth/xmeng/chat/stream → SSE流式输出
GET  /auth/xmeng/conversations → 对话历史
DELETE /auth/xmeng/conversations/:id
```

### 在线状态
```
GET /auth/users/online-status → 基于last_seen_at推导 online/recently/offline
```

---

## Block 格式（教程/发布内容）
```json
[{
  "id": "uuid",
  "type": "text|code|latex|heading|image|callout|quote|video|audio|link",
  "content": "内容",
  "language": "python",
  "executable": true,
  "level": 1,
  "variant": "info",
  "imageUrl": "https://...",
  "caption": "图片说明"
}]
```

---

## 路由结构
```
/splash          → 启动页
/login           → 登录
/register        → 注册
/home            → 首页 Feed
/jisuo           → 极索问答
/xiaomeng        → 小梦AI欢迎页
/xiaomeng/chat   → 小梦AI对话
/xiaomeng/history → 小梦AI历史
/publish         → 发布页（Block编辑器）
/publish/:id     → 编辑已有文章
/messages        → 消息中心（通知/私信/群组）
/messages/notifications → 通知页
/messages/groups → 群组
/messages/forums → 论坛
/notebook        → Power Notebook首页
/notebook/:id    → Notebook编辑器
/profile         → 我的主页
/edit-profile    → 编辑资料
/settings        → 设置
/settings/subscription → 订阅/会员中心（免费用户头像角标皇冠点击跳转到这）
/settings/privacy → 隐私设置
/settings/security → 账号安全
/settings/storage → 云端存储管理（文件/教程删除，统一走底部Sheet确认）
/users/:identifier → 他人主页
/tutorial/:id    → 文章详情页
/creator         → 创作者中心
/aurora          → 极光计划
/column/:id      → 专栏详情
/friends         → 好友列表
```

---

## 功能完成状态

### ✅ 后端接口（已完成）
- 用户认证：注册/登录/JWT/Refresh Token/注销全量COS清理
- 用户系统：主页/编辑/关注/粉丝/在线状态/好友列表
- 内容创作：文章CRUD/专栏/收藏/点赞/评论/分享
- 极索问答：提问/回答/采纳/邀请
- 即时通讯：私信/群组/富文本/撤回/已读/陌生人限制
- 论坛社区：发帖/回复/精华
- 小梦AI：SSE流式/历史对话持久化/System Prompt代码规范
- 通知系统：多类型/已读/全部已读（群聊/论坛回复不进通知中心）
- 搜索：全类型/历史记录（POST/GET/DELETE）
- 文件：COS上传/删除
- 删除级联清理：文章body图片/专栏封面/私信图片/AI对话/用户注销全量/群聊解散
- search_history 表已建

### ✅ StoreKit内购（2026-07中旬新增）
- Flutter端：`lib/features/subscription/purchase_service.dart`（PurchaseService，
  App启动时`main.dart`里`unawaited(ref.read(purchaseServiceProvider).init())`
  预热，接住上次中断/挂起的交易）+ 订阅页面 + 收据验证已接入
- iOS工程已开启 In-App Purchase Capability
- 仍需等Apple开发者账号审核通过才能在App Store Connect配置真实商品/走通完整
  沙盒到生产的收据验证链路

### ❌ 后端接口（待做）
- APNs推送通知（等Apple账号）
- 创作者收益提现的真实资金对账/打款（分成规则已在Flutter端文案里定好，见
  下方"商业模式"，后端资金侧尚未实现）
- 品牌赞助体系接口

### ✅ Flutter前端（已完成）
**基础功能**
- 双主题（深色/浅色），主题切换 Duration.zero（消除过渡期不同步）
- 在线状态系统（last_seen推导/绿点/私信/群成员/用户主页）
- 搜索历史前端（接入后端接口/展示/清空）
- Firebase Crashlytics框架（脚手架，待flutterfire configure激活）

**内容功能**
- 小梦AI：SSE流式/LaTeX四格式渲染/代码运行跳Notebook/历史对话
- 文章分享：8项分享/生成海报/保存相册/复制链接（RepaintBoundary+image_gallery_saver）
- PDF导出：LaTeX离屏真渲染（Overlay+RepaintBoundary+endOfFrame双重防护）/代码块keep-together（≤40行/块）/图片嵌入/简洁+深色两种样式
- Markdown导出
- 音视频block加外部播放说明文字
- SyntaxError透传原始报错（dreaming_polar仓库，commit 8885db0）

**修复类**
- 底部导航栏主题切换边缘渲染延迟（改读scaffoldBackgroundColor）
- 发布按钮深色模式颜色（硬编码#6366F1，不走M3自动生成色）
- 通知预览点击标记已读（messages_screen.dart）
- PDF代码块跨页截断（keep-together防截断）
- Overlay.insert推到endOfFrame之后（消除build阶段setState冲突）

**视觉重构（已完成）**
- 通知页重设计：分类筛选chips/头像角标/内容摘要引用卡/空状态（commit 4e62e70）
- 文章阅读页重设计：进度条/封面16:9/Apple Books排版/作者卡片/底部操作栏（commit 29c6761）
- 小梦AI对话页视觉重构：欢迎页/对话/历史/深色系/代码运行按钮（commit 38918c2）

### ⏳ Flutter前端（进行中）
- 上面"视觉重构进度"列的大页面基本都已完成，当前主要是细节打磨
  （分割线粗细/背景色统一/空状态文案与插画/按钮描边vs填色这类微调），
  不再有整页级别的"待重设计"任务积压
- Pyodide运行引擎已从"每个页面/每个代码块各自一份隐藏WebView"改成
  App级全局单例，见下方"Pyodide架构"一节

---

## 视觉重构进度

**2026-07-15更新**：这轮重构规模很大（两个并行session同时在改这个仓库），
下表只列确认完成的大项，commit hash不再逐条对——改动太密集，请以
`git log --oneline`为准，这里只做"完成/进行中"的粗粒度状态跟踪。

| 页面 | 状态 | 备注 |
|------|------|--------|
| 通知页 | ✅ 完成 | 分类筛选/头像角标/内容摘要卡 |
| 文章阅读页 | ✅ 完成 | 进度条/封面/作者卡/底部操作栏；2026-07-15去掉了封面上方的阅读进度条（视觉噪音大于功能价值） |
| 小梦AI页 | ✅ 完成 | 欢迎页/对话/历史/深色系 |
| 首页Feed | ✅ 完成 | 无边框沉浸式，米白背景`#FAFAF8` |
| 极索页 | ✅ 完成 | Hero收紧+径向光晕背景+示例问题卡 |
| Notebook编辑页 | ✅ 完成 | Cell卡片/工具栏/紫光晕背景；Pyodide运行引擎已改为App级全局单例（见下方"Pyodide架构"） |
| 消息页 | ✅ 完成 | 快捷入口/最近通知/私信预览 |
| 作品管理页 | ✅ 完成 | 统计卡+单色文章卡+图标/文字操作行，封面支持真实cover_image |
| 专栏管理页 | ✅ 完成 | 彩色封面卡+全交互Sheet |
| 发布编辑页 | ✅ 完成 | Block编辑器/摘要LaTeX渲染/元信息卡 |
| 用户主页 | ✅ 完成 | 网易云风格头图/头像角标（VIP/皇冠升级入口） |
| 群组/论坛/搜索页 | ✅ 完成 | 背景统一米白，各页视觉细节持续微调中 |
| 设置类页面（存储/隐私/协议/群设置） | ✅ 完成 | 删除确认统一改底部Sheet，隐私政策/用户协议改真实公司信息全文 |

---

## 数据库关键表结构

```sql
users                 用户（tags字段已上线）
tutorials             文章（blocks LONGTEXT，status ENUM draft/published/deleted）
columns_table         专栏（cover_image，无CASCADE需手动删）
questions/answers     极索问答
groups/group_messages 群聊（type: image/file/text，content存URL）
messages              私信（type: image/file/text，无外键CASCADE）
forums/forum_posts    论坛
notifications         通知（群聊消息和论坛回复不进通知中心）
ai_conversations      小梦对话（ON DELETE CASCADE）
ai_messages           小梦消息（ON DELETE CASCADE，只有role/content，无图片字段）
user_files            用户文件（cos_key）
search_history        搜索历史（ON DELETE CASCADE，已建表）
refresh_tokens        JWT刷新
```

**注意**：
- tutorials 下架 = PUT status='deleted'，不是 DELETE（可恢复）
- 草稿是 POST status='draft' 存后端，不是本地存储
- GET /auth/tutorials 的 author 参数已实测可用

---

## 当前等待外部条件

| 条件 | 状态 | 解锁后做 |
|------|------|---------|
| Apple开发者账号 | ⏳ 审核中 | Bundle ID + APNs + StoreKit + 上架 |
| 营业执照 | ⏳ 办理中 | 隐私政策填公司名部署 |
| Firebase Console | ❌ 未配置 | flutterfire configure 激活Crashlytics |

---

## 上线前Checklist
- [ ] Apple开发者账号激活
- [ ] Bundle ID配置
- [ ] APNs证书配置
- [ ] Firebase Crashlytics激活（flutterfire configure一次性完成）
- [ ] StoreKit内购商品配置（月度¥39/年度¥128）
- [ ] 隐私政策/用户协议部署到dreamingpolar.com
- [ ] App Store截图准备（6.5寸/5.5寸）
- [ ] TestFlight内测至少1周
- [ ] 关键功能真机回归测试（尤其音视频/图片上传）

---

## 技术债（按优先级）

### 🔴 高优先级（上线前）
- APNs推送通知（等Apple账号，缺失会导致用户召回率极低）
- Firebase Crashlytics激活
- 隐私政策网页版部署（App Store审核必须）
- 文件上传MIME类型校验缺失（安全风险）

### 🟡 中优先级（上线后1个月）
- 音视频50MB上限 → 腾讯云VOD替换（自动转码/流式播放）
- in-app音视频播放器（video_player/just_audio包）
- 图片加载无渐进式
- 空状态缺设计感（全是文字，缺插图）
- 作者卡片无统计数字（等可靠的作者主页接口）
- 创作者收益系统未实现

### 🟢 低优先级（有用户后）
- Skeleton屏加载占位（替换CircularProgressIndicator）
- 错误页面设计
- 搜索结果关键词高亮
- 文章阅读进度保存
- 搜索历史单条删除接口（后端目前只有清空全部）

---

## Pyodide 运行引擎架构（2026-07-15更新）

Notebook/发布页可运行代码块/文章阅读页可运行代码块，三处都要跑Python/SQL/
JavaScript代码，底层都是同一套机制：一个隐藏的1x1 `InAppWebView`加载
`compiler.js`（Web端`https://dreamingpolar.com/components/compiler/compiler.js`，
封装了Pyodide），用`window.runCode(code, lang)`执行，用一个持久的
`onRunResult` JS handler + `Map<String, Completer<String>>`按调用方传的id路由
结果（不是每次调用注册一个新handler）。

- **共享类**：`lib/shared/services/pyodide_engine.dart`的`PyodideEngine`——
  `run(id, code, language, l10n, {timeout})`统一入口（内部处理SQL→Python包装、
  60秒就绪等待、超时兜底），`runJavaScript(code)`是完全独立的直接eval分支，
  不走compiler.js/Pyodide
- **App级单例**：`pyodideEngineProvider`（Riverpod Provider），隐藏WebView挂在
  `main.dart`的`MaterialApp.builder`里，跟路由无关，App启动就开始预热
  compiler.js/Pyodide，不用等用户真正打开Notebook/发布页才开始冷启动
- Notebook（`notebook_editor_screen.dart`）/发布页（`publish_screen.dart`）/
  文章阅读页可运行代码块（`tutorial_block_renderer.dart`的`TutorialCodeBlock`）
  三处都已迁移到这个共享单例，各自的内联WebView/JS桥接代码已删除
- **SQL不是真的一门语言**：compiler.js的`compile()`只认python，SQL cell是
  客户端自己把SQL文本包成一段调用内存sqlite3的python脚本再传进去
- **超时差异**：Notebook传90秒（pandas/matplotlib首次import常超过默认30秒），
  其它调用方用引擎默认的30秒，不是所有场景都要跟着调宽
- **全局共享意味着Python全局命名空间跨页面共用**——不是新引入的风险，
  Notebook内部同一个notebook的多个cell之间本来就依赖这个共享状态（后面的
  cell用前面cell产出的变量）；唯一的新情况是"看完一篇文章的代码块后马上开
  Notebook"这种跨页面场景，理论上会带着上一个页面遗留的全局变量，语义上
  跟真实Jupyter kernel没重启是一回事，不会崩溃

---

## 踩过的坑（关键）

1. **账号数据隔离**：所有缓存key必须带userId前缀，退出只清当前用户缓存
2. **时间戳秒级**：`DateTime.fromMillisecondsSinceEpoch(ts * 1000)`
3. **教程列表格式**：返回 `{tutorials:[...], total, page, pages}`，不是直接数组
4. **tags兼容**：`if (tags is String) jsonDecode(tags) else tags`
5. **ApiClient不抛异常**：返回ApiResponse.error()，调用方检查res.success
6. **token存储key**：`AppConstants.tokenKey(userId) = 'user_${userId}_token'`
7. **ChatScreen必须携带conversation extra**：extra为null时发送按钮静默失效
8. **GridView自动套安全区padding**：嵌在Column里必须显式`padding:EdgeInsets.zero`
9. **ReorderableListView拖拽**：传`buildDefaultDragHandles:false`，只包裹手柄图标
10. **cos_key格式不统一**：tutorials分类已是完整URL，media/docs是相对路径，判断startsWith('http')
11. **file_type字段不可信**：永远是"other"，靠文件名后缀判断类型
12. **SafeArea各自管理**：自定义顶栏/底栏各自用SafeArea包住，不整体套一层
13. **ListView/SliverList撑满子项宽度**：直接子项的width会被tight constraint覆盖，套Align或Row解决
14. **birthday格式**：传裸"YYYY-MM-DD"，传完整ISO会400
15. **主题切换**：Duration.zero消除过渡期各Surface不同步（#0A0A1A → themeAnimationDuration: Duration.zero）
16. **发布按钮深色模式**：硬编码#6366F1，不走M3 colorScheme.primary（M3深色会自动变浅紫）
17. **Overlay.insert在build阶段**：先await endOfFrame再insert，否则setState冲突
18. **ai_messages无图片字段**：只有role/content，COS图片扫content里的myqcloud.com URL
19. **陌生人消息限制**：用/auth/friends好友名单判断，不用单向follow-status
20. **ReorderableListView会吞掉"点空白处收起键盘"的tap手势**：它内部自带一套
    拖拽手势识别，会在"空白但仍在列表边界内"的区域抢先吃掉tap，不冒泡到外层
    `GestureDetector`——跟普通`ListView`的行为不一样。修复不是给
    `ReorderableListView`本身加手势，而是把`GestureDetector`挪到包住整个
    页面（顶栏+画布+底部工具栏一起），不要只包`Expanded(child:
    ReorderableListView(...))`这一层
21. **`GET /auth/users/profile/:identifier`（看别人主页）目前不返回真实
    membership字段**，对外恒为`'free'`——任何"根据对方是不是付费用户显示
    不同UI"的功能，只能对`isSelfView`生效，看别人主页时不要用这个字段做
    判断（会显示错误结论）
22. **`CachedNetworkImage`按URL缓存，而`POST /auth/update-avatar`每次都覆写
    同一个固定COS key**（`avatars/{userId}.jpg`，不是每次生成新URL）——头像
    换成功后状态层是对的，但图片组件会因为URL没变而继续画旧的缓存字节。
    换头像成功后要显式`CachedNetworkImage.evictFromCache(newAvatarUrl)`
23. **多个Claude Code session同时改同一个仓库时，git rebase的冲突标记
    偶尔会被静默剥离**（怀疑是IDE打开冲突文件时的自动解决功能误触发），
    留下"新代码已经在但还在调用被删掉的旧函数"这种损坏状态，`flutter
    analyze`能测出来但表现容易被误判成别的bug。发现代码"看起来对不上"时，
    先用`git show <commit>:<path>`+`diff`直接比对base和origin两边的真实
    内容，搞清楚真实冲突范围，不要凭感觉猜
24. **同一份Pyodide执行逻辑不要在多个页面/多个组件各写一份**：Notebook/
    发布页/文章阅读页三处一度各自维护几乎一样的隐藏WebView+JS桥接代码，
    文章阅读页更夸张——一篇文章有几个可运行代码块就建几个独立WebView实例。
    统一改成`pyodideEngineProvider`全局单例后解决，详见上方"Pyodide运行
    引擎架构"一节

---

## 极梦HD（iPad版）规划

- iPhone（极梦）和iPad（极梦HD）：两个独立App Store应用
- 共享同一仓库，共用 `lib/features/` + `lib/shared/` 业务逻辑，Bundle ID独立
- **iPhone = 发现和消费端，iPad = 创作主战场**
- HD核心差异：
  - 侧边栏导航（NavigationRail，类Linear/Notion）
  - 双栏/三栏布局（文章阅读：目录+内容，Notebook：文件树+代码+输出）
  - 小梦AI：历史列表+对话双栏（类ChatGPT桌面版）
  - Apple Pencil + LaTeX（手写识别→转LaTeX，旗舰功能）
  - 外接键盘快捷键（Cmd+N/F/K等）
  - Split View支持
- 时间线：iPhone上线+1000用户后启动，预计分三阶段各1个月

---

## 商业模式

| 收入来源 | 目标用户 | 优先级 |
|---------|---------|--------|
| 极梦 PRO（¥38/月 或 ¥348/年，新用户首次订阅7天免费试用） | 数据/编程/建模用户 | ★★★ 主要收入 |
| 极梦 PRO MAX（¥68/月） | 重度创作者 | ★★★ |
| 品牌赞助体系 | 创作者+品牌方 | ★★☆ 中期 |
| 极光流量分成 | 优质创作者激励 | ★★☆ 创作者留存 |
| 永久不做流量广告 | — | — |

**极光Aurora Creator Program**（2026-07更新为自动达标制，不再是限量人工申请）：
- 自动达标条件（累计）：发布文章 ≥10篇 · 累计获赞/收藏 ≥100 · 粉丝数 ≥50
- 达标后自动获得：免费PRO MAX会员权益 / 流量分成资格 / 金色创作者标识
- 每月需满足活跃条件（6项任意3项）才能自动续期，不是终身资格
- 流量分成：每月从会员收入提取15-20%作为创作者基金，每月1日结算上月收益，
  满¥50可提现，平台收取10%手续费，1-3个工作日到账，支持微信/支付宝/银行卡

---

## Agent工作规范

- **Flutter 1**：维护型任务、bug修复、视觉重构（dp-flutter仓库）
- **Flutter 2**：新功能开发、重设计（dp-flutter-2仓库）
- **指令模式**：先grep确认结构 → 发给用户确认 → 再动手
- **每次改动**：`flutter analyze --no-pub` → `git add -A` → commit → push
- **后端改动**：npm run build → git push → 服务器 git pull + build + pm2 restart
- **提交规范**：`feat:` 新功能，`fix:` 修复，`refactor:` 重构

---

## 产品评估（2026年7月）

综合评级：**7.7/10，Beta级别**

| 维度 | 评分 | 说明 |
|------|------|------|
| 功能完整度 | 9/10 | 核心模块齐全 |
| 后端架构 | 8/10 | 接口规范，COS清理完善 |
| 数据安全 | 7/10 | JWT完善，MIME校验待补 |
| 前端体验 | 7/10 | 视觉重构进行中 |
| AI集成 | 8/10 | SSE流式+LaTeX真渲染 |
| 运维稳定性 | 7/10 | PM2+Nginx，缺崩溃监控 |
| 可扩展性 | 8/10 | 模块化，HD路径清晰 |

**TestFlight内测**：✅ 现在就可以开始
**App Store正式上线**：⏳ 等Apple账号+隐私政策
**生产级稳定运行**：❌ 还需Crashlytics+APNs+数据库备份