# 极梦 Flutter 开发上下文

## 产品定位
极梦（Dreaming Polar）— 全领域知识内容社区
覆盖：科学 / 经济 / 时事 / 生活 / 数据 / 编程 / 宇宙 / 生命科学
定位：知乎的深度 + 小红书的轻量 + Nature的专业质感
Slogan：极梦，为创造而生
品牌色：#6366F1（紫蓝，只做点缀）
主色调：#1A1A1A（近黑）+ #FAFAF8（米白底）

## 设计语言（必读）
- 底色：`AppColors.bg`（`#F7F7FB`，app_theme.dart 里定义，浅色主题的
  `scaffoldBackgroundColor`）——**2026-07-06 起全局统一成这一个值**。
  之前 home_screen.dart 自己配了 `#FAFAF8`、个人主页 `_heroBg` 也是
  `#FAFAF8`、`main_shell.dart` 底部导航栏又是纯白 `#FFFFFF`——三个
  肉眼很难分辨但确实不同的浅灰白，页面内容区跟底部导航栏拼接的地方会
  露出一条很淡但看得出来的接缝（深色主题因为统一读
  `Theme.of(context).scaffoldBackgroundColor` 反而没这个问题）。以后
  任何页面需要"整体背景色"，直接引用 `AppColors.bg`（或干脆不设置，让
  `Theme.of(context).scaffoldBackgroundColor` 自然生效），不要自己再开
  一个新的浅灰白色值
- 主文字：#1A1A1A，次要：#999，辅助：#6366F1
- 无阴影，无渐变，用 0.5px #F0F0F0 细线分区
- 卡片：白色 #FFF，border-radius:14px，border:0.5px solid #F0F0F0
- 发布/主操作按钮：#1A1A1A 黑色，不用紫色
- 紫色 #6366F1 只用于：链接/角标/选中态点缀
- **例外：个人主页头图区**（2026-07-05 起，用户明确要求的深色玻璃拟态
  方向）：深色渐变 #2A1F3D→#1A2A3D（无封面图时）+ 黑色蒙层、iOS原生
  BackdropFilter 毛玻璃按钮（白色 12% 透明度背景）、领域 badge 用同一套
  配色但改成半透明彩色底+浅色字。这个方向只用在个人主页头图区，是刻意
  的局部例外，不代表整个 app 转向深色/渐变/毛玻璃——其余页面（发布页、
  设置页、教程详情页等）继续遵守上面的米白/无渐变/无阴影规范，不要因为
  看到这条例外就顺手把别的页面也套上玻璃拟态。**这条例外踩过一次坑**：
  `InterestTag`（`shared/widgets/interest_tag.dart`）最初只实现了这套
  毛玻璃配色（浅色字+半透明彩色底，靠 BackdropFilter 模糊深色背景才有
  对比度），后来被复用到编辑资料页的兴趣标签选择器——那里是普通浅色
  卡片/页面背景，同一套浅色字糊在浅色底上完全看不清。修复：给
  `InterestTag` 加了个 `glass` 参数（默认 true，头图区例外场景保持不变），
  `glass:false` 时改用 `topic_badge.dart` 那套"浅底实色字"配色（不是新写
  一套，是复用已经验证过在浅色背景上可读的方案）；编辑资料页的三处调用
  全部传 `glass:false`

### Badge 配色规则
数据科学 → bg:#EEF0FF color:#6366F1
生命科学 → bg:#E8F8F0 color:#16A34A
经济     → bg:#FFF7E6 color:#D97706
宇宙天文 → bg:#FDF0F8 color:#C026D3
编程     → bg:#E6F0FF color:#2563EB
时事     → bg:#F5F5F5 color:#555555

## iOS HIG 交互设计原则（必读，组件/交互层面，区别于上面的配色规范）
这些是从发布页、消息页、个人主页等模块的迭代里沉淀下来的交互层规则——上面
「设计语言」管的是颜色/卡片这些静态视觉，这里管的是"东西怎么弹出来、怎么
关掉、危险操作长什么样"这类交互层面，新写弹层/菜单/操作面板一律照此收敛，
不要每个页面各发明一套：

1. **原生风格浮层菜单（Context Menu）替代常驻图标行**：多个次要操作（复制/
   移动/折叠/删除）不平铺成一排常驻图标，收进一个「...」触发的 `showMenu`
   浮层——圆角14px、`PopupMenuDivider` 细分割线分组、图标在左文字在右、
   破坏性操作（删除）用 `#EF4444` 标红且和其它项之间加分割线隔开、背景纯
   白无强投影。只有高频操作（AI入口、拖拽手柄）才常驻，低频操作一律收进
   菜单（参考：`block_card.dart` 的 `_showMoreMenu`）
2. **模态操作用 Bottom Sheet，不用 Dialog**：`showModalBottomSheet` +
   `backgroundColor: Colors.transparent` + 自己套白色 `Container`
   （`borderRadius: vertical top 20`），标题上方留一条灰色小圆角拖拽条
   （36×4，暗示可下滑关闭）。`AlertDialog` 只用于真正需要"确认/取消"
   二选一阻断的场景（应用AI优化结果这种），不用来做菜单
3. **Safe Area 自己管，不整体套一层**：自定义顶栏/底栏各自用
   `SafeArea(top:false)` 或 `SafeArea(bottom:false)` 包住并铺满自己的
   背景色，不在 Scaffold 外层统一留白——否则页面背景色和顶/底栏背景色
   刀切不齐，会露出一圈灰色缝隙（chat_screen.dart/publish_screen.dart
   都踩过，见"踩过的坑"#18）
