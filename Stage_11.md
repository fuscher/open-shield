# Stage 11：规则编辑/添加/删除功能实现

## 一、需求概述

Dashboard 规则管理板块中，编辑按钮（`editRule`）和添加规则按钮（`addRule`）当前仅弹出"功能开发中..."提示，未实现实际功能。本阶段将实现完整的规则 CRUD 功能。

### 功能目标

- 点击编辑按钮可打开模态框，填充当前规则数据
- 点击添加规则按钮可打开空表单模态框
- 点击删除按钮可移除指定规则（带确认提示）
- 保存时调用后端 PUT API 更新规则文件
- 支持 PII、关键词、注入、输出敏感、响应监控、自定义六种规则类型
- 为响应监控和自定义规则添加缺失的编辑/删除按钮
- output_sensitivity 表单根据 strategy 动态显示对应字段
- 自定义规则后端支持多文件写入（按来源文件回写）
- 按当前 Tab 还原默认规则（从 `core/rules/` 源文件恢复）
- 导出时剥离内部 `_source` 字段

---

## 二、设计决策

| 决策项 | 选择 | 说明 |
|--------|------|------|
| 表单方案 | 通用动态表单 | 一个模态框根据 `currentTab` 动态渲染字段 |
| 编辑/添加复用 | 共用模态框 | 通过 `editingRuleIndex` 区分模式（-1 为添加） |
| 数组字段输入 | 文本域换行分隔 | keywords/patterns 用换行分隔，需 HTML 转义 |
| 响应监控分组 | 传参记录 group | 编辑时通过参数传入 `group`，而非事后反查 |
| output_sensitivity | 条件字段 | strategy 切换时动态显示 replacement 或 mask_config |
| 自定义规则 | 后端多文件写入 | 后端返回 `_source` 字段标记来源文件，写回原文件 |
| 删除功能 | confirm 确认 | 删除前弹出浏览器确认对话框 |
| 还原默认 | 按当前 Tab 重置 | 从 `core/rules/` 复制源文件覆盖运行时文件 |
| 导出清洁 | 剥离 `_source` | 导出时移除内部标记字段，保持 YAML 纯净 |
| i18n 支持 | 中英文 | 复用现有 i18n 结构 |
| 安全 | 输入验证 | textarea 内容 HTML 转义；正则表达式合法性校验 |

---

## 三、修改文件清单

| 序号 | 文件路径 | 修改内容 |
|------|----------|----------|
| 1 | `dashboard/index.html` | 添加规则编辑模态框 HTML + JS 函数 + i18n 翻译 + 还原默认按钮 |
| 2 | `dashboard/server.py` | 修改 `load_custom_rules()` 返回 `_source` 字段；修改 PUT 按源文件写入；新增 `POST /reset` 端点；导出时剥离 `_source` |

---

## 四、规则数据结构分析

### 4.1 各类型规则实际 YAML 结构

| 规则类型 | 顶层 key | 字段 |
|---------|----------|------|
| PII | `pii_rules[]` | name, pattern, severity, description, mask{type, prefix, suffix} |
| 关键词 | `keyword_rules[]` | category, keywords[], severity, description |
| 注入 | `injection_rules[]` | name, patterns[], severity, description |
| 输出敏感 | `sensitive_output_rules[]` | name, pattern, severity, strategy, replacement, mask_config{prefix_chars, suffix_chars} |
| 响应监控 | `phishing[]` + `leak_detection[]` | name, pattern, severity |
| 自定义 | `rules[]`（各文件内） | name, type, pattern, severity, description |

### 4.2 output_sensitivity 的 strategy 与字段关系

| strategy 值 | 需要的字段 | 说明 |
|-------------|-----------|------|
| `replace` | `replacement` | 整段替换为 replacement 文本 |
| `mask_credentials` | `replacement` | 凭证部分替换（如 `$1://***:***@$3`） |
| `mask` | `mask_config.prefix_chars`, `mask_config.suffix_chars` | 保留首尾 N 字符，中间用 *** |

### 4.3 表单字段映射

```
通用字段（所有类型）:
├── name / category    - 名称
├── severity           - 级别 (low/medium/high/critical)
└── description        - 描述（响应监控无此字段）

动态字段（按类型）:
├── PII:
│   ├── pattern        - 正则模式
│   ├── mask.type      - 脱敏类型 (email/fixed)
│   ├── mask.prefix    - 前缀保留字符数
│   └── mask.suffix    - 后缀保留字符数
├── 关键词:
│   └── keywords       - 关键词列表（文本域，换行分隔）
├── 注入:
│   └── patterns       - 模式列表（文本域，换行分隔）
├── 输出敏感:
│   ├── pattern        - 正则模式
│   ├── strategy       - 策略 (replace/mask/mask_credentials)
│   ├── replacement    - 替换文本（strategy=replace|mask_credentials 时显示）
│   ├── mask_config.prefix_chars - 前缀保留（strategy=mask 时显示）
│   └── mask_config.suffix_chars - 后缀保留（strategy=mask 时显示）
├── 响应监控:
│   ├── pattern        - 正则模式
│   └── group          - 分组 (phishing/leak_detection)，编辑时从参数传入
└── 自定义:
    ├── pattern        - 正则模式
    ├── type           - 类型 (regex/keyword)
    └── description    - 描述
```

---

## 五、后端修改（server.py）

### 5.1 修改 `load_custom_rules()` - 添加来源标记

```python
def load_custom_rules():
    custom_dir = OPENSHIELD_DIR / "rules" / "custom"
    rules = []
    if custom_dir.exists():
        for yaml_file in sorted(custom_dir.glob("*.yaml")):
            data = load_yaml(f"rules/custom/{yaml_file.name}")
            if data and "rules" in data:
                for rule in data["rules"]:
                    rule["_source"] = yaml_file.name
                    rules.append(rule)
    return {"rules": rules}
```

