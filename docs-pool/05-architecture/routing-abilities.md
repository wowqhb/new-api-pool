# 路由原理：Group + Models + Abilities

> 用户调一次 `/v1/chat/completions` 时，new-api 是怎么挑出一个具体 channel 转发的？这个问题的答案就在 `abilities` 表里。号池新建渠道时**最重要的一件事**是把 abilities 写对——本 fork 出过两次大事故，根因都在这里。

## 1. 路由的输入与输出

输入：
- 用户 token → 找到 user 和 token 自身的 `group`（token.group 优先；没有就 user.group）
- HTTP body 中的 `model` 字段
- 可能还有 `tags` 过滤（tokens 可指定只走某些 tag 的渠道）

输出：
- 选中一个 `channel_id`，按 `priority + weight` 加权随机
- 拿到 `channels.base_url + key + type`，转发

## 2. abilities 表是怎么命中的

```sql
SELECT channel_id, priority, weight
FROM abilities
WHERE `group` = :user_group     -- e.g. 'default'
  AND `model` = :request_model  -- e.g. 'gemini-2.5-flash'
  AND enabled = 1
ORDER BY priority DESC, weight DESC, RANDOM()
LIMIT 1;
```

`abilities` 是 **3 列复合主键** `(group, model, channel_id)`，每一行就是一条"路由规则"。无该行 → `No available channel for model X under group Y`。

## 3. abilities 是怎么被写进去的

**核心**：`Channel.Insert()` 内部会调 `Channel.AddAbilities()`：

```go
// model/channel.go
func (channel *Channel) Insert() error {
    err := DB.Create(channel).Error
    if err != nil { return err }
    return channel.AddAbilities(nil)   // ← ★ 关键
}

// model/ability.go::AddAbilities
models_ := strings.Split(channel.Models, ",")
groups_ := strings.Split(channel.Group, ",")
for _, model := range models_ {
    for _, group := range groups_ {
        // 笛卡尔积写入
        abilities = append(abilities, Ability{
            Group: group, Model: model, ChannelId: channel.Id,
            Enabled: status==enabled, Priority, Weight, Tag,
        })
    }
}
```

**所以**：写一个 channel.Group="default,gemini" + channel.Models="gemini-2.5-pro,gemini-2.5-flash" → abilities 写 4 行：
- `(default, gemini-2.5-pro, ch_id)`
- `(default, gemini-2.5-flash, ch_id)`
- `(gemini, gemini-2.5-pro, ch_id)`
- `(gemini, gemini-2.5-flash, ch_id)`

任何 default 组或 gemini 组的用户调这俩 model 都能命中。

## 4. 本 fork 的 3 大坑（已修，但要知道）

### 坑 1：`model.DB.Create(ch)` 不写 abilities

错误代码：
```go
ch := &model.Channel{...}
model.DB.Create(ch).Error    // ❌ 只写 channels 表，abilities 全无
```

正确：
```go
ch.Insert()                  // ✅ 自动 AddAbilities()
```

历史踩过：自动建渠道时用了 `DB.Create`，结果 channel 列表能看到，但调用上游永远 404 → 路由表里没记录。

### 坑 2：channel.Group 只写一个 `<provider>` 而不是 `default,<provider>`

错误：
```go
ch.Group = recipe.Provider     // 例如 "gemini"
```

后果：路由查 `WHERE group='default' AND model='gemini-2.5-flash'` 命不中，因为 abilities 里的 group 是 `gemini`。

正确：
```go
groupName := recipe.Provider
chGroup := "default"
if groupName != "" && groupName != "default" {
    chGroup = "default," + groupName
}
ch.Group = chGroup
```

这样 abilities 同时写两条：default 组用户和 `<provider>` 组的 vip 用户都能命中。

### 坑 3：channel.Models 留空

错误：建渠道时不填 `Models`，期望"用户后续点'获取模型列表'再补"。

后果：`AddAbilities` 里 `strings.Split("", ",") = [""]`，只写一条 `(group, "", ch_id)` 的废条目。

正确：用 `Recipe.DefaultModels` 预填——这就是 `DefaultModels` 字段存在的原因。

## 5. 自动建渠道的标准代码

`controller/pool.go::AddPoolAccount` / `controller.ManualSubmitJobResult` / `service/pool_worker.go::runJob` 现在都用同一份模式：