4. **毛玻璃（BackdropFilter blur）只用在刻意选定的深色语境**：个人主页
   头图区、侧边栏、底部导航——不是全局默认，米白主题的普通页面（发布页/
   设置页/教程详情页）不套毛玻璃
5. **拖拽热区精确绑定到手柄图标**：用 `ReorderableDragStartListener`
   只包裹一个 `drag_handle` 图标，不是让整行/整卡片可长按拖拽——不然会
   跟卡片内部的文字输入框/按钮抢手势
6. **一次性反馈用 SnackBar，不打断操作**：复制成功这类"知道一下就行"的
   反馈用 1~2 秒的 SnackBar，不用 Dialog 硬打断；需要用户做选择的才用
   Dialog/Bottom Sheet
7. **图标统一用线性/outline 风格，不用 emoji**：贴近 SF Symbols 的观感，
   之前把发布页/侧边栏里的 emoji 全部换成了 Material Icons 的 outlined
   变体（"提高档次"）
8. **渐进式披露（Progressive Disclosure）**：内容多/占地方的区块默认给
   最少信息，需要时才展开——block 折叠功能是这条原则的具体实现，折叠态
   只显示类型标签+"已折叠"提示+单行内容预览，且折叠只是编辑器内的临时
   视觉状态，不写进数据模型/不随发布内容持久化
9. **测试规范**：验证任何新交互，必须能在测试完成后用 `git diff` 证明
   反复横跳的临时测试代码（splash 跳转/postFrameCallback 钩子）已经
   完全撤回，零残留（见"踩过的坑"#18）

## 技术栈
- Flutter + Dart（目标：iOS App Store + Android）
- 状态管理：Riverpod（currentUserProvider 存登录用户）
- 路由：GoRouter
- 网络：ApiClient（封装 Dio，自动注入 Bearer token，不抛异常返回 ApiResponse）
- 本地存储：flutter_secure_storage + shared_preferences
- 图片：cached_network_image + flutter_svg
- LaTeX：flutter_math_fork
- WebView（Notebook运行Python）：flutter_inappwebview

## 后端 API
base: https://api.dreamingpolar.com

### 认证
POST /auth/login → {accessToken, username}
POST /auth/refresh → {accessToken, user}（走 HttpOnly Cookie dp_refresh）
POST /auth/register → {message:'注册成功'}，不返回token，需再调一次 /auth/login
GET /auth/me → {id,username,email,avatar,bio,website,handle,gender,location,birthday,zodiac,ip_location,follower_count,following_count,privacy_public_profile,privacy_public_favorites,privacy_allow_comments,privacy_allow_messages,created_at}
PATCH /auth/me → 更新 username/bio/website/gender/location/birthday/zodiac，birthday 传裸 "YYYY-MM-DD"（传完整ISO会 400）
PUT /auth/users/privacy → body驼峰bool(publicProfile等)，GET /auth/me 回的是 privacy_* 蛇形int，两边字段命名不对称
POST /auth/change-password → {oldPassword, newPassword}
DELETE /auth/account → 注销账号
403 "Token 无效或已过期" = token过期(可重试刷新)；401 "未携带 Access Token" = 根本没带token(不可重试)

### 教程
GET /auth/tutorials?status=published&author=xxx&page=1&limit=12
→ {tutorials:[{id,title,cover_image,summary,tags,likes,views,created_at,username,avatar,user_id}], total,page,pages}
POST /auth/tutorials → {title,summary,cover_image,tags(array),blocks(JSON string),status}
PUT /auth/tutorials/:id
DELETE /auth/tutorials/:id
POST /auth/tutorials/:id/like
DELETE /auth/tutorials/:id/like
GET /auth/tutorials/:id/comments
POST /auth/tutorials/:id/comments → {content}

### 用户
GET /auth/users/search?handle=xxx —— 目前是坏的，永远404，不要以为是客户端bug
GET /auth/users/profile/:identifier → {id,username,handle,avatar,bio,website,follower_count,following_count,tutorial_count}，不含gender/location/zodiac；对方设了主页不公开时返回403
GET /auth/users/:identifier（旧接口）/ GET /auth/users/:id/follow-status —— 不受主页不公开影响，作为兜底展示有限信息
POST /auth/users/:targetId/follow
DELETE /auth/users/:targetId/follow
GET /auth/users/:targetId/follow-status → {isFollowing}
GET /auth/users/:userId/followers
GET /auth/users/:userId/following

### 文件 / 存储
POST /auth/files/upload (multipart, field='file') → {id,filename,file_type,size_bytes,created_at,updated_at,cos_key,url}
  file_type 永远是 "other"——后端不区分图片/视频/音频，客户端只能靠文件名后缀猜
DELETE /auth/files/:id → {message:'文件已删除'}
GET /auth/storage/usage → {quota,membership,categories:{notebooks,tutorials,media,docs,other,avatars},totalBytes}
  每个分类 {files:[...], totalBytes}；tutorials 的file自带id+status，cos_key已是完整URL；
  media/docs/notebooks 的file没有id(靠cos_key末段UUID反推)，cos_key是相对路径，需拼COS前缀
  图片/视频/音频没有独立分类，全部合并在 media 里
POST /auth/update-avatar (multipart, field='avatar') → {avatar:'COS URL'}

### 消息（后端待建，目前用 mock 数据）
GET /auth/notifications
GET /auth/conversations
GET /auth/conversations/:id/messages
POST /auth/messages → {toUserId,content,type}

### ARIA
POST /api/chat
headers: Authorization: Bearer token
body: {messages:[{role,content}], dataframe_context:{varName,columns,rowCount,sampleRows}}