### 5.2 修改 PUT `/api/rules/custom` - 按源文件分组写入

```python
@app.route("/api/rules/<rule_type>", methods=["PUT"])
def update_rules(rule_type):
    if rule_type not in VALID_RULE_TYPES:
        return jsonify({"status": "error", "message": "Invalid rule type"}), 400
    
    data = request.json
    try:
        if rule_type == "custom":
            # 按 _source 分组写回各自文件
            file_groups = {}
            for rule in data.get("rules", []):
                source = rule.pop("_source", "dashboard_custom.yaml")
                file_groups.setdefault(source, []).append(rule)
            for filename, rules_list in file_groups.items():
                save_yaml(f"rules/custom/{filename}", {"rules": rules_list})
            # 处理被完全删空的文件：对比磁盘上的文件列表
            custom_dir = OPENSHIELD_DIR / "rules" / "custom"
            if custom_dir.exists():
                for yaml_file in custom_dir.glob("*.yaml"):
                    if yaml_file.name not in file_groups:
                        # 文件中的所有规则都被删除了，写入空规则列表
                        save_yaml(f"rules/custom/{yaml_file.name}", {"rules": []})
        else:
            save_yaml(f"rules/{rule_type}.yaml", data)
        return jsonify({"status": "ok"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400
```

### 5.3 说明

- `_source` 字段仅用于前端传回标识，不写入 YAML 文件（`rule.pop("_source", ...)`）
- 新添加的规则默认 `_source` 为 `dashboard_custom.yaml`
- 若某文件所有规则都被删除，写入空 `{"rules": []}` 保持文件存在

### 5.4 新增还原默认端点 `POST /api/rules/<rule_type>/reset`

```python
import shutil

DEFAULT_RULES_DIR = Path(__file__).parent.parent / "core" / "rules"

@app.route("/api/rules/<rule_type>/reset", methods=["POST"])
def reset_rules(rule_type):
    if rule_type not in VALID_RULE_TYPES:
        return jsonify({"status": "error", "message": "Invalid rule type"}), 400

    try:
        if rule_type == "custom":
            src_dir = DEFAULT_RULES_DIR / "custom"
            dest_dir = OPENSHIELD_DIR / "rules" / "custom"
            dest_dir.mkdir(parents=True, exist_ok=True)
            # 清空现有 yaml
            for f in dest_dir.glob("*.yaml"):
                f.unlink()
            # 从源目录复制默认文件
            if src_dir.exists():
                for f in src_dir.glob("*.yaml"):
                    shutil.copy2(f, dest_dir / f.name)
        else:
            src = DEFAULT_RULES_DIR / f"{rule_type}.yaml"
            if not src.exists():
                return jsonify({"status": "error", "message": "Default file not found"}), 404
            dest = OPENSHIELD_DIR / "rules" / f"{rule_type}.yaml"
            shutil.copy2(src, dest)

        return jsonify({"status": "ok"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500
```

**说明**：
- `DEFAULT_RULES_DIR` 基于 server.py 位置推算（`../core/rules/`），指向项目源码中的默认规则
- 标准规则：直接从源文件覆盖 `~/.openshield/rules/<type>.yaml`
- 自定义规则：清空 `~/.openshield/rules/custom/` 目录后，从 `core/rules/custom/` 复制所有默认文件
- 若源文件不存在（部署环境缺失），返回 404

### 5.5 修改导出端点 - 剥离 `_source` 字段

修改 `export_rules()`（server.py:126-134），导出 custom 类型时移除内部标记：

```python
@app.route("/api/rules/<rule_type>/export", methods=["GET"])
def export_rules(rule_type):
    if rule_type not in VALID_RULE_TYPES:
        return jsonify({"status": "error", "message": "Invalid rule type"}), 400
    if rule_type == "custom":
        data = load_custom_rules()
        # 导出时剥离内部标记
        for rule in data.get("rules", []):
            rule.pop("_source", None)
    else:
        data = load_yaml(f"rules/{rule_type}.yaml")
    return jsonify({"filename": f"{rule_type}.yaml", "content": yaml.dump(data, allow_unicode=True)})
```

---

## 六、前端详细设计（index.html）

### 6.1 新增 i18n 翻译

