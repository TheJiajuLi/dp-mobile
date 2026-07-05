# 极梦 Flutter 开发上下文

## 产品定位
极梦（Dreaming Polar）— 全领域知识内容社区
覆盖：科学 / 经济 / 时事 / 生活 / 数据 / 编程 / 宇宙 / 生命科学
定位：知乎的深度 + 小红书的轻量 + Nature的专业质感
Slogan：极梦，为创造而生
品牌色：#6366F1（紫蓝，只做点缀）
主色调：#1A1A1A（近黑）+ #FAFAF8（米白底）

## 设计语言（必读）
- 底色：#FAFAF8（米白，不是纯白）
- 主文字：#1A1A1A，次要：#999，辅助：#6366F1
- 无阴影，无渐变，用 0.5px #F0F0F0 细线分区
- 卡片：白色 #FFF，border-radius:14px，border:0.5px solid #F0F0F0
- 发布/主操作按钮：#1A1A1A 黑色，不用紫色
- 紫色 #6366F1 只用于：链接/角标/选中态点缀

### Badge 配色规则
数据科学 → bg:#EEF0FF color:#6366F1
生命科学 → bg:#E8F8F0 color:#16A34A
经济     → bg:#FFF7E6 color:#D97706
宇宙天文 → bg:#FDF0F8 color:#C026D3
编程     → bg:#E6F0FF color:#2563EB
时事     → bg:#F5F5F5 color:#555555

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
- 元信息卡：封面图缩成小方块塞进摘要卡片，加入专栏（bottom sheet选专栏，mock 2条数据，后端GET /auth/columns还是404）+ 标题植入（bottom sheet实时预览），两个功能2列并排放
- Block 列表：统一白色圆角卡片风格，代码块做成 macOS 风格（三个圆点header+语言下拉+运行按钮），编辑器和阅读态共用同一套语法高亮（HighlightingCodeController）
- 拖拽排序：ReorderableListView + buildDefaultDragHandles:false，只有drag_handle图标本身可拖（用ReorderableDragStartListener包裹），不是长按任意位置
- 底部横排工具栏，选中的block类型高亮
- 抽屉式预览（不是全屏），预览抽屉作者行加了收藏/分享图标
- 空白引导态：无block时显示"今天想写点什么？"问候语 + 6个快速开始按钮 + 轮播"今日灵感"卡片
- Block 类型：文字/代码/LaTeX/图片/引用/视频(Pro)/音频(Pro)/链接

### Power Notebook
- 首页：最近打开（左滑删除）+ 模板 + 新建底部弹窗
- 编辑器：Cell列表（Python/R/LaTeX/Markdown/SQL）
- Python：隐藏WebView跑 Pyodide（dreamingpolar.com/components/compiler/compiler.js）
- LaTeX：flutter_math_fork 渲染
- 导入：file_picker（csv/xlsx/json/py/ipynb/tex/md）
- 持久化：SharedPreferences，key带userId前缀

### 个人主页
- 头图区仿小红书/网易云：黑色蒙层+白字（不是深色文字直接压照片背景，可读性问题）
- 兴趣领域 badge（从tags解析，最多3个，各领域配色）
- 统计行：白色圆角卡片包裹，文章/获赞/粉丝/关注
- 四Tab：文章/Notebook/收藏/点赞
- 文章等三Tab：3列九宫格（GridView.count 记得手动 padding:EdgeInsets.zero，否则安全区自动padding撑出大缝隙），Notebook：列表式
- 左上角汉堡 → Scaffold drawer 抽屉（不嵌入主页面）
- 侧边栏：紫色渐变header + 会员卡 + 菜单 + 底部三按钮

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
- 三Tab：通知/私信/群组
- 私信支持：文字/代码/LaTeX/教程卡片/图片
- 目前 mock 数据，后端消息API待建

## 共享组件
lib/shared/widgets/
- main_shell.dart — 底部导航（首页/发现/+/消息/我的）
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