## Block 格式（教程/发布内容）
blocks 是 JSON 字符串：
[{id, type(text|code|latex|heading|image|callout|quote|video|audio|link), content, language, executable, level, variant, imageUrl, caption}]

## 路由结构
/splash        → 启动页（自动登录检查）
/login         → 登录页
/register      → 注册页
/switch-account → 切换账号
/home          → 首页（Feed）
/discover      → 发现页（专题+领域地图+创作者）
/publish       → 发布页（Block 编辑器）
/aria          → ARIA 分析助手
/messages      → 消息中心
/messages/chat/:conversationId → 聊天页
/profile       → 我的（个人主页）
/edit-profile  → 编辑资料
/settings      → 设置
/settings/security         → 账号安全
/settings/security/history → 登录历史
/settings/payment          → 支付方式
/settings/subscription     → 订阅/会员
/settings/privacy          → 隐私设置
/settings/storage          → 云端存储（用量+分类文件管理，封面/缩略图见下）
/settings/about            → 关于
/notebook      → Power Notebook 首页
/notebook/:id  → Notebook 编辑器
/users/:identifier       → 他人主页
/users/:userId/followers → 粉丝列表
/users/:userId/following → 关注列表
/tutorial/:id  → 教程详情页

## 底部导航（5个）
首页 / 发现 / +发布（黑色方块按钮）/ 消息 / 我的

## 已实现模块

### 首页
- Feed 三种卡片混排：大图头条 / 文字+缩略图 / 双列小卡
- 话题标签横滑筛选（全部/科学/经济/时事/生活/数据/编程）
- 下拉刷新 + 上拉加载更多

### 发现页（待实现）
三层结构：
1. 本周专题：编辑精选大卡 + 专题文章横滑
2. 领域地图：6宫格（数学物理/生命科学/经济金融/宇宙天文/编程数据/时事）
3. 发现创作者：横滑卡片，按领域推荐

### 社区
- 2列瀑布流，搜索栏+标签筛选（本地过滤）
- 下拉刷新+分页加载

### 发布页（Block编辑器，视觉语言已深化）
- 顶部：标题输入 + 草稿/发布按钮，SafeArea(bottom:false)+自己的白色背景，不留灰色安全区缝隙
- 元信息卡：封面图缩成小方块塞进摘要卡片，加入专栏（bottom sheet选专栏，真实数据，GET /auth/columns/mine——2026-07-06 实测确认这个接口已经好了，不是之前记的404/mock，创作者中心的"我的专栏"页也是同一个接口）+ 标题植入（bottom sheet实时预览），两个功能2列并排放
- 编辑已有内容（2026-07-06）：PublishScreen 现在支持传入 tutorialId 进入编辑模式（路由 /publish/:id）——initState 里 GET /auth/tutorials/:id 回填 title/summary/tags/cover/blocks（EditorBlock.fromJson，是 toJson 的反函数），保存时走 PUT 更新原记录而不是再 POST 一篇新的；同一次编辑会话里第一次保存成功后会记下后端返回的 id，后续再保存也走 PUT，不会重复创建
- Block 列表：统一白色圆角卡片风格，代码块做成 macOS 风格（三个圆点header+语言下拉+运行按钮），编辑器和阅读态共用同一套语法高亮（HighlightingCodeController）
- Block 头部操作（2026-07-06 收进「...」菜单）：上移/下移/复制/复制代码（仅代码块）/折叠/删除 不再常驻平铺图标，收进一个 iOS 原生风格的浮层菜单（圆角、细分割线、删除项标红），AI 入口和拖拽手柄因为用得最频繁仍然常驻。折叠是编辑器内的临时视觉状态，不写进 EditorBlock、不随发布内容持久化——重进编辑页永远是展开的，折叠态显示"已折叠"标签+单行内容预览
- 拖拽排序：ReorderableListView + buildDefaultDragHandles:false，只有drag_handle图标本身可拖（用ReorderableDragStartListener包裹），不是长按任意位置
- 底部横排工具栏，选中的block类型高亮
- 抽屉式预览（不是全屏），预览抽屉作者行加了收藏/分享图标
- 空白引导态：无block时显示"今天想写点什么？"问候语 + 6个快速开始按钮 + 轮播"今日灵感"卡片
- Block 类型：文字/代码/LaTeX/图片/引用/视频(Pro)/音频(Pro)/链接

### 创作者中心 + 极光创作者计划（2026-07-06）
入口：个人主页侧边栏「创作者中心」，`lib/features/creator/` 下四个页面：
- `creator_center_screen.dart`：整体跟随 ThemePreference（浅色白底/深色 `#0A0A1A`）。
  顶部浏览量/获赞/新粉丝三格数据是真实累计值（GET /auth/tutorials
  ?author=username&status=published 求和 + currentUserProvider.followerCount），
  涨幅百分比（↑23%等）后端没有历史快照算不出真实环比，写死 mock，不要当真
  数据看。作品管理/我的专栏两个快捷入口 + 常驻的 AuroraEntryCard（极光计划
  入口卡，固定深色星空底，不跟随主题）+ 草稿箱行（点开直接跳作品管理的
  草稿 tab，不是跳去空白发布页）
- `aurora_screen.dart`：极光计划详情页，固定深色背景 `#0A0812`（不跟随
  ThemePreference，跟个人主页头图区一样是刻意保留的局部深色例外）。除了
  "我的申请进度"卡用真实数据，其余（加入权益/流量分成制度/结算规则/续期
  条件/为什么选极梦/早期创作者）都是纯静态文案，没有对应的真实计算逻辑