```javascript
// === 中文 (zh) ===
'modal-title-edit-rule': '编辑规则',
'modal-title-add-rule': '添加规则',
'label-rule-name': '名称',
'label-rule-category': '分类名',
'label-rule-pattern': '正则模式',
'label-rule-severity': '严重级别',
'label-rule-description': '描述',
'label-keywords': '关键词（每行一个）',
'label-patterns': '匹配模式（每行一个）',
'label-strategy': '处理策略',
'label-replacement': '替换文本',
'label-mask-prefix-chars': '前缀保留字符数',
'label-mask-suffix-chars': '后缀保留字符数',
'label-mask-type': '脱敏类型',
'label-mask-prefix': '前缀保留',
'label-mask-suffix': '后缀保留',
'label-group': '检测分组',
'label-custom-type': '规则类型',
'btn-cancel-rule': '取消',
'btn-save-rule': '保存',
'msg-save-success': '规则保存成功',
'msg-save-fail': '规则保存失败',
'msg-delete-confirm': '确定要删除此规则吗？',
'msg-invalid-regex': '正则表达式格式无效',
'msg-name-required': '名称不能为空',
'msg-field-required': '必填字段不能为空',
'btn-reset-rules': '还原默认',
'msg-reset-rules-confirm': '确定要将当前规则类型还原为默认设置吗？所有修改将丢失。',
'msg-reset-rules-success': '已还原为默认规则',
'msg-reset-rules-fail': '还原失败',

// === English (en) ===
'modal-title-edit-rule': 'Edit Rule',
'modal-title-add-rule': 'Add Rule',
'label-rule-name': 'Name',
'label-rule-category': 'Category Name',
'label-rule-pattern': 'Regex Pattern',
'label-rule-severity': 'Severity',
'label-rule-description': 'Description',
'label-keywords': 'Keywords (one per line)',
'label-patterns': 'Patterns (one per line)',
'label-strategy': 'Strategy',
'label-replacement': 'Replacement',
'label-mask-prefix-chars': 'Prefix Chars to Keep',
'label-mask-suffix-chars': 'Suffix Chars to Keep',
'label-mask-type': 'Mask Type',
'label-mask-prefix': 'Prefix Keep',
'label-mask-suffix': 'Suffix Keep',
'label-group': 'Detection Group',
'label-custom-type': 'Rule Type',
'btn-cancel-rule': 'Cancel',
'btn-save-rule': 'Save',
'msg-save-success': 'Rule saved successfully',
'msg-save-fail': 'Failed to save rule',
'msg-delete-confirm': 'Are you sure you want to delete this rule?',
'msg-invalid-regex': 'Invalid regex pattern',
'msg-name-required': 'Name is required',
'msg-field-required': 'Required field cannot be empty',
'btn-reset-rules': 'Reset Default',
'msg-reset-rules-confirm': 'Reset this rule type to default? All changes will be lost.',
'msg-reset-rules-success': 'Rules reset to default',
'msg-reset-rules-fail': 'Reset failed',
```

### 6.2 规则编辑模态框 HTML

在 `import-modal` 后面添加：

```html
<!-- 规则编辑弹窗 -->
<div class="modal-overlay" id="rule-modal">
    <div class="modal">
        <div class="modal-header" id="rule-modal-title">编辑规则</div>
        <div id="rule-form-fields">
            <!-- JS 动态渲染 -->
        </div>
        <div class="modal-footer">
            <button class="btn btn-outline" onclick="closeRuleModal()" id="btn-cancel-rule">取消</button>
            <button class="btn btn-primary" onclick="saveRule()" id="btn-save-rule">保存</button>
        </div>
    </div>
</div>
```

### 6.3 全局状态

```javascript
let editingRuleIndex = -1;  // -1 表示添加模式
let editingRuleGroup = '';  // response_guard 编辑时记录原始分组
```

### 6.4 editRule() - 编辑规则

```javascript
function editRule(index, group) {
    editingRuleIndex = index;
    editingRuleGroup = group || '';
    const ruleData = rules[currentTab];
    let rule = null;

    if (currentTab === 'pii') {
        rule = (ruleData.pii_rules || [])[index];
    } else if (currentTab === 'keywords') {
        rule = (ruleData.keyword_rules || [])[index];
    } else if (currentTab === 'injection') {
        rule = (ruleData.injection_rules || [])[index];
    } else if (currentTab === 'output_sensitivity') {
        rule = (ruleData.sensitive_output_rules || [])[index];
    } else if (currentTab === 'response_guard') {
        rule = (ruleData[group] || [])[index];
    } else if (currentTab === 'custom') {
        rule = (ruleData.rules || [])[index];
    }

    renderRuleFormFields(rule);
    document.getElementById('rule-modal-title').textContent = i18n[currentLang]['modal-title-edit-rule'];
    document.getElementById('btn-cancel-rule').textContent = i18n[currentLang]['btn-cancel-rule'];
    document.getElementById('btn-save-rule').textContent = i18n[currentLang]['btn-save-rule'];
    document.getElementById('rule-modal').classList.add('active');
}
```

**关键变化**：`editRule(index, group)` 接收第二个参数 `group`，用于 response_guard 精确定位规则所在分组和组内索引。

### 6.5 addRule() - 添加规则

```javascript
function addRule() {
    editingRuleIndex = -1;
    editingRuleGroup = '';
    renderRuleFormFields(null);
    document.getElementById('rule-modal-title').textContent = i18n[currentLang]['modal-title-add-rule'];
    document.getElementById('btn-cancel-rule').textContent = i18n[currentLang]['btn-cancel-rule'];
    document.getElementById('btn-save-rule').textContent = i18n[currentLang]['btn-save-rule'];
    document.getElementById('rule-modal').classList.add('active');
}
```

### 6.6 deleteRule() - 删除规则

```javascript
async function deleteRule(index, group) {
    if (!confirm(i18n[currentLang]['msg-delete-confirm'])) return;

    const ruleData = JSON.parse(JSON.stringify(rules[currentTab]));

    if (currentTab === 'pii') {
        ruleData.pii_rules.splice(index, 1);
    } else if (currentTab === 'keywords') {
        ruleData.keyword_rules.splice(index, 1);
    } else if (currentTab === 'injection') {
        ruleData.injection_rules.splice(index, 1);
    } else if (currentTab === 'output_sensitivity') {
        ruleData.sensitive_output_rules.splice(index, 1);
    } else if (currentTab === 'response_guard') {
        ruleData[group].splice(index, 1);
    } else if (currentTab === 'custom') {
        ruleData.rules.splice(index, 1);
    }

    try {
        await apiCall(`/api/rules/${currentTab}`, 'PUT', ruleData);
        rules = await apiCall('/api/rules');
        renderRules();
    } catch (err) {
        alert(i18n[currentLang]['msg-save-fail'] + ': ' + err.message);
    }
}
```

### 6.7 closeRuleModal()

```javascript
function closeRuleModal() {
    document.getElementById('rule-modal').classList.remove('active');
}
```

### 6.8 renderRuleFormFields() - 动态渲染表单

