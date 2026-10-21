# 第 20 步：开源整理与上传 GitHub

> 本文是"从零到仓库公开"的完整操作手册。
> 仓库本身已经整理好（109 个文件、18 MB、纯英文命名、MIT 许可），
> 你只需要**注册账号 → 建空仓库 → 推送**三步。

---

## 一、仓库已经做了什么

| 项 | 状态 | 说明 |
|---|---|---|
| `LICENSE` | ✅ MIT | 比赛要求 MIT / Apache-2.0 |
| `NOTICE` | ✅ | 第三方代码归属（TMDS 模块来自正点原子参考设计） |
| `README.md` | ✅ 中英双语 | 一句话方案 + 指标表 + 复现步骤 + 仓库结构 |
| `.gitignore` | ✅ | 排除 Vivado 产物、仿真波形、厂商原理图 PDF |
| `.gitattributes` | ✅ | 统一换行符，二进制文件不做文本转换 |
| 文件名纯英文 | ✅ | 报告已从 `作品报告.docx` 改为 `design_report.docx` |
| 移除大文件 | ✅ | 82.5 MB → 18 MB（删掉 30 MB 仿真波形、日志、分析截图） |
| 排除版权资料 | ✅ | 原理图 PDF、官方引脚表、厂商例程文本不进仓库 |

---

## 二、注册 GitHub 账号（约 5 分钟）

1. 打开 <https://github.com/signup>
2. 填 **邮箱** → 设置**密码**（≥8 位，含数字和小写字母）→ 设置**用户名**
   - 用户名会出现在仓库地址里，建议用英文小写+连字符，例如 `zhangsan-fpga`
3. 完成邮箱验证（收验证码）
4. 跳过"选择套餐"（默认 Free 即可）

> 访问慢的话：可以用手机热点、或在浏览器里开代理。
> 如果长期访问困难，也可以改用 **Gitee（码云）**，操作逻辑几乎一样，
> 但比赛是否接受 Gitee 链接需要看当年规则（一般写着"GitHub 或 Gitee"）。

---

## 三、创建一个空仓库（约 2 分钟）

1. 右上角 **`+`** → **`New repository`**
2. 填写：
   | 字段 | 填什么 |
   |---|---|
   | Repository name | `zynq7010-image-filter`（建议，纯英文） |
   | Description | `Real-time 3x3 image filtering accelerator on ZYNQ-7010 (soft-hardware co-design)` |
   | 公开性 | 选 **Public**（比赛要求开源，Private 评委看不到） |
   | Initialize this repository with | **全部不要勾选**（README / .gitignore / license 都不要） |

> ⚠️ **千万不要勾选 "Add a README file"**，否则远端会先有一个提交，
> 你本地推送时会被拒绝（需要先 `git pull --rebase`）。

3. 点 **`Create repository`**
4. 记下页面上的仓库地址：`https://github.com/你的用户名/zynq7010-image-filter.git`

---

## 四、生成访问令牌（PAT）—— 命令行推送必需

GitHub 从 2021 年起**不再支持用密码推送**，必须用 Token。

1. 右上角头像 → **`Settings`**
2. 左侧最下 → **`Developer settings`**
3. **`Personal access tokens`** → **`Tokens (classic)`**
4. 右上 **`Generate new token`** → **`Generate new token (classic)`**
5. 填写：
   - **Note**：`zynq7010-push`
   - **Expiration**：30 days（够用）
   - **Scopes**：只勾 **`repo`**（整个大项都勾上）
6. 点 **`Generate token`**
7. **立刻复制** `ghp_` 开头的那串（页面关掉就再也看不到）

> 这串 token 相当于密码，**不要发到群里、不要写进代码、不要提交到仓库**。
> 我的脚本只在一次 push 命令里用它，不会写进 `.git/config`。

---

## 五、推送（两种方式，选一种）

### 方式 A：图形界面（最省事，推荐新手）

用 **GitHub Desktop**，不用记命令：

1. 下载 <https://desktop.github.com/> 并安装
2. 登录你在第 2 步注册的账号
3. 菜单 **`File` → `Add local repository...`** → 选择 `D:\FPGA比赛`
   - 如果提示"This directory does not appear to be a Git repository"，
     说明还没初始化；先在本目录跑一次 `git init -b main`
4. 左侧会列出 109 个文件 → 底部填提交信息
   （例如 `Initial commit: ZYNQ-7010 real-time image filtering accelerator`）→ 点 **`Commit to main`**