- `works_screen.dart`：作品管理，已发布/草稿/下架三个 tab，每个 tab 各自
  查一次 `GET /auth/tutorials?author=username&status=X`（X=published/
  draft/deleted）。**"下架"不是调 DELETE 硬删**——tutorials.status 是
  MySQL ENUM('draft','published','deleted') 三个合法值，下架实际是 GET
  完整教程内容后 PUT 回去把 status 改成 'deleted'，内容和评论/点赞都还在，
  可以在"下架"tab里"恢复上架"（PUT 改回 published）；只有草稿的"删除"
  和下架内容的"彻底删除"才是真正调 DELETE /auth/tutorials/:id（这两种
  情况原本就没公开过或已经不公开，删掉没有社交层面的连带损失）。
  updateTutorial 是整份覆盖语义，不传 blocks/tags 会被清空成默认值，所以
  改 status 前必须先 GET 一次拿完整内容再原样传回去
- `columns_screen.dart`：我的专栏，真实数据 `GET /auth/columns/mine`，
  "新建专栏"真的调 `POST /auth/columns` 创建（不是占位 SnackBar）——这个
  接口本来就在用（publish_screen 的加入专栏功能同一个接口），没有理由
  在这里假装它不存在
- 与最初给的任务描述有出入的地方（都是往更安全/更真实的方向改，不是
  抄近路）：草稿箱本地存储实际上不存在，草稿是 POST /auth/tutorials 时
  status='draft' 存在后端，不是 SharedPreferences；GET /auth/tutorials
  的 author 参数实测已经在服务端正确过滤（2026-07-06 用一次性测试账号
  curl 验证），不再是"传了也无效"的状态，但 Flutter 侧沿用了原有的
  client-side 二次过滤当保险；WorksScreen 的"编辑"按钮需要 PublishScreen
  真的支持编辑已有内容才有意义，为此把 PublishScreen 从"只能新建"扩展成
  能编辑（见上面"发布页"一节的记录）

### Power Notebook
- 首页：最近打开（左滑删除）+ 模板 + 新建底部弹窗
- 编辑器：Cell列表（Python/R/LaTeX/Markdown/SQL）
- Python：隐藏WebView跑 Pyodide（dreamingpolar.com/components/compiler/compiler.js）
- LaTeX：flutter_math_fork 渲染
- 导入：file_picker（csv/xlsx/json/py/ipynb/tex/md）
- 持久化：SharedPreferences，key带userId前缀

### 个人主页（2026-07-05 深色玻璃拟态重设计）
- 头图区固定高度（屏幕50%-Tab栏42-底部导航83，clamp在280~520之间），
  不再是"内容撑多高算多高"——顶部毛玻璃按钮行（汉堡/返回 + 链接 + 更多，
  BackdropFilter blur+白色12%透明度背景）和底部用户信息块都是 Positioned
  绝对定位叠在封面上，互不影响
- 无封面图时的占位渐变：#2A1F3D→#1A2A3D 深色渐变（不是米白系）
- 头像+用户名一行 → 兴趣标签（2026-07-06起：编辑资料页里用户自己选的最多3个
  标签，`lib/core/constants/tag_colors.dart` + `InterestTag` widget 渲染，
  跟发布/首页用的 `shared/utils/topic_badge.dart` 是两套独立配色表——
  topic_badge.dart 服务白色卡片上的浅底实色badge，tag_colors.dart 专门服务
  这里的深色毛玻璃场景（真·BackdropFilter模糊+半透明彩色底+浅色字+同色
  描边），不是重复维护，视觉语境完全不同。不再是"从发布过的教程tags统计
  频率最高3个"那套自动推断了，后端 users.tags 字段已上线（GET/PATCH
  /auth/me、GET /auth/users/profile/:identifier 都支持）
  → bio单行 → 位置+星座+网站压成一行（性别、IP属地这两项为了省空间已经从
  这里拿掉，不再单独占一行）→ 统计+按钮一行
- 统计行是内联文字（"3 文章"这种数字+小字标签紧挨着排成一行，横向可滚动
  防溢出），显示的是文章/获赞/粉丝/关注这种社交数据，不是tab计数；编辑
  资料(32px白底黑字)+分享(毛玻璃)/私信+关注 两个按钮跟统计同一行右侧
- Tab栏是独立的 SliverPersistentHeader(pinned:true, 42px高)，不是
  嵌进头图区的一部分：文章/专栏/Notebook/收藏/点赞五个（专栏在文章和
  Notebook中间），5个tab要用更紧凑的字号(12px)+labelPadding，不然
  "Notebook"这种比中文标签长的单词会被裁切显示不全
- 文章/专栏等Tab：3列九宫格或列表（GridView.count 记得手动
  padding:EdgeInsets.zero，否则安全区自动padding撑出大缝隙）
- **下半部（Tab栏+内容区）2026-07-06 起跟着 ThemePreference 走**：深色
  主题用 `_profileDarkBg` `#0A0A1A` + 深色两色渐变兜底封面
  （`_coverPaletteDark`，5组，教程没有封面图时用）+ 白色/紫色高亮 TabBar +
  半透明白玻璃专栏卡；浅色主题保持原来那套——米白底、`_coverPaletteLight`
  浅色纯色块+图标兜底封面、黑字 TabBar、白底专栏卡。踩过一次坑：第一版
  直接照抄头图区"不跟随主题、永远深色"的例外规则，结果浅色主题下背景/
  卡片全变黑但配色还是深色主题那套，反而是浅色主题下唯一一块看不清的
  区域——头图区可以这样做是因为它本来就一直是深色玻璃拟态设计，没有对应
  的浅色版本；下半部这里在这次改动前已经有成熟的浅色设计，不能直接套用
  同一条"局部深色例外"规则，必须两套配色都做，跟着 isDark 切