```javascript
function renderRuleFormFields(rule) {
    const container = document.getElementById('rule-form-fields');
    const lang = currentLang;
    const t = i18n[lang];

    // 通用字段：名称
    const nameLabel = currentTab === 'keywords' ? t['label-rule-category'] : t['label-rule-name'];
    let html = `
        <div class="form-group">
            <label>${nameLabel}</label>
            <input type="text" id="rule-name" value="${escapeHtml(rule?.name || rule?.category || '')}">
        </div>
        <div class="form-group">
            <label>${t['label-rule-severity']}</label>
            <select id="rule-severity">
                <option value="low" ${rule?.severity === 'low' ? 'selected' : ''}>low</option>
                <option value="medium" ${rule?.severity === 'medium' ? 'selected' : ''}>medium</option>
                <option value="high" ${rule?.severity === 'high' ? 'selected' : ''}>high</option>
                <option value="critical" ${rule?.severity === 'critical' ? 'selected' : ''}>critical</option>
            </select>
        </div>
    `;

    // 按类型渲染动态字段
    if (currentTab === 'pii') {
        html += `
            <div class="form-group">
                <label>${t['label-rule-pattern']}</label>
                <input type="text" id="rule-pattern" value="${escapeHtml(rule?.pattern || '')}">
            </div>
            <div class="form-group">
                <label>${t['label-rule-description']}</label>
                <input type="text" id="rule-description" value="${escapeHtml(rule?.description || '')}">
            </div>
            <div class="form-row">
                <div class="form-group" style="flex:1">
                    <label>${t['label-mask-type']}</label>
                    <select id="rule-mask-type">
                        <option value="email" ${rule?.mask?.type === 'email' ? 'selected' : ''}>email</option>
                        <option value="fixed" ${rule?.mask?.type === 'fixed' ? 'selected' : ''}>fixed</option>
                    </select>
                </div>
                <div class="form-group" style="flex:1">
                    <label>${t['label-mask-prefix']}</label>
                    <input type="number" id="rule-mask-prefix" value="${rule?.mask?.prefix ?? 2}" min="0">
                </div>
                <div class="form-group" style="flex:1">
                    <label>${t['label-mask-suffix']}</label>
                    <input type="number" id="rule-mask-suffix" value="${rule?.mask?.suffix ?? 2}" min="0">
                </div>
            </div>
        `;
    } else if (currentTab === 'keywords') {
        html += `
            <div class="form-group">
                <label>${t['label-keywords']}</label>
                <textarea id="rule-keywords" rows="5">${escapeHtml((rule?.keywords || []).join('\n'))}</textarea>
            </div>
            <div class="form-group">
                <label>${t['label-rule-description']}</label>
                <input type="text" id="rule-description" value="${escapeHtml(rule?.description || '')}">
            </div>
        `;
    } else if (currentTab === 'injection') {
        html += `
            <div class="form-group">
                <label>${t['label-patterns']}</label>
                <textarea id="rule-patterns" rows="5">${escapeHtml((rule?.patterns || []).join('\n'))}</textarea>
            </div>
            <div class="form-group">
                <label>${t['label-rule-description']}</label>
                <input type="text" id="rule-description" value="${escapeHtml(rule?.description || '')}">
            </div>
        `;
    } else if (currentTab === 'output_sensitivity') {
        const strategy = rule?.strategy || 'replace';
        const showReplacement = strategy !== 'mask';
        const showMaskConfig = strategy === 'mask';
        html += `
            <div class="form-group">
                <label>${t['label-rule-pattern']}</label>
                <input type="text" id="rule-pattern" value="${escapeHtml(rule?.pattern || '')}">
            </div>
            <div class="form-group">
                <label>${t['label-strategy']}</label>
                <select id="rule-strategy" onchange="onStrategyChange()">
                    <option value="replace" ${strategy === 'replace' ? 'selected' : ''}>replace</option>
                    <option value="mask" ${strategy === 'mask' ? 'selected' : ''}>mask</option>
                    <option value="mask_credentials" ${strategy === 'mask_credentials' ? 'selected' : ''}>mask_credentials</option>
                </select>
            </div>
            <div class="form-group" id="field-replacement" style="display:${showReplacement ? 'block' : 'none'}">
                <label>${t['label-replacement']}</label>
                <input type="text" id="rule-replacement" value="${escapeHtml(rule?.replacement || '')}">
            </div>
            <div id="field-mask-config" style="display:${showMaskConfig ? 'block' : 'none'}">
                <div class="form-row">
                    <div class="form-group" style="flex:1">
                        <label>${t['label-mask-prefix-chars']}</label>
                        <input type="number" id="rule-mask-prefix-chars" value="${rule?.mask_config?.prefix_chars ?? 4}" min="0">
                    </div>
                    <div class="form-group" style="flex:1">
                        <label>${t['label-mask-suffix-chars']}</label>
                        <input type="number" id="rule-mask-suffix-chars" value="${rule?.mask_config?.suffix_chars ?? 4}" min="0">
                    </div>
                </div>
            </div>
        `;
    } else if (currentTab === 'response_guard') {
        const group = editingRuleGroup || 'phishing';
        html += `
            <div class="form-group">
                <label>${t['label-rule-pattern']}</label>
                <input type="text" id="rule-pattern" value="${escapeHtml(rule?.pattern || '')}">
            </div>
            <div class="form-group">
                <label>${t['label-group']}</label>
                <select id="rule-group">
                    <option value="phishing" ${group === 'phishing' ? 'selected' : ''}>phishing</option>
                    <option value="leak_detection" ${group === 'leak_detection' ? 'selected' : ''}>leak_detection</option>
                </select>
            </div>
        `;
    } else if (currentTab === 'custom') {
        html += `
            <div class="form-group">
                <label>${t['label-rule-pattern']}</label>
                <input type="text" id="rule-pattern" value="${escapeHtml(rule?.pattern || '')}">
            </div>
            <div class="form-group">
                <label>${t['label-custom-type']}</label>
                <select id="rule-custom-type">
                    <option value="regex" ${rule?.type === 'regex' ? 'selected' : ''}>regex</option>
                    <option value="keyword" ${rule?.type === 'keyword' ? 'selected' : ''}>keyword</option>
                </select>
            </div>
            <div class="form-group">
                <label>${t['label-rule-description']}</label>
                <input type="text" id="rule-description" value="${escapeHtml(rule?.description || '')}">
            </div>
        `;
    }

    container.innerHTML = html;
}
```