5. 顶部点 **`Publish repository`** → 取消勾选 "Keep this code private" → **`Publish`**

完成。之后每次改了代码，界面会自动显示改动，再点 Commit + Push 即可。

### 方式 B：命令行（我就是用这个准备的，一条命令跑完）

打开 PowerShell，运行：

```powershell
cd D:\FPGA比赛
powershell -ExecutionPolicy Bypass -File tools\publish_to_github.ps1
```

脚本会依次问你：

```
请输入 GitHub 用户名（例如 zhang-san）      →  你的用户名
请输入提交用邮箱（建议 用户名@users.noreply.github.com）
请输入你在 GitHub 上创建的仓库名（例如 zynq7010-image-filter）
粘贴 token（输入时不显示）                  →  刚才复制的 ghp_xxx
```

然后自动完成：配置身份 → 首次提交 → 添加远端 → 推送。

成功后会打印：

```
推送成功！
仓库地址: https://github.com/你的用户名/zynq7010-image-filter
```

### 方式 C：纯手工命令（想理解每一步）

```powershell
cd D:\FPGA比赛

# 1. 身份（只对本仓库生效）
git config user.name  "你的用户名"
git config user.email "你的用户名@users.noreply.github.com"

# 2. 提交
git add -A
git commit -m "Initial commit: ZYNQ-7010 real-time image filtering accelerator"

# 3. 关联远端
git remote add origin https://github.com/你的用户名/zynq7010-image-filter.git

# 4. 推送（会提示输入用户名和 token）
git push -u origin main
```

> 第 4 步提示 `Username:` 输入你的 GitHub 用户名，
> `Password:` **粘贴 token**（不是登录密码，输入时不显示字符）。

---

## 六、验证清单

推送成功后，打开 `https://github.com/你的用户名/zynq7010-image-filter`，逐项确认：

| 检查项 | 期望 |
|---|---|
| 文件列表 | 能看到 `README.md`、`LICENSE`、`NOTICE`、`src/`、`docs/` 等 |
| README 渲染 | 标题、指标表、架构图说明都正常显示 |
| License | 仓库页面右上出现 `MIT license` 标签 |
| 文件总数 | 约 109 个（不含 `.git`） |
| 仓库体积 | 约 18 MB |
| 没有敏感内容 | 搜索一下：不应出现 `原理图.pdf`、`_ref/`、`.log`、`RESUME.md` |

---

## 七、常见问题

| 现象 | 原因 | 解决 |
|---|---|---|
| `remote: Support for password authentication was removed` | 用了登录密码 | 必须用 PAT（第四步） |
| `Authentication failed` | token 过期或没勾 `repo` | 重新生成 token |
| `failed to push some refs / non-fast-forward` | 建仓库时勾了 README | `git pull --rebase origin main` 后重推 |
| `src refspec main does not match any` | 分支名是 `master` | `git branch -M main` 再推 |
| 推送卡住不动 | 国内网络到 GitHub 不稳 | 重试 / 用 SSH / 开代理 / 换 Gitee |
| `file is 105 MB; this exceeds GitHub's file size limit` | 有大文件混进来 | 检查 `.gitignore`，用 `git rm --cached` 移除 |
| 中文文件名警告 | 比赛要求纯英文 | 已全部改为英文 |

---

## 八、之后怎么更新仓库

改了代码或报告后，三步：

```powershell
cd D:\FPGA比赛
git add -A
git commit -m "更新说明：例如 补充四种模式实测照片"
git push
```

或者用 GitHub Desktop：它会自动检测改动，填信息 → Commit → Push。

> 建议每完成一个功能就提交一次，提交信息写清楚做了什么。
> 比赛评审看提交历史能看出工作量与迭代过程。

---

## 九、给评委看的加分项（可选）

1. **仓库描述 + Topics**：在仓库首页右上 `About` 里填描述，并加 topics：
   `zynq`、`fpga`、`verilog`、`image-processing`、`sobel`、`axi4-lite`、`vivado`
2. **Releases**：把 `board/system/system_top.bit` 和 `design_report.docx` 传一个 `v1.0` Release，
   评审不用克隆就能直接下载成品
3. **提交历史**：如果之前一次性提交了 109 个文件，后续改动分开提交，历史更好看
4. **README 顶部加实拍图**：把四模式对比图放进 `docs/images/`，README 里引用，第一眼就有画面