- **2026-07-06：整个侧边栏（抽屉）已删除**——`_openProfileDrawer`/
  `_buildProfileDrawer`/`_profileMenuItem`/`_bottomActionButton` 全部拿掉，
  左上角不再有汉堡按钮。原来挂在抽屉里的功能重新分配：
  - 深色模式：不再是"点图标弹出浅色/深色/跟随系统三选一的 bottom
    sheet"，改成点头图右上角的太阳/月亮图标直接切换明暗（`_toggleTheme`，
    在当前 `Theme.of(context).brightness` 的相反值之间二选一，不经过
    "跟随系统"）。图标本身跟着实际生效的明暗态换，不是跟着
    ThemePreference 的取值
  - 创作者中心、设置：分别做成头图右上角的图标（`Icons.article_outlined`
    push `/creator`，`Icons.settings_outlined` push `/settings`），三个
    图标（主题/创作者中心/设置）从左到右一排，只在自己主页显示
  - 我的消息/我的收藏/浏览历史/我的Notebook/草稿箱：这几项没有指定新
    入口，drawer删除后暂时没有专门的菜单能到达——我的消息本来就有底部
    "消息"tab不受影响，草稿箱可以从创作者中心的作品管理走，我的收藏/
    浏览历史本来就是"即将上线"的占位，我的Notebook暂时确实少了一个
    入口，如果需要恢复得另外找地方放
  - 切换账号、退出登录：移进"全部设置"页最底部，不带 `_SectionTitle`
    （页面顶部已经用过一次"账号"当分组标题，这里再来一次会像重复分组）
  - 会员卡：抽屉那张会员升级卡直接删掉，不算功能损失——"全部设置"里
    本来就有对等的"我的会员"入口（会员中心分组），不是新增的
  - 头图顶部这一排图标（返回/主题/创作者中心/设置/其他主页的链接图标）
    统一去掉了原来的 BackdropFilter 毛玻璃圆角底，改成裸图标+黑色投影
    保证在任意背景亮暗下都能看清，不再靠白色半透明底衬托
- 状态栏图标用 AnnotatedRegion<SystemUiOverlayStyle>(value: .light) 强制
  白色，因为头图区总是深色；已知取舍：滚动很远头图完全滚出视口后状态栏
  区域会露出白色Tab栏背景，白图标短暂不好辨认，没做滚动监听动态切换

### 设置主页（settings_screen.dart）
账号/通用/会员中心/关于 四组之后，2026-07-06 起追加一组不带标题的
切换账号+退出登录（原来在侧边栏底部，侧边栏整个删除后搬过来）——退出
登录复用跟以前一样的确认弹窗+`authServiceProvider.logout()`+
`context.go('/login')`，没有改逻辑，只是从 profile 页搬到了这里

### 设置 · 云端存储
- 用量卡片（进度条+已用/总量/剩余）+ 4个可展开分类：Notebook/教程笔记/图片视频音频(media)/文档数据(docs)
- 教程：封面缩略图(CachedNetworkImage)+已发布/草稿状态徽标
- media分类内按文件名后缀客户端猜图片/视频/音频（后端file_type恒为"other"，不可靠）：
  图片走CachedNetworkImage缩略图，视频用video_thumbnail截首帧+播放图标，音频紫色音符图标+模拟波形（非真实波形分析）
- 删除逻辑：教程用自带id走DELETE /auth/tutorials/:id；其余分类从cos_key末段UUID反推id走DELETE /auth/files/:id，反推失败就不显示删除按钮

### 编辑资料（网易云风格）
- 全白背景，分割线分区，无色块
- 生日选择 → 自动推断星座（ZodiacSignExt.fromBirthday）
- 星座：自研SVG icon（ZodiacIcon）+ 紫色文字，无背景

### 消息中心
- 三Tab：通知/私信/群组（群组目前是空白占位，注释写着"下个版本上线"）
- 私信支持：文字/代码/LaTeX/教程卡片/图片
- 通知/私信都是真实后端数据（不是 mock），群组还没有对应接口
- **陌生人消息限制（2026-07-06 后端上线，chat_screen.dart 跟着实现）**：
  互相关注视为好友，完全不受限；非好友规则——对方从没回复过之前，
  我的第一条消息只能是文字类型，发过之后要等对方回复才能再发；对方
  只要回复过一次（不论当时是否互关、后续有没有取关）就永久解锁，两人
  可以自由互发任何类型，这条判断只认"消息历史里有没有对方发的消息"，
  不认实时关注状态。后端 403 时带 `{message, code}`，`code` 是
  `STRANGER_LIMIT`（对方尚未回复）或 `TEXT_ONLY_LIMIT`（首条只能文字）。
  是否互关本身查不了"互相"这个方向（`/auth/users/:id/follow-status`
  只返回 `isFollowing`，是单向的"我关注了没"），用 `/auth/friends`
  好友名单（互相关注的人）本身来判断在不在里面，才是跟后端同一套口径。
  提示条 UI 不是常驻在输入框上方的通栏，是插进消息列表顶部、居中的小
  胶囊——跟输入框上方的横栏比更像一条系统提示，不是一直杵在那的警告；
  且只在真的没有聊天记录时出现，一旦对方回复过（哪怕之后取关了）就再
  也不出现
- **ApiResponse.error 现在会透传原始错误响应体到 `data` 字段**
  （`core/network/api_response.dart`/`api_client.dart`）——2026-07-06 之前
  失败响应只保留一个拍平的 `message` 字符串，`code` 这种结构化字段全部
  丢失，想按错误类型精确处理只能匹配 message 文案（换一个字就失配）。
  现在 `res.data?['code']` 能可靠读到，陌生人限制这两个 code 就是靠这个
  修复才能用，以后其它接口的结构化错误也一样能读