```go
recipe, _ := model.GetPoolRecipeByKey(...)   // 取 Provider/ChannelType/BaseURL/DefaultModels

groupName := "default"
if recipe.Provider != "" { groupName = recipe.Provider }

chGroup := "default"
if groupName != "default" {
    chGroup = "default," + groupName
}

poolTag := "pool-auto"   // 或 "pool-manual" / "pool"
ch := &model.Channel{
    Type:        recipe.ChannelType,
    Key:         keyRaw,
    Status:      common.ChannelStatusEnabled,
    Name:        accountName,
    Group:       chGroup,
    Models:      recipe.DefaultModels,
    CreatedTime: common.GetTimestamp(),
    Tag:         &poolTag,
}
if recipe.ChannelBaseURL != "" {
    base := recipe.ChannelBaseURL
    ch.BaseURL = &base
}
if err := ch.Insert(); err != nil {  // ★ 必须 Insert()
    return err
}
poolAccount.ChannelId = ch.Id
poolAccount.Update()
```

如要新加流程，**直接抄这段**就不会再踩坑。

## 6. 修复历史脏数据

如果你 DB 里已经存在"建错的渠道"（abilities 缺失），用 new-api 自带的 `model.FixAbility()`：

```go
// 在 Go 代码里调
fixed, broken, err := model.FixAbility()
fmt.Printf("repaired %d abilities, %d broken channels\n", fixed, broken)
```

或者在启动时 `main.go` 里临时加一行 `model.FixAbility()`，重启即可。

## 7. 排查路由问题的 SQL

```bash
DB=<REPO>/one-api.db

# 1) 看一个 channel 的 abilities 是不是齐
sqlite3 $DB "SELECT \`group\`, model, channel_id, enabled
             FROM abilities
             WHERE channel_id = 42"

# 2) 用户路由查询模拟
sqlite3 $DB "SELECT a.channel_id, c.name, c.type, c.status, a.priority, a.weight
             FROM abilities a JOIN channels c ON c.id = a.channel_id
             WHERE a.\`group\`='default' AND a.model='gemini-2.5-flash'
               AND a.enabled = 1 AND c.status = 1
             ORDER BY a.priority DESC, a.weight DESC"

# 3) 找哪些 channel 没 abilities（修复目标）
sqlite3 $DB "SELECT id, name, type, models, \`group\`
             FROM channels
             WHERE id NOT IN (SELECT DISTINCT channel_id FROM abilities)"

# 4) 反查"为什么我的模型没渠道"
MODEL=gemini-2.5-flash
GROUP=default
sqlite3 $DB "SELECT 'channels with this model' AS info,
                    c.id, c.name, c.\`group\`, c.status, c.tag
             FROM channels c
             WHERE c.models LIKE '%$MODEL%';
            SELECT 'abilities' AS info,
                    a.channel_id, a.\`group\`, a.enabled
             FROM abilities a
             WHERE a.model='$MODEL' AND a.\`group\`='$GROUP';"
```

## 8. 重写 abilities

某 channel 的 `Models` 或 `Group` 改了之后，要用 `channel.UpdateAbilities()` 重写：

```go
ch.Group = "default,gemini,vip"
ch.Models = "gemini-2.5-pro,gemini-2.5-flash,gemini-1.5-pro"
ch.Update()                  // ← 内部自动调 UpdateAbilities()
// 或者手动：
// _ = ch.UpdateAbilities(nil)
```

UpdateAbilities 会先 DELETE 然后 INSERT，原子性由事务保证。

## 9. 路由的二级"tag 过滤"

`tokens.tags` 字段（JSON 数组）存"只允许走哪些 tag 的渠道"。token 设置了之后，路由 SQL 自动加：
```sql
... AND a.tag IN ('pool-auto','pool-manual')
```

号池侧的 `tag` 设计就是给这个用的——你可以创建一个"只走 pool 渠道"的 token，专门给某个客户用。

UI 入口：原生「令牌」编辑页有 tag 选择。

## 10. 一句话总结

> **建任何 channel：用 `ch.Insert()` 而非 `DB.Create(ch)`，`Group` 用逗号双值，`Models` 必须非空。**
> **改任何 channel 的 Group/Models：用 `ch.Update()` 自动重写 abilities，不要手 SQL。**
