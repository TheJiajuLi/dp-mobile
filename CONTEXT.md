# 极梦产品开发背景文档

## 已有 Web 端参考代码

前端仓库：https://github.com/TheJiajuLi/dreamingpolar.com

里面有：
- mobile.html（现有移动端，Flutter 是重写）
- community.html（社区页面）
- write.html（写教程编辑器）
- tutorial.html（教程详情页）
- profile.html（用户主页）

Flutter 开发时可以参考这些文件的业务逻辑和 API 调用方式。

## 后端 API 完整列表

base: `https://api.dreamingpolar.com`

### 认证

```
GET  /auth/me → {id, username, email, avatar, bio, created_at}
POST /auth/login → {accessToken, username}（注意：没有 user 字段）
POST /auth/refresh → {accessToken, user}
POST /auth/register → {accessToken, username}
```

### 教程

```
GET /auth/tutorials?status=published&author=xxx&page=1&limit=12
→ {tutorials:[{id,title,cover_image,summary,tags,likes,views,
   created_at,username,avatar,user_id}], total, page, pages}

POST /auth/tutorials
→ body: {title, summary, cover_image, tags(array),
         blocks(JSON string), status('draft'|'published')}

PUT    /auth/tutorials/:id → 同上
DELETE /auth/tutorials/:id
POST   /auth/tutorials/:id/like
DELETE /auth/tutorials/:id/like
GET    /auth/tutorials/:id/comments
POST   /auth/tutorials/:id/comments → {content}
```

### 用户

```
GET /auth/users/:username
→ {id, username, bio, avatar, created_at}
```

### 文件

```
GET  /auth/files → {files:[{id,filename,file_type,size_bytes,cos_key,url}]}
POST /auth/files/upload (multipart, field='file')
→ {id, filename, url, cos_key}
```

### 头像

```
POST /auth/update-avatar (multipart, field='avatar')
→ {avatar: 'COS URL'}
```

## Block 格式（教程内容）

`blocks` 字段是 JSON 字符串，格式：

```json
[
  {
    "id": "唯一id",
    "type": "text|code|latex|heading|image|callout",
    "content": "内容",
    "language": "python|javascript|sql",
    "executable": true,
    "level": 2,
    "variant": "tip|warning|info",
    "imageUrl": "",
    "caption": ""
  }
]
```

字段说明：
- `language`/`executable`：`type: code` 时使用
- `level`（2/3/4）：`type: heading` 时使用
- `variant`：`type: callout` 时使用
- `imageUrl`/`caption`：`type: image` 时使用

## 踩过的坑

1. **账号数据隔离（最重要）**
   所有本地缓存必须带 userId 前缀：`'${userId}_tutorials'`、`'${userId}_profile'`。
   退出登录清空当前用户所有缓存。
   切换账号时强制重新 fetch，不用缓存。

2. **时间戳是秒级**
   `created_at` 是 Unix 秒级时间戳。
   显示时：`DateTime.fromMillisecondsSinceEpoch(ts * 1000)`

3. **教程列表格式**
   `GET /auth/tutorials` 返回 `{tutorials:[...], total, page, pages}`，不是直接数组，要取 `data['tutorials']`。

4. **tags 字段**
   `tags` 可能是 JSON 数组字符串，也可能已经是 List。需要兼容：
   ```dart
   if (tags is String) jsonDecode(tags) else tags
   ```

5. **cover_image 可能为空**
   没有封面图时用颜色+图标占位，根据标题首字符哈希选颜色。

6. **avatar 可能是 base64**
   旧数据的 avatar 是 base64 字符串（`data:image/jpeg;base64,...`），需要用 `Image.memory(base64Decode(base64String))` 显示。
   新数据的 avatar 是 COS URL，用 `Image.network` 显示。
   判断方式：`avatar.startsWith('data:image') ? base64 : url`

7. **ARIA API**
   ```
   POST /api/chat
   headers: Authorization: Bearer token
   body: {
     messages: [{role:'user'|'assistant', content:'...'}],
     dataframe_context: {varName, columns, rowCount, sampleRows}
   }
   ```

## COS 存储

```
bucket: dp-1317483118
region: ap-hongkong
URL: https://dp-1317483118.cos.ap-hongkong.myqcloud.com/${cosKey}
```

存储桶公共读，图片 URL 可直接访问。

## 品牌设计

- 主色：`#6366f1`（紫蓝色）
- 品牌名：极梦
- 英文：Dreaming Polar
- 字体：系统默认（iOS 用 SF Pro）
- 风格：参考小红书 + 知乎，干净简洁

## 当前 Flutter 项目结构

```
lib/
├── main.dart
├── core/
│   ├── constants/
│   │   └── app_constants.dart（baseUrl、userId 前缀缓存 key）
│   ├── network/
│   │   ├── api_client.dart（Dio 封装，拦截器自动注入 Bearer token）
│   │   └── api_response.dart（统一响应模型）
│   ├── router/
│   │   └── app_router.dart（GoRouter，StatefulShellRoute 底部导航）
│   └── theme/
│       └── app_theme.dart（主题色 #6366f1，iOS 风格设计系统）
├── features/
│   ├── auth/（登录注册）
│   │   ├── auth_service.dart
│   │   └── screens/login_screen.dart
│   ├── home/（首页九宫格）
│   │   ├── providers/tutorials_provider.dart
│   │   └── screens/home_screen.dart
│   ├── community/（社区，占位待开发）
│   ├── publish/（发布教程，占位待开发）
│   ├── profile/（个人主页，占位待开发）
│   └── aria/（ARIA 助手，占位待开发）
└── shared/
    ├── models/（user_model.dart, tutorial_model.dart）
    └── widgets/（main_shell.dart 底部导航）
```