- **好友列表**（`friend_list_screen.dart`，路由 `/friends`）：互相关注的
  用户列表，GET /auth/friends。入口不是消息页里的一个tab（消息页已经有
  通知/私信/群组三个tab，跟最初任务描述假设的"单一会话列表页"不一样），
  是个人主页头图区新增的一个图标，卡在"主题切换"和"创作中心"两个图标
  中间。点开一个好友进聊天：接口本身没直接返回 conversation id，复用
  user_profile_screen.dart"发消息"按钮那套"先查 /auth/conversations
  里有没有现成会话，没有就发一条默认招呼语创建一个"逻辑

## 共享组件
lib/shared/widgets/
- main_shell.dart — 底部导航（首页/发现/+/消息/我的）。2026-07-06 起
  跟着 `Theme.of(context).brightness` 走——之前整条背景/图标颜色都是
  写死的浅色（白底+近黑图标），个人主页下半部改深色之后滚到底会露出
  这条刺眼的白条。深色主题：背景 `#1C1C1E`（复用 app_theme.dart 深色
  scaffoldBackgroundColor 那个值，不是另配一个）、无阴影、选中态白色/
  未选中 `Colors.white38`、中间发布按钮换成品牌紫 `#6366F1`（近黑在
  深色导航条上对比度太低）；浅色主题同一天又从纯白 `#FFFFFF` 改成
  `AppColors.bg`（跟首页/发现页/消息页/个人主页统一，见上面"设计语言"
  里背景色统一的说明，不是重复的改动）
- zodiac_icon.dart — 十二星座SVG图标 + ZodiacPicker

lib/shared/models/
- user_model.dart — UserModel
- tutorial_model.dart — TutorialModel（含tags兼容解析）

## 踩过的坑（必读）

### 1. 账号数据隔离（最重要）
所有缓存key必须带userId前缀：'${userId}_tutorials'
退出登录只清当前用户缓存，不能 deleteAll()

### 2. 时间戳秒级
DateTime.fromMillisecondsSinceEpoch(created_at * 1000)

### 3. 教程列表格式
返回 {tutorials:[...], total, page, pages}，不是直接数组

### 4. tags 兼容
if (tags is String) jsonDecode(tags) else tags

### 5. cover_image 可能为空
无封面按标题首字符 hashCode 选色（紫/绿/橙/粉/蓝）

### 6. avatar 两种格式
avatar.startsWith('data:image')
  ? Image.memory(base64Decode(去掉前缀))
  : CachedNetworkImage(url)

### 7. ApiClient 不抛异常
内部 catch DioException，返回 ApiResponse.error()
调用方必须检查 res.success，不能用 try/catch

### 8. currentUserProvider
ref.watch(currentUserProvider) → UserModel?
不存在 authProvider 或 authProvider.userId

### 9. token 存储 key
AppConstants.tokenKey(userId) = 'user_${userId}_token'
不要用裸字符串 'access_token'

### 10. Cookie 自动管理
已配置 cookie_jar + dio_cookie_manager
refresh token 走 HttpOnly Cookie（dp_refresh），Dio 自动携带

### 11. ChatScreen 必须携带 conversation
context.push('/messages/chat/${id}', extra: conversation)
extra 为 null 时发送按钮静默失效

### 12. Scaffold drawer 做侧边栏
个人主页侧边栏用 Scaffold(drawer: ...) 实现
不要嵌入主页面 Column，否则变成页面内容而非抽屉

### 13. 全局 InputDecorationTheme 会漏灰色底
app_theme.dart 的亮/暗主题都设了 filled:true 的灰色fillColor
任何 TextField 不显式加 filled:false，都会透出一层灰底，跟自定义/透明背景很违和

### 14. GridView 会自动套安全区 padding
GridView / GridView.count 不传 padding 时，会默认套 MediaQuery.padding（安全区）
嵌在 Column/SingleChildScrollView 里的 GridView 必须显式 padding:EdgeInsets.zero，否则跟相邻元素之间会出现说不清的大缝隙（个人主页九宫格、发布页快速开始2列格都踩过）

### 15. ReorderableListView 的拖拽默认是"长按任意位置"
一个纯装饰性 Icon(Icons.drag_handle) 不会自动变成拖拽手柄
要让"只有这个图标能拖"：ReorderableListView 传 buildDefaultDragHandles:false，图标外面包 ReorderableDragStartListener(index:...)

### 16. GET /auth/storage/usage 里 cos_key 格式不统一
tutorials 分类的 cos_key 已经是完整 https:// URL；media/docs/notebooks 分类是相对路径，要拼COS前缀
无脑统一拼前缀会在tutorials上产出重复前缀的坏URL——渲染前必须判断 startsWith('http')

### 17. file_type 字段不可信
POST /auth/files/upload 返回的 file_type 不管传什么 contentType 上传，实测永远是 "other"
要分辨图片/视频/音频只能靠文件名后缀，不能指望后端字段

### 18. 测试路由跳转后必须用 git diff 验证复原
没有UI自动化点击手段时，临时改 splash_screen.dart 的 context.go(...) 目标路由来做可视化验证是可行的
但改完测试后必须 git diff 确认改动只有那一行、且改回原值后 diff 为空，否则容易在来回改的过程中误删周边代码
另外要注意 _restore() 里有两条成功跳转分支（首次登录成功 + 刷新token后登录成功），只改一条可能测不出效果——本机token若已过期会走第二条分支