### 6.9 onStrategyChange() - output_sensitivity 策略切换联动

```javascript
function onStrategyChange() {
    const strategy = document.getElementById('rule-strategy').value;
    document.getElementById('field-replacement').style.display = strategy !== 'mask' ? 'block' : 'none';
    document.getElementById('field-mask-config').style.display = strategy === 'mask' ? 'block' : 'none';
}
```

### 6.10 validatePattern() - 正则验证辅助函数

```javascript
function validatePattern(pattern) {
    try {
        new RegExp(pattern);
        return true;
    } catch (e) {
        return false;
    }
}
```

### 6.11 saveRule() - 保存规则（含验证）

```javascript
async function saveRule() {
    const ruleData = JSON.parse(JSON.stringify(rules[currentTab]));
    const severity = document.getElementById('rule-severity').value;
    const name = document.getElementById('rule-name').value.trim();

    if (!name) {
        alert(i18n[currentLang]['msg-name-required']);
        return;
    }

    let newRule = {};

    if (currentTab === 'pii') {
        const pattern = document.getElementById('rule-pattern').value;
        if (pattern && !validatePattern(pattern)) {
            alert(i18n[currentLang]['msg-invalid-regex']);
            return;
        }
        newRule = {
            name,
            pattern,
            severity,
            description: document.getElementById('rule-description').value,
            mask: {
                type: document.getElementById('rule-mask-type').value,
                prefix: parseInt(document.getElementById('rule-mask-prefix').value) || 0,
                suffix: parseInt(document.getElementById('rule-mask-suffix').value) || 0
            }
        };
        ruleData.pii_rules = ruleData.pii_rules || [];
        if (editingRuleIndex === -1) {
            ruleData.pii_rules.push(newRule);
        } else {
            ruleData.pii_rules[editingRuleIndex] = newRule;
        }

    } else if (currentTab === 'keywords') {
        const keywords = document.getElementById('rule-keywords').value.split('\n').filter(k => k.trim());
        if (keywords.length === 0) {
            alert(i18n[currentLang]['msg-field-required']);
            return;
        }
        newRule = {
            category: name,
            keywords,
            severity,
            description: document.getElementById('rule-description').value
        };
        ruleData.keyword_rules = ruleData.keyword_rules || [];
        if (editingRuleIndex === -1) {
            ruleData.keyword_rules.push(newRule);
        } else {
            ruleData.keyword_rules[editingRuleIndex] = newRule;
        }

    } else if (currentTab === 'injection') {
        const patterns = document.getElementById('rule-patterns').value.split('\n').filter(p => p.trim());
        if (patterns.length === 0) {
            alert(i18n[currentLang]['msg-field-required']);
            return;
        }
        // 验证每个正则
        for (const p of patterns) {
            if (!validatePattern(p)) {
                alert(i18n[currentLang]['msg-invalid-regex'] + ': ' + p);
                return;
            }
        }
        newRule = {
            name,
            patterns,
            severity,
            description: document.getElementById('rule-description').value
        };
        ruleData.injection_rules = ruleData.injection_rules || [];
        if (editingRuleIndex === -1) {
            ruleData.injection_rules.push(newRule);
        } else {
            ruleData.injection_rules[editingRuleIndex] = newRule;
        }

    } else if (currentTab === 'output_sensitivity') {
        const pattern = document.getElementById('rule-pattern').value;
        if (pattern && !validatePattern(pattern)) {
            alert(i18n[currentLang]['msg-invalid-regex']);
            return;
        }
        const strategy = document.getElementById('rule-strategy').value;
        newRule = { name, pattern, severity, strategy };
        if (strategy === 'mask') {
            newRule.mask_config = {
                prefix_chars: parseInt(document.getElementById('rule-mask-prefix-chars').value) || 4,
                suffix_chars: parseInt(document.getElementById('rule-mask-suffix-chars').value) || 4
            };
        } else {
            newRule.replacement = document.getElementById('rule-replacement').value;
        }
        ruleData.sensitive_output_rules = ruleData.sensitive_output_rules || [];
        if (editingRuleIndex === -1) {
            ruleData.sensitive_output_rules.push(newRule);
        } else {
            ruleData.sensitive_output_rules[editingRuleIndex] = newRule;
        }

    } else if (currentTab === 'response_guard') {
        const pattern = document.getElementById('rule-pattern').value;
        if (pattern && !validatePattern(pattern)) {
            alert(i18n[currentLang]['msg-invalid-regex']);
            return;
        }
        const newGroup = document.getElementById('rule-group').value;
        newRule = { name, pattern, severity };

        if (editingRuleIndex === -1) {
            // 添加模式
            ruleData[newGroup] = ruleData[newGroup] || [];
            ruleData[newGroup].push(newRule);
        } else {
            // 编辑模式：从原始 group 中删除，写入新 group
            const oldGroup = editingRuleGroup;
            if (oldGroup && ruleData[oldGroup]) {
                ruleData[oldGroup].splice(editingRuleIndex, 1);
            }
            ruleData[newGroup] = ruleData[newGroup] || [];
            ruleData[newGroup].push(newRule);
        }

    } else if (currentTab === 'custom') {
        const pattern = document.getElementById('rule-pattern').value;
        if (pattern && !validatePattern(pattern)) {
            alert(i18n[currentLang]['msg-invalid-regex']);
            return;
        }
        newRule = {
            name,
            pattern,
            severity,
            type: document.getElementById('rule-custom-type').value,
            description: document.getElementById('rule-description').value
        };
        ruleData.rules = ruleData.rules || [];
        if (editingRuleIndex === -1) {
            // 新增规则默认归入 dashboard_custom.yaml
            newRule._source = 'dashboard_custom.yaml';
            ruleData.rules.push(newRule);
        } else {
            // 编辑：保留原始 _source
            newRule._source = ruleData.rules[editingRuleIndex]._source || 'dashboard_custom.yaml';
            ruleData.rules[editingRuleIndex] = newRule;
        }
    }

    try {
        await apiCall(`/api/rules/${currentTab}`, 'PUT', ruleData);
        rules = await apiCall('/api/rules');
        renderRules();
        closeRuleModal();
        alert(i18n[currentLang]['msg-save-success']);
    } catch (err) {
        alert(i18n[currentLang]['msg-save-fail'] + ': ' + err.message);
    }
}
```