### 19. ListView/SliverList 会把直接子项的 cross axis 撑成 tight constraint
垂直滚动的 ListView（包括其他基于 Sliver 的滚动容器）给每个直接子项的横向
约束是 min==max==视口宽度，一个明确写了 `width: 36` 的 Container 放进去，
自己的 width 会被这个 tight constraint 顶掉、被拉伸撑满全宽——不是 Container
的 bug，是 BoxConstraints.constrain() 的正常行为。踩过一次（aurora_screen.dart
的返回按钮被拉成了一条通栏），修法是给这个子项外面套一层 `Align`（或
`Row`/`Center`），不要指望子项自己的固定 width 能在 ListView 直接子项这一层
生效

## COS 存储
bucket: dp-1317483118，region: ap-hongkong
URL: https://dp-1317483118.cos.ap-hongkong.myqcloud.com/${cosKey}
公共读，图片 URL 可直接访问
头像目录：avatars/（不计入配额）

## 服务器
腾讯云香港，IP: 150.109.77.250
后端：/root/dp-auth-backend，pm2 服务名 dp-auth，端口 3001
数据库：MySQL，内网 10.5.0.6:3306，库名 dp_users

## 品牌破圈思路
用户发文章的动力来源
现有平台的问题
知乎：写了没人看，算法不扶持新人，大V垄断流量
小红书：适合生活类，数据科学/学术内容没有受众
微信公众号：封闭，没有发现机制，只能靠自己推广
CSDN/博客园：太技术向，没有社区感，排版差
极梦要填的空白：一个让知识型创作者觉得"值得写"的地方。

动力一：被看见
这是最基础的需求。极梦的优势是垂直受众精准——在极梦写一篇关于贝叶斯统计的文章，读者都是真正对这个感兴趣的人，点赞和评论的含金量远高于泛流量平台。
比在朋友圈发文章被10个人无聊点赞，更有价值的是被100个真正懂的人认真阅读。

动力二：Notebook 是天然的发布动机
这是极梦独有的。
用户在 Power Notebook 里做了一个分析，代码跑通了，图出来了——这个过程本身就是内容。发布只需要点一下"发布为文章"，Notebook 直接转成带可运行代码的教程。
其他平台没有这个路径。用户在极梦创作的过程本身就产生了发布动机，不需要额外激励。

动力三：变现预期
早期即使没有知识付费，也要让创作者看到路径：

公开粉丝数和阅读量，让创作者感受到积累
早期创作者标签（"极梦认证创作者"）
承诺未来开放付费专栏

人愿意投入的前提是相信未来有回报，不需要现在就兑现。

动力四：工具本身就值得用
即使没有读者，Power Notebook 本身也是一个好用的工具——比 Jupyter 更轻量，比 Colab 更私密，带 LaTeX 渲染，带 ARIA 辅助。
用户先因为工具来，然后自然而然地发布。这和 GitHub 的逻辑一样：开发者用 GitHub 管代码，不是为了涨粉，但代码公开之后自然形成了社区。

动力五：社区归属感
极梦的全领域定位创造了一个新的身份认同——"极梦创作者"，不是某个领域的专家，而是跨领域的知识探索者。
这个身份在其他平台没有对应位置。物理系学生在知乎写经济，没人看；在极梦，"用物理思维理解经济"恰恰是平台鼓励的。

冷启动的关键策略
光靠产品功能不够，还需要：
第一步：找50个种子创作者
不是泛泛招募，是主动找那些在知乎、公众号上已经有积累但觉得"怀才不遇"的人，给他们开白名单、给他们流量扶持，让他们第一批内容在极梦独家发布。
第二步：编辑团队主动约稿
早期不能完全依赖自然投稿，要像杂志编辑一样主动选题、约稿、帮作者打磨，保证首页内容质量。
第三步：让第一批内容破圈
把极梦上最好的文章推到微博、微信、知乎——不是推极梦这个平台，而是推文章本身，让读者追着内容来注册。

## 视觉风格（2026 风格，高质感）

### 主视觉方向
- 深色为主：主背景 `#0A0A1A` → `#1A0E2E` → `#0D1A3A` 渐变
- 极光光效：`radial-gradient` 紫蓝光晕叠加，营造深空感
- 毛玻璃层：`BackdropFilter blur(20-32px)` + `rgba(255,255,255,0.08-0.12)` 半透明
- 主色调：`#6366F1` 紫蓝，点缀 `#8B5CF6` 深紫

### 侧边栏（Drawer）视觉规范
- 背景：`rgba(15,10,30,0.82)` + `BackdropFilter blur(32px) saturate(1.8)`
- 右边框：`0.5px rgba(255,255,255,0.08)`
- Header：深紫极光渐变 `rgba(99,102,241,0.25) → rgba(139,92,246,0.15) → transparent`
- 菜单图标背景：各领域色 `.withOpacity(0.2)`，图标用浅色版本
- 菜单文字：`rgba(255,255,255,0.85)`
- 分割线：`rgba(255,255,255,0.06)`
- 底部按钮：`rgba(255,255,255,0.4)`，退出用 `#FF6B6B`

### 个人主页视觉规范
- 封面区：深色渐变背景 + `radial-gradient` 极光光晕
- 顶部按钮：毛玻璃 `rgba(255,255,255,0.10)` + `BackdropFilter blur(10px)`
- Badge：领域色 `.withOpacity(0.3)` 背景 + 浅色文字 + `0.5px` 领域色边框
- 统计行：`rgba(255,255,255,0.08)` 毛玻璃卡片
- Tab 选中：`#6366F1` 下划线（深色主题）
- 底部导航：`rgba(10,10,26,0.85)` + `BackdropFilter blur(20px)`