### 6.12 修改 renderResponseGuardRules() - 添加编辑/删除按钮

```javascript
function renderResponseGuardRules(container, data) {
    const groups = ['phishing', 'leak_detection'];
    let tableRows = '';

    groups.forEach(group => {
        (data[group] || []).forEach((rule, index) => {
            tableRows += `
                <tr>
                    <td>${escapeHtml(rule.name || '-')}</td>
                    <td style="max-width:300px;overflow:hidden;text-overflow:ellipsis;">${escapeHtml(rule.pattern || '-')}</td>
                    <td><span class="tag tag-${rule.severity || 'low'}">${rule.severity || 'low'}</span></td>
                    <td>${group}</td>
                    <td>
                        <button class="btn btn-outline btn-sm" onclick="editRule(${index}, '${group}')">${i18n[currentLang]['btn-edit']}</button>
                        <button class="btn btn-danger btn-sm" onclick="deleteRule(${index}, '${group}')">${i18n[currentLang]['btn-delete']}</button>
                    </td>
                </tr>
            `;
        });
    });

    container.innerHTML = `
        <div class="table-container">
            <table>
                <thead>
                    <tr>
                        <th>${i18n[currentLang]['th-name']}</th>
                        <th>${i18n[currentLang]['th-pattern']}</th>
                        <th>${i18n[currentLang]['th-level-col']}</th>
                        <th>${i18n[currentLang]['label-group'] || 'Group'}</th>
                        <th>${i18n[currentLang]['th-actions']}</th>
                    </tr>
                </thead>
                <tbody>${tableRows}</tbody>
            </table>
        </div>
        <button class="btn btn-outline" style="margin-top:15px;" onclick="addRule()">${i18n[currentLang]['btn-add-rule']}</button>
    `;
}
```

**关键变化**：
- 不再将 phishing + leak_detection 合并为一个扁平数组
- 每行传递 `(index, group)` 参数，确保编辑/删除精确定位
- 新增 Group 列显示规则所属分组

### 6.13 修改 renderCustomRules() - 添加编辑/删除按钮