### 技术实现栈
- Flutter + Material 3 + 自定义 Design System
- `CustomPainter`：渐变背景、极光光效
- `BackdropFilter`：毛玻璃效果（侧边栏、顶部按钮、底部导航）
- `AnimationController` / `ImplicitAnimation`：页面微交互
- Lottie / Rive：局部动态效果（可选，后期）
- Skia 渲染引擎：保证复杂渐变在 iOS/Android 一致

  ### 颜色系统（深色主题）
  ```dart
  // 背景层
  bgDeep:    Color(0xFF0A0A1A)
  bgMid:     Color(0xFF1A0E2E)
  bgLight:   Color(0xFF0D1A3A)

  // 毛玻璃
  glassLight: Color(0x1AFFFFFF)  // rgba(255,255,255,0.10)
  glassMid:   Color(0x14FFFFFF)  // rgba(255,255,255,0.08)
  glassBorder: Color(0x0FFFFFFF) // rgba(255,255,255,0.06)

  // 主色
  primary:   Color(0xFF6366F1)
  primaryAlt: Color(0xFF8B5CF6)

  // 文字
  textPrimary:   Color(0xFFFFFFFF)
  textSecondary: Color(0xCCFFFFFF)  // 0.8
  textMuted:     Color(0x66FFFFFF)  // 0.4

  // 功能色
  danger: Color(0xFFFF6B6B)
  ```

  ### 注意事项
  - `BackdropFilter` 在 iOS 上性能优秀，Android 需注意层数不要过多
  - 渐变光晕用 `DecoratedBox` + `BoxDecoration` 叠加，不要用 `ShaderMask`（性能差）
  - 深色模式下所有边框用 `rgba白色` 而非 `rgba黑色`
  - 九宫格内容区卡片用深色渐变而非白色，保持整体调性一致

---

## 产品生态架构（完整闭环）

### 三层架构

**层一：内容生产层**
- 发布页（通用）：任何人可用，文字/代码/LaTeX/图片/视频 Block
- 专业垂直模块：
  - 编程及开发 → Notebook + CM6 + 小梦辅助
  - 数学建模 → LaTeX渲染 + 公式生成 + 3D图形
  - 天体物理 → 3D星体渲染 + 数据可视化
  - 经济杂志 → 数据图表 + 宏观数据接入
  - 科普内容 → 富媒体 + 交互式图解
- 小梦 AI：辅助摘要生成、封面生成、写作建议

**层二：内容分发层**
- 发现页：按领域筛选，热度排序（浏览/点赞/收藏加权）
- 首页推送：个性化推荐（基于用户兴趣标签），优质内容算法+人工筛选后推至首页，首页是流量最大入口

**层三：商业化层**
- 品牌赞助体系（内容原生广告）
- 极光创作者计划（流量分成）
- 极梦 Pro 订阅（工具付费）

---

## 品牌赞助体系

### 核心逻辑
赞助商购买赞助名额 → 系统匹配领域相关优质内容 → 内容顶部原生展示

### 展示样式

**教程详情页**（标题下方）：
┌─────────────────────────────┐
│ 本文由 [品牌名] 赞助           │
│ 「品牌一句话广告语」            │
└─────────────────────────────┘
底部注释：作品创作人可获得赞助分成

**发现页卡片**：
┌────────────────────────┐
│ 📌 赞助      [品牌Logo] │
│ 文章标题                │
│ 作者 · 1.2k浏览         │
└────────────────────────┘

### 收益分配
- 创作者：**70%**（主要受益方）
- 极梦平台：**20%**（匹配+分发服务费）
- 极光基金：**10%**（流入流量分成池，壮大极光计划）

### 定价建议
- 普通优质内容（首页推送）：¥500–2,000 / 7天曝光周期
- 极光创作者内容（高流量）：¥2,000–10,000 / 次
- 爆款内容（专项谈判）：无上限，品牌价值导向

### 优势
- 对创作者：除流量分成外的额外被动收入，无需主动接广告
- 对赞助商：内容原生不突兀，精准领域投放，用户接受度高
- 对平台：不依赖流量广告，内容质量越高赞助价值越高，正向飞轮

### 后端数据表（待实现）
```sql
sponsorships         -- 赞助合同
sponsor_placements   -- 内容匹配记录
sponsor_earnings     -- 创作者收益记录
```

### 后端接口（待实现）
GET  /auth/sponsorships                    -- 赞助商列表
POST /auth/sponsorships/apply              -- 申请赞助
POST /auth/tutorials/:id/sponsor           -- 匹配内容
GET  /auth/creator/sponsor-earnings        -- 创作者赞助收益

### Flutter 待实现
- 教程详情页顶部赞助展示区（标题下方插入赞助卡片）
- 创作者中心新增「赞助收益」模块
- 赞助商后台（独立入口，暂不开发）

---

## 飞轮效应
优质内容 → 更多流量 → 吸引赞助商
↑                        ↓
创作者收益增加 ← 赞助+分成收益
↑                        ↓
└──── 极光基金池扩大 ←────┘

内容质量越高 → 赞助价值越高 → 极光基金越大 → 创作者收益越多 → 激励更多优质创作

---

## 商业模式总结

| 收入来源 | 目标用户 | 现阶段优先级 |
|---------|---------|------------|
| Pro 订阅（¥39/月） | 数据/编程/建模用户 | ★★★ 主要收入 |
| 品牌赞助体系 | 内容创作者+品牌方 | ★★☆ 中期 |
| 极光流量分成 | 优质创作者激励 | ★★☆ 创作者留存 |
| 不做流量广告 | — | 永久不做 |