```javascript
function renderCustomRules(container) {
    const customRules = rules.custom?.rules || [];
    container.innerHTML = `
        <div class="table-container">
            <table>
                <thead>
                    <tr>
                        <th>${i18n[currentLang]['th-name']}</th>
                        <th>${i18n[currentLang]['th-type']}</th>
                        <th>${i18n[currentLang]['th-pattern']}</th>
                        <th>${i18n[currentLang]['th-level-col']}</th>
                        <th>${i18n[currentLang]['th-actions']}</th>
                    </tr>
                </thead>
                <tbody>
                    ${customRules.map((rule, index) => `
                        <tr>
                            <td>${escapeHtml(rule.name || '-')}</td>
                            <td>${escapeHtml(rule.type || '-')}</td>
                            <td style="max-width:300px;overflow:hidden;text-overflow:ellipsis;">${escapeHtml(rule.pattern || '-')}</td>
                            <td><span class="tag tag-${rule.severity || 'low'}">${rule.severity || 'low'}</span></td>
                            <td>
                                <button class="btn btn-outline btn-sm" onclick="editRule(${index})">${i18n[currentLang]['btn-edit']}</button>
                                <button class="btn btn-danger btn-sm" onclick="deleteRule(${index})">${i18n[currentLang]['btn-delete']}</button>
                            </td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
        <button class="btn btn-outline" style="margin-top:15px;" onclick="addRule()">${i18n[currentLang]['btn-add-rule']}</button>
    `;
}
```

### 6.14 修改现有 renderRules() 中的通用规则表格

为已有的 pii/keywords/injection/output_sensitivity 规则行添加删除按钮：

```javascript
// 在 rulesList.map 的 <td> 操作列中，在编辑按钮旁添加删除按钮：
<td>
    <button class="btn btn-outline btn-sm" onclick="editRule(${index})">${i18n[currentLang]['btn-edit']}</button>
    <button class="btn btn-danger btn-sm" onclick="deleteRule(${index})">${i18n[currentLang]['btn-delete']}</button>
</td>
```

### 6.15 还原默认规则

**按钮位置**：在规则管理页工具栏，与"导入YAML"、"导出YAML"按钮并列（`index.html` 约 line 1066 附近）：

```html
<button class="btn btn-outline" onclick="resetRules()" id="btn-reset-rules">还原默认</button>
```

**JS 函数**：

```javascript
async function resetRules() {
    if (!confirm(i18n[currentLang]['msg-reset-rules-confirm'])) return;

    try {
        await apiCall(`/api/rules/${currentTab}/reset`, 'POST');
        rules = await apiCall('/api/rules');
        renderRules();
        alert(i18n[currentLang]['msg-reset-rules-success']);
    } catch (err) {
        alert(i18n[currentLang]['msg-reset-rules-fail'] + ': ' + err.message);
    }
}
```

**行为说明**：
- 仅还原当前 Tab 对应的规则类型
- 标准规则：从 `core/rules/<type>.yaml` 覆盖 `~/.openshield/rules/<type>.yaml`
- 自定义规则：清空 `~/.openshield/rules/custom/` 目录，从 `core/rules/custom/` 恢复所有默认文件
- 还原后自动重新加载规则列表并刷新界面

---

## 七、数据流

### 7.1 编辑规则流程

```
用户点击编辑按钮 editRule(index, group?)
    ↓
根据 currentTab + index + group 获取规则对象
    ↓
renderRuleFormFields(rule) 渲染表单（含已有值）
    ↓
打开模态框
    ↓
用户修改字段（output_sensitivity 可切换 strategy）
    ↓
点击保存 → saveRule()
    ↓
前端验证（name 非空、正则合法、数组非空）
    ↓
构建新规则对象，替换原数组中的元素
    ↓
PUT /api/rules/{type} → 后端写入 YAML
    ↓
重新 GET /api/rules 刷新前端数据
    ↓
renderRules() + closeRuleModal()
```

### 7.2 删除规则流程

```
用户点击删除按钮 deleteRule(index, group?)
    ↓
浏览器 confirm() 确认
    ↓
深拷贝 rules[currentTab]
    ↓
splice(index, 1) 移除目标规则
    ↓
PUT /api/rules/{type} → 后端写入 YAML
    ↓
重新 GET /api/rules 刷新前端数据
    ↓
renderRules()
```

### 7.3 自定义规则写入流程（后端）

```
前端 PUT /api/rules/custom
    ↓ body: { rules: [{..., _source: "url_detector.yaml"}, {..., _source: "dashboard_custom.yaml"}] }
后端接收 → 按 _source 分组
    ↓
url_detector.yaml 的规则 → 写回 rules/custom/url_detector.yaml
dashboard_custom.yaml 的规则 → 写回 rules/custom/dashboard_custom.yaml
    ↓
若某文件在请求中无对应规则 → 写入 {"rules": []}
    ↓
返回 {"status": "ok"}
```

### 7.4 还原默认规则流程

```
用户点击"还原默认"按钮
    ↓
浏览器 confirm() 确认
    ↓
POST /api/rules/{currentTab}/reset
    ↓
后端根据 rule_type 判断：
    ├── 标准类型：shutil.copy2(core/rules/<type>.yaml → ~/.openshield/rules/<type>.yaml)
    └── custom：清空 custom/ 目录 → 从 core/rules/custom/ 复制所有默认文件
    ↓
返回 {"status": "ok"}
    ↓
前端重新 GET /api/rules 刷新数据
    ↓
renderRules()
```

---

## 八、实施顺序

1. **Phase 1**：修改 `server.py` - `load_custom_rules()` 添加 `_source` 字段、修改 PUT 按源文件写入、修改导出剥离 `_source`
2. **Phase 2**：`server.py` 新增 `POST /api/rules/<rule_type>/reset` 端点
3. **Phase 3**：添加 i18n 翻译文本（中英文，含还原默认相关）
4. **Phase 4**：添加规则编辑模态框 HTML + 还原默认按钮
5. **Phase 5**：实现 `renderRuleFormFields()` + `onStrategyChange()` + `validatePattern()`
6. **Phase 6**：实现 `editRule()` + `addRule()` + `closeRuleModal()`
7. **Phase 7**：实现 `saveRule()` 保存逻辑（含验证）
8. **Phase 8**：实现 `deleteRule()` 删除逻辑
9. **Phase 9**：实现 `resetRules()` 还原默认逻辑
10. **Phase 10**：修改 `renderResponseGuardRules()` + `renderCustomRules()` + 通用表格添加编辑/删除按钮
11. **Phase 11**：测试验证所有规则类型的完整 CRUD + 还原默认

---

## 九、代码量预估

| 部分 | 代码行数 |
|------|----------|
| server.py 修改（`_source`、PUT 分文件、导出剥离） | ~30 行 |
| server.py 新增 reset 端点 | ~25 行 |
| i18n 翻译（含还原默认） | ~48 行 |
| 模态框 HTML + 还原默认按钮 | ~16 行 |
| renderRuleFormFields() + onStrategyChange() | ~100 行 |
| editRule() + addRule() + closeRuleModal() | ~35 行 |
| saveRule()（含验证） | ~90 行 |
| deleteRule() | ~25 行 |
| resetRules() | ~12 行 |
| validatePattern() | ~7 行 |
| 修改 renderResponseGuardRules/renderCustomRules/通用表格 | ~40 行 |
| **总计** | **~428 行** |

---

## 十、与原计划相比的关键修正

| 原计划问题 | 修正方案 |
|-----------|----------|
| `editRule()` 不处理 response_guard 和 custom | 添加了这两种类型的规则获取逻辑 |
| `saveRule()` custom 类型未将规则写入 ruleData | 添加 `ruleData.rules.push(newRule)` 和索引替换 |
| output_sensitivity 缺少 `mask_config` 支持 | 根据 strategy 动态显示 replacement 或 mask_config 字段 |
| response_guard 用 name 反查规则（不可靠） | 改为 `editRule(index, group)` 直接传递组内索引和分组名 |
| response_guard 编辑时 group 未回填 | 使用 `editingRuleGroup` 记录并在下拉框设置 selected |
| 自定义规则编辑会产生重复 | 后端改为按 `_source` 分文件写回 |
| 缺少删除功能 | 新增 `deleteRule()` 函数 + 各表格添加删除按钮 |
| textarea 内容未 HTML 转义（XSS） | 所有 textarea/input 值均通过 `escapeHtml()` |
| 无正则验证 | 新增 `validatePattern()` 在保存前校验 |
| 模态框按钮不随语言切换 | 打开模态框时手动设置按钮文本 + i18n 添加对应 key |
| 空 keywords/patterns 可保存 | 添加数组非空校验 |
| 无还原默认规则功能 | 新增 `POST /api/rules/<type>/reset` 端点 + 前端 `resetRules()` |
| 导出 custom 规则泄露 `_source` 内部字段 | 导出端点在返回前 `pop("_source")` 剥离 |

---

## 十一、参考实现

Webhook 编辑功能（`index.html:2075-2112`）提供了完整的模态框编辑模式参考：
- `showAddWebhookModal()` - 添加模式
- `editWebhook(index)` - 编辑模式
- `saveWebhook()` - 保存逻辑
- 模态框 HTML（`index.html:1144-1169`）

规则编辑功能复用相同的 CSS 类和交互模式，但增加了：
- 动态表单渲染（因规则类型字段差异大）
- 条件字段显示（output_sensitivity strategy 联动）
- 分组参数传递（response_guard）
- 前端输入验证

---

## 十二、审查注意事项

### 12.1 后端实现注意事项

| 项目 | 注意事项 |
|------|----------|
| `load_custom_rules()` 修改 | 当前实现（server.py:401-409）只是简单合并规则，添加 `_source` 字段时需确保不破坏现有数据结构 |
| `update_rules()` 修改 | 当前实现（server.py:111-124）只写入 `dashboard_custom.yaml`，修改后需处理多文件写入逻辑和文件不存在的情况 |
| `DEFAULT_RULES_DIR` 路径 | 基于 `server.py` 位置推算（`../core/rules/`），部署时需确保目录结构一致 |
| `shutil` 模块 | 需确认已导入，或在 reset 端点实现时添加导入 |
| 自定义规则空文件处理 | 当某文件所有规则被删除时，写入 `{"rules": []}` 保持文件存在 |
| `_source` 字段剥离 | `rule.pop("_source", ...)` 确保不写入 YAML 文件 |

### 12.2 前端实现注意事项

| 项目 | 注意事项 |
|------|----------|
| `escapeHtml()` 函数 | 需确认已实现，用于防止 XSS 攻击（所有 textarea/input 值均需转义） |
| `apiCall()` 函数 | 确认已实现，用于封装 fetch 请求 |
| i18n 键名冲突 | 添加新键名前检查是否与现有 i18n 对象中的键名冲突 |
| `renderResponseGuardRules()` 修改 | 当前实现（index.html:1955-1982）将 phishing + leak_detection 合并为扁平数组，修改后需保持分组结构 |
| `renderCustomRules()` 修改 | 当前实现（index.html:1984-2010）没有编辑/删除按钮，需添加 |
| 模态框 CSS 类 | 复用现有 `.modal-overlay` 和 `.modal` 类，确保样式一致 |
| 按钮文本国际化 | 打开模态框时需手动设置按钮文本（`btn-cancel-rule`、`btn-save-rule`） |
| `editingRuleGroup` 状态 | response_guard 编辑时需记录原始分组，用于编辑模式下的分组切换 |

### 12.3 数据一致性注意事项

| 项目 | 注意事项 |
|------|----------|
| response_guard 分组切换 | 编辑时从原 group 删除，写入新 group，需确保数组索引正确 |
| custom 规则 `_source` 默认值 | 新增规则默认 `_source` 为 `dashboard_custom.yaml` |
| 正则表达式验证 | 使用 `new RegExp()` 验证，需处理用户输入的转义字符 |
| 数组字段过滤 | keywords/patterns 使用 `split('\n').filter(k => k.trim())` 过滤空行 |
| 深拷贝 | 使用 `JSON.parse(JSON.stringify())` 进行深拷贝，避免修改原始数据 |

### 12.4 测试验证要点

| 测试项 | 验证内容 |
|--------|----------|
| PII 规则 CRUD | 编辑、添加、删除 PII 规则，验证 mask 字段 |
| 关键词规则 CRUD | 编辑、添加、删除关键词规则，验证 keywords 数组 |
| 注入规则 CRUD | 编辑、添加、删除注入规则，验证 patterns 数组 |
| 输出敏感规则 CRUD | 编辑、添加、删除输出敏感规则，验证 strategy 切换联动 |
| 响应监控规则 CRUD | 编辑、添加、删除响应监控规则，验证分组参数传递 |
| 自定义规则 CRUD | 编辑、添加、删除自定义规则，验证多文件写入 |
| 还原默认功能 | 测试各类型规则的还原默认功能 |
| 导出清洁性 | 导出 custom 规则时验证 `_source` 字段已剥离 |
| 输入验证 | 测试空名称、无效正则、空数组等边界情况 |
| i18n 切换 | 切换中英文，验证模态框文本和按钮文本 |

### 12.5 潜在风险点

| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| 文件写入冲突 | 多个用户同时编辑规则可能导致文件写入冲突 | 当前实现为单用户场景，暂不处理并发 |
| `_source` 字段丢失 | 如果前端未正确传递 `_source`，规则可能写入错误文件 | 使用 `rule.pop("_source", "dashboard_custom.yaml")` 提供默认值 |
| 正则表达式 DoS | 用户输入的正则表达式可能导致 ReDoS | 当前仅验证语法合法性，不评估性能 |
| 大量规则性能 | 自定义规则文件过多可能影响加载性能 | 当前实现为全量加载，暂无分页机制 |
| YAML 格式兼容性 | 不同 YAML 解析器可能有格式差异 | 使用 `pyyaml` 的 `safe_load` 和 `dump` 保持一致性 |
