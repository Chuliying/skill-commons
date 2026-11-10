#!/usr/bin/env python3
"""Build the deterministic model behind the repo visual map, and gate flow drift.

Two responsibilities, both read-only over the repository:

  model        emit the presentation model as deterministic JSON on stdout
  check-flows  assert flows.json agrees with the router prose and the registry

The model carries no wall-clock value. A build that embeds the current time
cannot be diffed against its own regeneration, which is the only cheap way to
prove a generated page still matches the repository it claims to describe.
Identity comes from the Git commit instead.
"""

from __future__ import annotations

import argparse
import hashlib
from html import escape
import json
from pathlib import Path
import re
import subprocess
import sys

MODEL_SCHEMA = "repo-visual/v1"
PAGE_PATH = Path("docs") / "repo-visual.html"
FLOWS_SCHEMA = "skill-commons/flows/v1"

# docs/work and docs/STATUS.md are excluded from the public export. Presentation
# built from them would silently bind this page to the private repository, so the
# producer refuses to carry their content rather than trusting a downstream test.
PRIVATE_MARKERS = ("docs/work/", "STATUS.md")

# Reader-facing copy for evidence-map rows whose status reached "Supported".
# Keyed by the exact question so drift against docs/evaluation.md fails closed,
# exactly like CLAIM_TODO_COPY below. A row whose evidence is already presented
# by another page section declares `covered_by` instead of table copy.
SUPPORTED_EVIDENCE_COPY = {
    "Do artifact, Plan, profile, adapter, and release contracts agree?": {
        "covered_by": "驗證",
    },
    "What is the input-token cost of loading workflow guidance?": {
        "task": "流程說明的 token 成本基線",
        "question": "回答了：載入這套工作流程，會增加多少模型輸入量？",
        "result": (
            "重跑了 8 個案例 × 3 種載入方式，共 27 個計量 session，版本與模型固定。"
            "全部預載比不載入多 17.2% 未快取輸入；先讀 router、需要才載入平均只多 "
            "0.3%，但逐案例配對看仍有約一成的中位數溢價。整段 session 的總輸入量"
            "則由回合數主導，這個樣本數比不出高下。"
        ),
        "method": (
            "每個 session 的用量紀錄與帳本都留著，包含一次有記錄的 protocol "
            "amendment。分析腳本直接讀原始紀錄，報告裡的每個數字都能重算出來。"
        ),
        "status": "已有可重播證據（2026-08-24）",
        "report": """
<h4>固定條件</h4>
<table><tbody>
<tr><td>Repo revision</td><td><code>c6015d1</code>（技能檔與 HEAD 相同）</td></tr>
<tr><td>執行模型</td><td><code>claude-haiku-4-5</code>，headless CLI，工具僅 Read／Grep／Glob（唯讀）</td></tr>
<tr><td>案例</td><td>8 個，對應歷史分類：事實查詢、micro-task 邊界、有界模糊、研究、拒絕深挖、續作、跨 session 計畫、大範圍重構計畫</td></tr>
<tr><td>三臂 payload</td><td>A 無（0 bytes）· B 全部預載 router＋brainstorming(＋references)＋plan-sync（20,509 bytes）· C 只預載 router、其餘技能放在工作區按需讀取（7,040 bytes）</td></tr>
<tr><td>Session 數</td><td>24 主要＋3 amendment＝27，成本 US$2.62，run 內無重試</td></tr>
</tbody></table>
<h4>結果（八案例，c7 用 amendment 面）</h4>
<table><thead><tr><th>臂</th><th>平均總輸入 tokens</th><th>平均未快取輸入</th><th>平均回合</th><th>平均成本 US$</th></tr></thead>
<tbody>
<tr><td>A 無 payload</td><td>325,906</td><td>17,453</td><td>10.75</td><td>0.1003</td></tr>
<tr><td>B 全部預載</td><td>316,220</td><td>20,452</td><td>10.38</td><td>0.0889</td></tr>
<tr><td>C router-first</td><td>362,384</td><td>17,506</td><td>11.50</td><td>0.0911</td></tr>
</tbody></table>
<p>未快取輸入是真正新付費的 tokens。以平均計：B 比 A 多 <strong>17.2%</strong>，C 比 A 多 0.3%，C 比 B 少 14.4%。
逐案例配對看得更細：B 高於 A 的有 7/8 個案例，預載溢價很穩；C 高於 A 的也有 6/8 個案例，
中位數約多 13%。C 的平均接近零，是被 c1 案例 A 臂的單一離群值拉平的。誠實的講法是：
按需載入仍有小幅溢價，只是明顯小於全部預載。
總輸入（含跨回合的快取重讀）則由回合數主導，單一案例落在 14 萬到 65 萬之間，8 個案例比不出方向。</p>
<h4>Protocol amendment #1</h4>
<p>主跑時 c7 的 B 臂撞到 16 回合上限，沒有產出最終答案。整個 c7 案例三臂都用 32 回合上限重跑一次，原始紀錄原封保留。
把 c7 整個案例從三臂剔除、只比其餘七個案例，方向也一樣（B 的總輸入比 A 少 9.9%），結論不依賴這次補跑。</p>
<h4>主張界線</h4>
<ul>
<li>這次重跑能說明的：在這個版本和模型下，全部預載有可量測的新輸入費用，方向與 2026-07 那份無法重播的敘事一致（當時記錄 C 比 B 省 16.6%）。</li>
<li>它不能說明的：品質或可用性、跨模型的情況、以及由回合數主導的總成本。</li>
<li>歷史的絕對數字（例如 A 平均 25,514）出自不同 harness 和不同計量定義，仍然是未驗證敘事。之後引用成本基線，以這次重跑為準。</li>
</ul>
<p>重播：在開發 repo 的 work item <code>eval-evidence-rerun</code> 裡，<code>harness/analyze_abc.py</code> 只讀 <code>artifacts/abc/</code> 的原始 session JSON 與帳本，重算上表每個數字；<code>run_abc.py</code> 和 <code>amend_c7.py</code> 可以整組重跑。</p>
""",
    },
    "Does leak-free blind scoring show a quality winner between the arms?": {
        "task": "修正後的無洩漏盲評",
        "question": "回答了：看不到分組來源的評分者，是否認為其中一種流程品質更高？",
        "result": (
            "在這八個案例裡，全部預載在評分項通過數（31/32）和偏好排名都領先。"
            "這是描述性證據，不是一般化的品質結論；而且領先的這一臂，"
            "正好也是輸入成本最高的。"
        ),
        "method": (
            "匿名答案先消毒、再凍結雜湊。每個評分 session 沒有工具、只拿到一份資料；"
            "session 會計（1 audit＋8 scorers＋1 review，無 retry）由零模型驗證器獨立"
            "確認。兩次身份洩漏都在評分開始前被擋下，紀錄完整留檔。"
        ),
        "status": "已有可重播證據（2026-08-24）",
        "report": """
<h4>協定（修正後的 1/8/1）</h4>
<p>輸入是 token 成本實驗的 24 份最終答案。每個案例把三個答案重貼成 X／Y／Z，貼法來自
私有洗牌；已知的執行路徑先換成中性字串，零模型 leak gate 再逐字掃一次身份線索。
八份資料的雜湊在任何 session 啟動前就凍結。之後依序跑：1 個 packet audit、
8 個盲評 session、零模型彙整、1 個對抗性覆核。盲評 session 沒有工具、目錄是空的、
各只拿到一份資料；標籤對應表從頭到尾不進任何 session。覆核只看它啟動前就存在的事實。
session 會計（10 個 session、1/8/1 角色、audit 先於評分、無重試）由外部的零模型驗證器
確認；歷史協定被詬病的「模型自證完成」，就移到這一步之外解決。評分模型
<code>claude-sonnet-5</code>。</p>
<h4>結果</h4>
<table><thead><tr><th>臂</th><th>評分項通過</th><th>平均偏好排名（低者佳）</th></tr></thead>
<tbody>
<tr><td>A 無 payload</td><td>29／32</td><td>2.125</td></tr>
<tr><td>B 全部預載</td><td>31／32</td><td>1.750</td></tr>
<tr><td>C router-first</td><td>28／32</td><td>2.125</td></tr>
</tbody></table>
<p>預先註冊的判定規則要求排名與通過數同時嚴格領先，結果是<strong>描述性勝者 B（全部預載）</strong>。
值得記住的一點：勝出的一臂正好是輸入成本最高的，最省的 C 臂通過數反而最低。</p>
<h4>Attempt 歷史（全數留檔、run 內無重試）</h4>
<table><thead><tr><th>Attempt</th><th>結果</th></tr></thead>
<tbody>
<tr><td>1</td><td>packet audit 抓到兩個答案引用執行環境的暫存路徑，和歷史失敗是同一種洩漏。在任何評分開始前 fail-closed 中止</td></tr>
<tr><td>2</td><td>audit 抓到消毒佔位符會自我暴露，也指出 audit 定義太寬：答案風格屬於 treatment 的內容，不算身份洩漏。改用中性替換、收斂定義後重新凍結</td></tr>
<tr><td>3</td><td>一個評分 session 死在 1 回合上限，唯一的回合花在思考。這一輪的覆核 session 也死在同一個上限；記錄到的 fail 是 harness 對非零結束的 fail-closed 預設值，不是模型判定。這次記錄為未完成</td></tr>
<tr><td>4</td><td>完成：10/10 sessions、零模型驗證器 PASS、判定如上表</td></tr>
</tbody></table>
<p>四次 attempt 合計 22 個 session，實際花費 US$2.96（帳本原記 2.67，漏了兩個失敗 session 的成本；harness 已改為失敗 session 也記帳）。盲評本身在每一次 attempt 都沒有被汙染。</p>
<h4>覆核判定與機器事實</h4>
<p>attempt 4 的對抗性覆核把一個 64 字元的凍結雜湊看成 66 字元，因此給了 fail。判定照原樣
保留。零模型驗證器重算後確認雜湊正確、與資料內容一致。這件事剛好示範了為什麼機器可驗的
事實要交給外部驗證器：模型的判定值得留下，但不能當成最終事實。</p>
<h4>主張界線</h4>
<ul>
<li>每個案例只有一個評分 session，執行與評分也只用了一種模型組合。這是描述性證據，不是一般化的品質結論。</li>
<li>盲評的「盲」指評分者無法得知分組指派。答案本身的風格差異屬於 treatment 的內容；評分者沒有對應表，無從還原。</li>
</ul>
<p>重播：work item <code>eval-evidence-rerun</code> 裡的 <code>harness/analyze_scoring.py</code> 與
<code>harness/validate_scoring.py</code> 只讀留存的 artifacts，重算並重驗上表。</p>
""",
    },
}

CLAIM_TODO_COPY = {
    "Can another tool cold-start and continue with less rework?": {
        "task": "量測不同工具接手工作的成本",
        "question": "要回答：同一工作交給另一個 AI 工具接手，是否能更快繼續、減少重做？",
        "result": (
            "可以比較接手時間、釐清次數、重工與測試結果，且兩組使用相同任務與版本。"
        ),
        "method": (
            "以相同 task 與 revision 執行 matched handoff experiment，比較接續時間、"
            "釐清次數、stale work、rework、token 與測試結果。工具已在 2026-08-24 建好，"
            "也跑完第一組配對（每臂 n=1）。接下來要在 context 較重的任務上累積多組配對。"
        ),
        "status": "pilot 已執行，待擴大樣本",
        "report": """
<h4>已完成的 pilot（2026-08-24，每臂 n=1）</h4>
<p>兩臂拿到完全相同的起點：同一個種子 repo（小型 CLI 專案，里程碑規格有三條驗收準則）、
同一個模型（<code>claude-haiku-4-5</code>）、同一組工具。流程分三步：A session 只做準則一
就停止；harness 提交後把準則二的語意改掉（合併改成絕不覆寫既有資料）、再提交一次；
接著一個全新的 B session 接手，兩臂用一字不差的 prompt、只憑 repository state 完成剩下的
工作。差別只有一處：P 臂的 A 被要求建立並維護 work-item 計畫，N 臂沒有任何持久狀態指示。
驗收由確定性腳本對最終樹執行。</p>
<table><thead><tr><th>接手 session 指標</th><th>P（協定臂）</th><th>N（對照臂）</th></tr></thead>
<tbody>
<tr><td>全部驗收（含變更後準則二）</td><td>通過</td><td>通過</td></tr>
<tr><td>釐清提問</td><td>0</td><td>0</td></tr>
<tr><td>回合數</td><td>35</td><td>21</td></tr>
<tr><td>未快取輸入 tokens</td><td>26,789</td><td>20,263</td></tr>
<tr><td>Session 成本 US$</td><td>0.240</td><td>0.158</td></tr>
</tbody></table>
<h4>觀察與界線</h4>
<ul>
<li>P 臂的前導 session 沒有照協定做滿：計畫只涵蓋自己做完的部分。接手者完成工作後，計畫也停在過期狀態沒人更新。</li>
<li>這個任務規模下，程式碼加 git 歷史就足夠冷啟動；這種情境本來就是延續性協定最沒有發揮空間的地方。每臂 n=1，不構成任何一般化結論。</li>
<li>要做出決定性的一輪，需要至少 5 組配對、context 不完全留在程式碼裡的任務，以及由真正的 bundle gate（而不是 prompt 摘錄）強制前導者遵循。主要結果預先註冊為接手驗收通過率與重工量。</li>
</ul>
<p>證據：work item <code>eval-evidence-rerun</code> 的 <code>artifacts/handoff/</code> 保存兩臂完整樹快照、
git log、diff、4 份 session 原始 JSON 與指標；4 sessions 成本 US$0.66。</p>
""",
    },
    "Does the bundle improve team throughput or human usability?": {
        "task": "量測團隊交付速度與使用感受",
        "question": "要回答：採用這套流程後，團隊是否交付更快、重工更少，也更容易使用？",
        "result": (
            "使用事先定義的週期時間、重工、錯誤率與可用性指標，"
            "完成條件相同的團隊比較。"
        ),
        "method": (
            "以預先定義的週期時間、重工、錯誤率與可用性指標完成 matched team study。"
            "研究方案已於 2026-08-24 預先註冊，待有團隊願意執行。"
        ),
        "status": "已設計研究方案，待團隊執行",
        "report": """
<h4>已預先註冊的研究方案（2026-08-24）</h4>
<p>機器實驗無法回答這一題，所以交付的是凍結的研究設計。設計是兩臂配對比較，指派單位是
team-sprint：同一個團隊在可比的 backlog 切片上各跑一個 sprint，先後順序擲幣決定並記錄
（crossover）。W 臂使用 bundle，O 臂用相同的工具基線但不裝 bundle。最少收 4 個團隊 × 2
sprints，收滿 6 個團隊或滿一季就停。</p>
<table><thead><tr><th>指標</th><th>操作型定義</th></tr></thead>
<tbody>
<tr><td>週期時間</td><td>首個引用 work item 的 commit 到 merge commit 的小時數，每 sprint 取中位數</td></tr>
<tr><td>重工率</td><td>合併後 7 天內需要補修 PR 動到相同檔案的 PR 佔比</td></tr>
<tr><td>錯誤率</td><td>合併後 14 天內對 sprint 產出立案的 bug 數／合併 PR 數</td></tr>
<tr><td>可用性</td><td>SUS 十題問卷，sprint 結束時每位參與者填答</td></tr>
<tr><td>Token 成本</td><td>每完成任務的平均模型輸入 tokens（session log）</td></tr>
</tbody></table>
<p>判定規則已凍結：W 臂要宣稱「提升交付」，週期時間中位數必須較佳，而且重工率不能劣化；
要宣稱「提升可用性」，SUS 平均差必須達到 +5。混合結果照實記錄為混合，不得事後換指標。
效度威脅也先記錄了：新工具的學習效應（用 crossover 順序隨機化緩解）、backlog 不對等
（點數差超過 30% 就作廢該配對）、志願者偏誤（結論只及於志願團隊）。</p>
<p>完整方案存於 work item <code>eval-evidence-rerun</code> 的 <code>team-study-protocol.md</code>；
任何偏離都必須在解盲前以註記修訂。</p>
""",
    },
}

# The public verification surface is discovered from tests/verify.sh, while the
# page still needs a reader-facing explanation for every discovered entry. Keep
# this map keyed by the roster's stable names so adding a test without a plain-
# language explanation fails closed during rendering.
TEST_DESCRIPTIONS = {
    "unit": "執行 tests/py/unit，驗證 factory、corpus 與 timing 等保留的測試基礎行為。",
    "integration": "執行 tests/py/integration，驗證 verify runner 與 coverage roster 等保留的契約整合。",
    "e2e": "執行 tests/py/e2e，驗證 proof-of-use 的完整公開測試流程。",
    "tests/test_artifact_contract.sh": "檢查 work-item/v3 artifact 契約、必要檔案、狀態與真實 Git workspace 邊界。",
    "tests/test_brainstorming.sh": "檢查 brainstorming 的 discovery、research/wayfinding 條件與 router、README、文件引用一致性。",
    "tests/test_export_coauthors.sh": "用 fixture repo 驗證 export-coauthors 的 trailer 收集、去重、範圍界定與排除行為。",
    "tests/test_gate_automation.sh": "用 fixture 驗證 PRD、QA、Gate 與 secret scan 等自動 gate 的通過、拒絕與 fail-closed 行為。",
    "tests/test_journey_evals.sh": "列出並執行五條 release journey，檢查 grader、workspace 與非互動 CLI 參數。",
    "tests/test_onboard_spec_contract.sh": "驗證缺少 manifest 欄位時只有一套規則：spec 先從 repo 推導 system_context，推導不足才詢問，不直接停止。",
    "tests/test_plan_sync.sh": "檢查 plan-sync skill/template 的 evidence boundary、canonical plan stage 與 decomposition contract。",
    "tests/test_profiles.sh": "檢查 profile 解析、skill membership、依賴與衝突，以及 bootstrap fan-out defaults。",
    "tests/test_project_status.sh": "用 fixtures 驗證 project-status 對 work item、bootstrap、ambiguity 與 focus 的狀態判定。",
    "tests/test_protocol_registry.sh": "檢查 protocol-registry schema、execution mode、artifact、gate 與 release evidence 契約。",
    "tests/test_release_convergence.sh": "檢查已淘汰 skill 是否移除，驗證 implement、grilling、review、sync-work 的責任收斂與 public export boundary。",
    "tests/test_repo_map.sh": "驗證 codebase-understanding 的 repo map 在 fixtures 上能建圖，並處理 root、ignore、cycle 等邊界。",
    "tests/test_repo_visual.sh": "驗證本頁的 model、flow drift、生成 parity、responsive、interaction、privacy 與 source variants。",
    "tests/test_skills_reorg.sh": "驗證 public export、generated fan-out 與文件結構的完整性。",
    "tests/test_context_budget.sh": "驗證 context budget meter、ratchet 與 lossless frontend disclosure 的結構邊界。",
    "tests/test_work_items.sh": "用 fixture 驗證 work-items metadata、stage、delivery evidence、documentation impact 與狀態檢查。",
    "tests/bootstrap/test_check.sh": "驗證 bootstrap check 在 claude-code、codex 等平台對健康狀態、directive 與 drift 的回報。",
    "tests/bootstrap/test_fanout_ignore.sh": "驗證產生的技能副本寫進 .gitignore 不提交、clone 後由 session 開始的檢查重新產生，以及舊安裝的取消追蹤提示與 uninstall。",
    "tests/bootstrap/test_generate_safety.sh": "驗證 generate 的 ownership 與 writable-path preflight 不會在相對路徑邊界卡住或誤寫。",
    "tests/bootstrap/test_manage.sh": "驗證 bootstrap manage 的專案建立、平台切換、generated tree digest 與使用者內容保留。",
    "tests/bootstrap/test_manifest.sh": "驗證 manifest 預設值、顯式 submodule path、platform parsing 與逗號轉換。",
    "tests/bootstrap/test_onboard.sh": "驗證 onboard 的平台選擇、預設 manifest、stamp 與 invalid selection 的 fail-closed 行為。",
    "tests/bootstrap/test_quick_init.sh": "驗證 README 的兩個指令安裝：HTTPS submodule 加 onboard，預設含 optional，可建立並檢查第一個工作項目。",
    "tests/bootstrap/test_platform.sh": "驗證各平台輸出格式、JSON escaping、directive body 與 warning 前置。",
    "tests/bootstrap/test_render.sh": "驗證 render block 的 fence、stamp、upsert 與既有使用者內容保留。",
    "tests/bootstrap/test_stamp.sh": "驗證 stamp 內容雜湊具 deterministic、差異可辨識，且缺檔會報錯。",
}

NON_SKILL_DIRS = {"docs", "tests", "scripts", "bootstrap", "profiles", "journey-evals", "_archive", "node_modules"}


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def frontmatter(text: str) -> dict[str, str]:
    """Parse a SKILL.md frontmatter block, folding `key: |` blocks to one line."""
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    block = text[3:end].strip("\n")
    fields: dict[str, str] = {}
    key = None
    for line in block.splitlines():
        if not line.strip():
            continue
        match = re.match(r"^([a-z_]+):\s*(.*)$", line)
        if match and not line.startswith((" ", "\t")):
            key = match.group(1)
            value = match.group(2).strip()
            fields[key] = "" if value in ("|", ">", "|-", ">-") else value
        elif key and line.startswith((" ", "\t")) and not fields.get(key):
            fields[key] = line.strip()
    return fields


def skill_dirs(root: Path) -> list[Path]:
    return sorted(
        path
        for path in root.iterdir()
        if path.is_dir()
        and not path.name.startswith(".")
        and path.name not in NON_SKILL_DIRS
        and (path / "SKILL.md").is_file()
    )


def package_dirs(root: Path) -> list[Path]:
    return sorted(
        path
        for path in root.iterdir()
        if path.is_dir()
        and not path.name.startswith(".")
        and path.name not in NON_SKILL_DIRS
        and (path / "__init__.py").is_file()
    )


def export_ignored(root: Path, paths: list[str]) -> set[str]:
    """Return paths marked ``export-ignore`` by the worktree attributes."""
    if not paths:
        return set()
    attrs = subprocess.run(
        ["git", "check-attr", "export-ignore", "--", *paths],
        cwd=root,
        capture_output=True,
        text=True,
    )
    if attrs.returncode != 0:
        raise SystemExit(f"git check-attr export-ignore failed: {attrs.stderr.strip()}")
    ignored: set[str] = set()
    for line in attrs.stdout.splitlines():
        path, _, value = line.rpartition(": export-ignore: ")
        if value == "set":
            ignored.add(path)
    return ignored


def resolve_profile(root: Path, name: str, depth: int = 0) -> list[str]:
    """Resolve one profiles/<name> file, following `@other` includes."""
    if depth > 3:
        raise SystemExit(f"profile include depth exceeded at {name}")
    path = root / "profiles" / name
    if not path.is_file():
        raise SystemExit(f"profile file missing: profiles/{name}")
    names: list[str] = []
    for line in read(path).splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("@"):
            names.extend(resolve_profile(root, line[1:], depth + 1))
        else:
            names.append(line)
    return names


def evidence_map(root: Path) -> list[dict[str, str]]:
    """Extract the `## Evidence map` table from docs/evaluation.md."""
    text = read(root / "docs" / "evaluation.md")
    section = re.search(r"^## Evidence map\s*$(.*?)(?=^## )", text, re.MULTILINE | re.DOTALL)
    if not section:
        raise SystemExit("docs/evaluation.md has no `## Evidence map` section")
    rows: list[dict[str, str]] = []
    for line in section.group(1).splitlines():
        line = line.strip()
        if not line.startswith("|") or set(line) <= set("|-: "):
            continue
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) != 3 or cells[0].lower() == "question":
            continue
        row = {"question": cells[0], "evidence": cells[1], "status": cells[2]}
        for value in row.values():
            for marker in PRIVATE_MARKERS:
                if marker in value:
                    raise SystemExit(
                        f"evidence map row carries private reference `{marker}`: {value}"
                    )
        rows.append(row)
    if not rows:
        raise SystemExit("docs/evaluation.md evidence map is empty")
    return rows


def supported_evidence(evidence: list[dict[str, str]]) -> list[dict[str, str]]:
    """Turn supported evidence-map rows into reader-facing result rows.

    Every supported row must have copy (or an explicit `covered_by` pointer to
    the page section that already presents it); a supported row without copy,
    or copy for a question the map no longer supports, fails the build.
    """
    questions = [
        row["question"]
        for row in evidence
        if row["status"].lower().startswith("supported")
    ]
    missing = sorted(set(questions) - set(SUPPORTED_EVIDENCE_COPY))
    stale = sorted(set(SUPPORTED_EVIDENCE_COPY) - set(questions))
    if missing or stale:
        details = []
        if missing:
            details.append(f"missing copy for: {', '.join(missing)}")
        if stale:
            details.append(f"stale copy for: {', '.join(stale)}")
        raise SystemExit(
            "supported evidence copy drifted from docs/evaluation.md ("
            + "; ".join(details) + ")"
        )
    return [
        SUPPORTED_EVIDENCE_COPY[question]
        for question in questions
        if "covered_by" not in SUPPORTED_EVIDENCE_COPY[question]
    ]


def claim_todos(claim_limits: list[dict[str, str]]) -> list[dict[str, str]]:
    """Turn unresolved evidence claims into a fail-closed action list."""
    questions = [row["question"] for row in claim_limits]
    missing = sorted(set(questions) - set(CLAIM_TODO_COPY))
    stale = sorted(set(CLAIM_TODO_COPY) - set(questions))
    if missing or stale:
        details = []
        if missing:
            details.append(f"missing copy for: {', '.join(missing)}")
        if stale:
            details.append(f"stale copy for: {', '.join(stale)}")
        raise SystemExit("claim todo copy drifted from docs/evaluation.md (" + "; ".join(details) + ")")
    return [CLAIM_TODO_COPY[question] for question in questions]


def roster(root: Path) -> list[dict[str, str]]:
    result = subprocess.run(
        ["bash", "tests/verify.sh", "--list"],
        cwd=root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"verify.sh --list failed: {result.stderr.strip()}")
    entries: list[dict[str, str]] = []
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        entries.append({"kind": parts[0], "name": parts[1]})
    if not entries:
        raise SystemExit("verify.sh --list returned an empty roster")

    # This generated page ships in the public payload. The private source tree
    # discovers maintainer-only suites too, but embedding them would make the
    # exported page name files that do not exist and fail its own regeneration.
    # Ask Git for the one authoritative public/private boundary instead of
    # duplicating the export-ignore roster here.
    suites = [entry["name"] for entry in entries if entry["kind"] == "suite"]
    ignored = export_ignored(root, suites)
    public_entries = [
        entry
        for entry in entries
        if entry["kind"] != "suite" or entry["name"] not in ignored
    ]
    if not public_entries:
        raise SystemExit("public verify roster is empty after export-ignore filtering")
    return public_entries


def content_digest(payload: dict) -> str:
    """Stable identity for the described contracts, independent of the checkout."""
    canonical = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]


def applicable_gates(registry: dict, installed: set[str]) -> list[str]:
    """Derive the human decisions that can occur with one delivery bundle.

    An execution mode is available only when every required artifact has at
    least one installed producer.  Optional and absent artifacts do not make a
    mode unavailable.  Gate applicability is the union across the modes that
    remain possible; this keeps profile semantics in the machine model instead
    of teaching the renderer special cases such as ``personal``.
    """
    gates: set[str] = set()
    for mode in registry.get("execution_modes", {}).values():
        required = (
            artifact
            for artifact in mode.get("artifacts", {}).values()
            if artifact.get("requirement") == "required"
        )
        if all(
            any(producer in installed for producer in artifact.get("producers", []))
            for artifact in required
        ):
            gates.update(mode.get("human_gates", []))
    return sorted(gates)


def build_model(root: Path) -> dict:
    registry = json.loads(read(root / "protocol-registry.json"))
    profiles_config = json.loads(read(root / "profiles.json"))
    lock = json.loads(read(root / "skills-lock.json")).get("skills", {})
    flows = json.loads(read(root / "flows.json"))

    profile_names = sorted(registry.get("profiles", {}))
    membership = {name: sorted(set(resolve_profile(root, name))) for name in profile_names}

    skills = []
    for path in skill_dirs(root):
        name = path.name
        fields = frontmatter(read(path / "SKILL.md"))
        upstream = lock.get(name)
        skills.append(
            {
                "name": name,
                "path": f"{name}/SKILL.md",
                "intent": fields.get("description", "").strip(),
                "stage": fields.get("stage", ""),
                "output": fields.get("output", ""),
                "source_kind": fields.get("source_kind", ""),
                "maturity": fields.get("maturity", "stable"),
                # Two independent provenance channels: `skills-lock.json` covers the
                # npx-managed vendored set, while an adapted skill records its origin
                # in its own frontmatter. Reading only the lock silently drops the
                # second group, so both are carried and neither is inferred.
                "provenance": {
                    "lock": (
                        {
                            "source": upstream.get("source", ""),
                            "hash": upstream.get("computedHash", ""),
                        }
                        if upstream
                        else None
                    ),
                    "declared_source": fields.get("source", ""),
                },
                "profiles": sorted(p for p in profile_names if name in membership[p]),
            }
        )

    package_paths = [f"{path.name}/__init__.py" for path in package_dirs(root)]
    ignored_packages = export_ignored(root, package_paths)
    packages = [
        {
            "name": path.name,
            "path": f"{path.name}/__init__.py",
            "modules": len(sorted(path.glob("*.py"))),
        }
        for path in package_dirs(root)
        if f"{path.name}/__init__.py" not in ignored_packages
    ]

    evidence = evidence_map(root)
    profiles = {}
    for name in profile_names:
        kind = registry["profiles"][name].get("kind", "")
        profile = {
            "kind": kind,
            "requires": registry["profiles"][name].get("requires", []),
            "conflicts": registry["profiles"][name].get("conflicts", []),
            "file": f"profiles/{name}",
            "skills": membership[name],
        }
        # A capability pack is not an executable bundle on its own, so applying
        # a gate verdict to it would invent semantics the registry does not own.
        if kind == "delivery-mode":
            profile["applicable_gates"] = applicable_gates(
                registry, set(membership[name])
            )
        profiles[name] = profile

    test_roster = roster(root)
    for entry in test_roster:
        description = TEST_DESCRIPTIONS.get(entry["name"])
        if not description:
            raise SystemExit(
                "missing reader-facing description for verification entry "
                f"`{entry['name']}`"
            )
        entry["description"] = description

    model = {
        "schema_version": MODEL_SCHEMA,
        "identity": {
            "registry_schema": registry.get("schema_version", ""),
            "profiles_schema": profiles_config.get("schema_version", ""),
            "flows_schema": flows.get("schema_version", ""),
            "work_item_schema": registry.get("work_item", {}).get("schema_version", ""),
        },
        "non_goals": registry.get("non_goals", []),
        "skills": skills,
        "packages": packages,
        "profiles": profiles,
        "platforms": profiles_config.get("platforms", {}),
        "execution_modes": registry.get("execution_modes", {}),
        "work_item": registry.get("work_item", {}),
        "flows": flows.get("flows", []),
        "human_gates": flows.get("human_gates", []),
        "tests": {"roster": test_roster, "runner": "tests/verify.sh"},
        "evidence_map": evidence,
        "claim_limits": [
            row for row in evidence if not row["status"].lower().startswith("supported")
        ],
    }
    described = {key: value for key, value in model.items() if key != "identity"}
    model["identity"]["content_digest"] = content_digest(described)
    return model


def check_flows(root: Path, router_path: Path, flows_path: Path) -> list[str]:
    errors: list[str] = []
    flows = json.loads(read(flows_path))
    registry = json.loads(read(root / "protocol-registry.json"))
    router = read(router_path)

    if flows.get("schema_version") != FLOWS_SCHEMA:
        errors.append(f"flows schema must be {FLOWS_SCHEMA}")

    declared = sorted(flow.get("router_heading", "") for flow in flows.get("flows", []))
    in_router = sorted(re.findall(r"^## Flow: (\S+)\s*$", router, re.MULTILINE))
    if declared != in_router:
        errors.append(
            f"flow headings disagree: flows.json={declared} router={in_router}"
        )

    registry_gates = sorted(
        {
            gate
            for mode in registry.get("execution_modes", {}).values()
            for gate in mode.get("human_gates", [])
        }
    )
    declared_gates = sorted(gate.get("id", "") for gate in flows.get("human_gates", []))
    if declared_gates != registry_gates:
        errors.append(
            f"human gates disagree: flows.json={declared_gates} registry={registry_gates}"
        )
    for gate in flows.get("human_gates", []):
        label = gate.get("router_label", "")
        if label and label not in router:
            errors.append(f"router does not present human gate label `{label}`")

    known_skills = {path.name for path in skill_dirs(root)}
    known_modes = set(registry.get("execution_modes", {}))
    for flow in flows.get("flows", []):
        for variant in flow.get("variants", []):
            mode = variant.get("execution_mode")
            if mode is not None and mode not in known_modes:
                errors.append(
                    f"{flow.get('id')}/{variant.get('id')} names unknown execution mode `{mode}`"
                )
            node_ids = set()
            for node in variant.get("nodes", []):
                node_ids.add(node.get("id", ""))
                if node.get("kind") == "skill" and node.get("ref") not in known_skills:
                    errors.append(
                        f"{flow.get('id')}/{variant.get('id')} references missing skill `{node.get('ref')}`"
                    )
                if node.get("kind") == "gate" and node.get("ref") not in registry_gates:
                    errors.append(
                        f"{flow.get('id')}/{variant.get('id')} references unknown gate `{node.get('ref')}`"
                    )
            for edge in variant.get("edges", []):
                for end in ("from", "to"):
                    if edge.get(end) not in node_ids:
                        errors.append(
                            f"{flow.get('id')}/{variant.get('id')} edge {end} `{edge.get(end)}` is not a declared node"
                        )
    return errors


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

PAGE_RELATIVE_PREFIX = ".."  # the page lives in docs/, repo files are one level up

# The hero is the one image that has to land in fifteen seconds: a delivery
# pipeline where the three human decisions are shaped differently from every
# machine-checked step.
HERO_STEPS = [
    ("rect", "意圖", "router 選最短路徑", "skill-router"),
    ("gate", "PRD 核可", "人工", "prd"),
    ("rect", "設計", "spec / prototype", "spec"),
    ("gate", "team 設計核可", "人工", "team-design"),
    ("rect", "計畫", "canonical plan", "plan-sync"),
    ("rect", "實作", "RED → GREEN", "implement"),
    ("rect", "驗證", "機器 Gate + 證據", "verification-before-completion"),
    ("gate", "發布核可", "人工", "release"),
    ("rect", "交付", "授權後才動 Git", "sync-work"),
]


def hero_svg() -> str:
    """Deterministic inline SVG. No layout library, no external asset."""
    pad, gap, top = 18, 30, 34
    rect_w, gate_w, height = 152, 82, 56
    x = pad
    shapes: list[str] = []
    arrows: list[str] = []
    previous_right: float | None = None
    for kind, label, hint, target in HERO_STEPS:
        width = gate_w if kind == "gate" else rect_w
        centre_x = x + width / 2
        centre_y = top + height / 2
        if previous_right is not None:
            arrows.append(
                f'<line class="edge" x1="{previous_right}" y1="{centre_y}" '
                f'x2="{x - 6}" y2="{centre_y}" marker-end="url(#arrow)"/>'
            )
        if kind == "gate":
            half = height / 2
            points = (
                f"{centre_x},{top} {x + width},{centre_y} "
                f"{centre_x},{top + height} {x},{centre_y}"
            )
            shapes.append(
                f'<g class="node gate" data-gate="{target}" role="button" tabindex="0" '
                f'aria-label="{escape(label)}">'
                f'<polygon points="{points}"/>'
                f'<text class="glyph" x="{centre_x}" y="{centre_y + 5}">人</text>'
                f'<text class="cap" x="{centre_x}" y="{top + height + 23}">{escape(label)}</text>'
                f'<text class="gate-na-label" x="{centre_x}" y="{top + height + 42}">不適用</text>'
                f"</g>"
            )
            del half
        else:
            shapes.append(
                f'<g class="node step" data-skill="{target}" role="button" tabindex="0">'
                f'<rect x="{x}" y="{top}" width="{width}" height="{height}" rx="7"/>'
                f'<text class="lbl" x="{centre_x}" y="{centre_y - 4}">{escape(label)}</text>'
                f'<text class="sub" x="{centre_x}" y="{centre_y + 16}">{escape(hint)}</text>'
                f"</g>"
            )
        previous_right = x + width
        x += width + gap
    total = x - gap + pad
    return (
        f'<svg class="hero" viewBox="0 0 {total} 150" role="img" '
        f'aria-label="交付流水線與三個人工判斷點">'
        '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" '
        'markerWidth="6" markerHeight="6" orient="auto-start-reverse">'
        '<path d="M0,1 L9,5 L0,9 z"/></marker></defs>'
        + "".join(arrows)
        + "".join(shapes)
        + "</svg>"
    )


CSS = """
:root{
  /* Four steps, nothing else: page title, section/card title, body, note. */
  --fs-h1:28px; --fs-title:18px; --fs-body:16px; --fs-note:14px;
  --bg:#fbfbf9; --panel:#ffffff; --panel-2:#f0f0ea; --line:#c6c6b9;
  --ink:#0b0c06; --muted:#2b2e24; --dim:#43463b;
  --accent:#1f4527; --accent-soft:#e2ece3;
  --human:#6b3708; --human-soft:#f4e5d4;
  --warn:#6e2020; --warn-soft:#f6e0dd;
  --build-bg:#080d0a; --build-panel:#121d16; --build-line:#405148;
  --build-ink:#f3f8f3; --build-muted:#b9c8bc; --build-accent:#a6e0b5;
  --build-gate:#f4c286; --build-gate-soft:#352516;
  --mono:ui-monospace,SFMono-Regular,Menlo,monospace;
  --sans:system-ui,-apple-system,"Helvetica Neue",sans-serif;
}
@media (prefers-color-scheme:dark){
  :root{
    --bg:#0f1110; --panel:#181b19; --panel-2:#212621; --line:#454d46;
    --ink:#f8faf6; --muted:#e0e5db; --dim:#bcc2b6;
    --accent:#a6e0b5; --accent-soft:#1d2c22;
    --human:#f4c286; --human-soft:#33281a;
    --warn:#f5a79e; --warn-soft:#33201f;
  }
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);
  font-size:var(--fs-body);line-height:1.65;-webkit-font-smoothing:antialiased}
a{color:var(--accent)}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
code,.mono{font-family:var(--mono);font-size:.92em}
.wrap{max-width:1180px;margin:0 auto;padding:40px 22px 100px}
header h1{margin:0 0 10px;font-size:var(--fs-h1);letter-spacing:-.012em}
header p.lede{margin:0;color:var(--ink);max-width:66ch}
h2{font-size:var(--fs-title);letter-spacing:.01em;color:var(--ink);
  margin:48px 0 16px;font-weight:650;scroll-margin-top:84px}
h2:first-of-type{margin-top:0}
.mode-guide{margin:30px 0 22px}
.mode-guide h2{margin-bottom:12px}
.mode-cards{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:11px}
.mode-card{background:var(--panel);border:1px solid var(--line);border-radius:10px;
  padding:15px 17px}
.mode-card h3{margin:0 0 6px;font-size:var(--fs-title)}
.mode-card p{margin:0;color:var(--ink)}
.mode-card code{color:var(--accent)}
.mode-note{color:var(--muted);font-size:var(--fs-note);margin:10px 0 0;max-width:82ch}
.cards{display:grid;gap:13px;grid-template-columns:repeat(auto-fit,minmax(252px,1fr))}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px 17px}
.card h3{margin:0 0 7px;font-size:var(--fs-title)}
.card p{margin:0;color:var(--ink)}
.scroll{overflow-x:auto;background:var(--panel);border:1px solid var(--line);
  border-radius:10px;padding:10px 4px 4px}
svg.hero{display:block;min-width:1240px;width:100%;height:auto}
svg.hero .edge{stroke:var(--dim);stroke-width:1.5}
svg.hero marker path{fill:var(--dim)}
svg.hero .node{cursor:pointer}
svg.hero .step rect{fill:var(--panel-2);stroke:var(--line);stroke-width:1.4}
svg.hero .node:hover rect,svg.hero .node:focus rect{stroke:var(--accent);stroke-width:2.2}
svg.hero .gate polygon{fill:var(--human-soft);stroke:var(--human);stroke-width:2}
svg.hero .node:hover polygon,svg.hero .node:focus polygon{stroke-width:3}
svg.hero text{text-anchor:middle;font-family:var(--sans)}
svg.hero .lbl{font-size:var(--fs-body);fill:var(--ink)}
svg.hero .sub{font-size:var(--fs-note);fill:var(--muted)}
svg.hero .glyph{font-size:var(--fs-title);fill:var(--human);font-weight:700}
svg.hero .cap{font-size:var(--fs-note);fill:var(--human);font-weight:600}
svg.hero .gate-na-label{display:none;font-size:var(--fs-note);fill:var(--muted);font-weight:650}
svg.hero .gate[data-na=true] polygon{fill:var(--panel-2);stroke:var(--muted);stroke-dasharray:4 3}
svg.hero .gate[data-na=true] .glyph,svg.hero .gate[data-na=true] .cap{fill:var(--muted)}
svg.hero .gate[data-na=true] .gate-na-label{display:block}
.legend{display:flex;gap:22px;flex-wrap:wrap;font-size:var(--fs-note);color:var(--ink);
  margin:13px 2px 0}
.legend i{display:inline-block;width:12px;height:12px;margin-right:7px;vertical-align:-1px}
.legend i.m{background:var(--panel-2);border:1px solid var(--line)}
.legend i.h{background:var(--human-soft);border:1px solid var(--human);transform:rotate(45deg)}
.flow{background:var(--panel);border:1px solid var(--line);border-radius:10px;
  padding:15px 17px;margin-bottom:11px}
.flow h3{margin:0 0 4px;font-size:var(--fs-title)}
.flow p.intent{margin:0 0 12px;color:var(--muted);font-size:var(--fs-note)}
.variant{display:grid;grid-template-columns:160px 32px minmax(0,1fr);align-items:stretch;
  gap:0;margin:9px 0}
.variant-name{min-width:0;padding-right:8px}
.variant-separator{align-self:stretch;width:1px;margin-inline:16px;background:var(--line)}
.variant .vname{display:inline-block;font-family:var(--mono);font-size:var(--fs-note);color:var(--muted);
  min-width:152px;justify-self:start;white-space:nowrap}
.variant-flow{display:flex;flex-wrap:wrap;align-items:center;gap:7px;min-width:0}
.variant-flow .chip{max-width:100%;overflow-wrap:anywhere}
.chip{border:1px solid var(--line);background:var(--panel-2);border-radius:6px;
  padding:4px 10px;font-size:var(--fs-body);cursor:pointer;color:var(--ink)}
.chip:hover{border-color:var(--accent)}
.chip.gate{background:var(--human-soft);border-color:var(--human);color:var(--human);
  font-weight:600}
.chip.handoff{background:transparent;border-style:dashed;color:var(--muted);cursor:default}
.arrow{color:var(--muted)}
.flow.build-flow{background:var(--build-bg);color:var(--build-ink)}
.flow.build-flow .variant .vname.chip{background:#000;border-color:#fff;color:#fff}
.flow.build-flow p.intent,.flow.build-flow .vname,.flow.build-flow .arrow{color:var(--build-muted)}
.flow.build-flow .variant-separator{background:var(--build-line)}
.flow.build-flow .chip{background:var(--build-panel);border-color:var(--build-line);color:var(--build-ink)}
.flow.build-flow .chip:hover{border-color:var(--build-accent)}
.flow.build-flow .chip.gate{background:var(--build-gate-soft);border-color:var(--build-gate);
  color:var(--build-gate)}
.flow.build-flow .chip.handoff{background:transparent;color:var(--build-muted)}
.filters{position:sticky;top:0;z-index:5;display:flex;gap:8px;flex-wrap:wrap;overflow-x:auto;
  align-items:center;background:var(--bg);border-bottom:1px solid var(--line);
  padding:11px 0;margin:0 0 30px}
.filters .lenslabel{font-size:var(--fs-note);color:var(--muted);margin-right:2px;
  flex:0 0 auto;white-space:nowrap}
.filters button{border:1px solid var(--line);background:var(--panel);color:var(--ink);
  border-radius:999px;padding:5px 14px;font-size:var(--fs-note);cursor:pointer;
  font-family:var(--sans);flex:0 0 auto;white-space:nowrap}
.filters button[aria-pressed=true]{background:var(--accent-soft);border-color:var(--accent);
  color:var(--accent);font-weight:650}
/* Out of the selected bundle. Marked, never removed: dropping a chip out of a
   flow chain would leave dangling arrows and misreport the flow, and hiding it
   from the catalogue hides exactly the boundary the reader needs to learn. */
[data-out=true]{opacity:.42}
[data-out=true]:not(.chip.gate){border-style:dashed}
.stage [data-out=true]::after{content:"·未安裝";color:var(--muted);font-size:var(--fs-note)}
svg.hero .node[data-out=true] rect{stroke-dasharray:4 3}
/* Human decisions remain visible and clickable even when no execution mode in
   the selected delivery bundle can reach them.  This is a separate state from
   an uninstalled skill: the gate is part of the protocol, but not this route. */
[data-gate][data-na=true]{opacity:.5}
.chip.gate[data-na=true]{border-style:dashed;background:var(--panel-2);color:var(--muted)}
.chip.gate[data-na=true]::after{content:" · 不適用";font-size:var(--fs-note)}
.stagegrid{display:grid;gap:11px;grid-template-columns:repeat(auto-fit,minmax(284px,1fr))}
.stage{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px 15px}
.stage h4{margin:0 0 10px;font-size:var(--fs-note);text-transform:uppercase;
  letter-spacing:.07em;color:var(--muted)}
.stage .chip{margin:0 5px 5px 0;display:inline-block}
.chip .ext{color:var(--muted);font-size:var(--fs-note);margin-left:4px}
table{border-collapse:collapse;width:100%;font-size:var(--fs-body);background:var(--panel);
  font-variant-numeric:tabular-nums}
th,td{border:1px solid var(--line);padding:9px 11px;text-align:left;vertical-align:top}
th{background:var(--panel-2);color:var(--ink);font-weight:650;font-size:var(--fs-note)}
td.req{font-family:var(--mono)}
td.req[data-v=required]{color:var(--accent);font-weight:650}
td.req[data-v=optional]{color:var(--ink)}
td.req[data-v=absent]{color:var(--muted);background:var(--panel-2)}
tr.limit td{background:var(--warn-soft)}
tr.limit td:last-child{color:var(--warn);font-weight:650}
.note{color:var(--muted);font-size:var(--fs-note);margin:12px 0 0;max-width:82ch}
.rosterwrap{display:grid;gap:11px;grid-template-columns:minmax(0,1fr)}
.test-table-wrap{overflow:visible;background:var(--panel);border:1px solid var(--line);
  border-radius:8px;padding:0}
.test-table{min-width:0;table-layout:fixed}
.test-table th:first-child,.test-table td:first-child{width:32%;white-space:normal;overflow-wrap:anywhere}
.test-table td:last-child{color:var(--muted)}
.engineering-details{margin-top:48px;background:var(--panel);border:1px solid var(--line);
  border-radius:10px;overflow:hidden}
.engineering-details>summary{display:flex;align-items:center;justify-content:space-between;
  gap:16px;cursor:pointer;padding:16px 17px;list-style:none}
.engineering-details>summary::-webkit-details-marker{display:none}
.engineering-details>summary strong{display:block;font-size:var(--fs-title)}
.engineering-details>summary small{display:block;color:var(--muted);font-size:var(--fs-note);
  font-weight:400}
.engineering-details>summary::after{content:"展開";color:var(--accent);font-size:var(--fs-note);
  font-weight:650;flex:0 0 auto}
.engineering-details[open]>summary::after{content:"收合"}
.engineering-body{border-top:1px solid var(--line);padding:0 17px 18px}
.engineering-body>h2:first-of-type{margin-top:24px}
.technical-stance{border-left:3px solid var(--accent);padding-left:13px}
.followups{margin-top:40px;scroll-margin-top:84px}
.todo-baseline{margin:0 0 14px;max-width:86ch}
.todo-table-wrap{overflow-x:auto;background:var(--panel);border:1px solid var(--line);
  border-radius:10px;padding:0;-webkit-overflow-scrolling:touch}
.todo-table{min-width:940px}
.todo-table th{white-space:nowrap}
.todo-table tr.limit td{background:var(--panel)}
.todo-table td.todo-task{min-width:220px}
.todo-table td.todo-result{min-width:280px}
.todo-table td.todo-method-cell{min-width:320px}
.todo-table td.todo-status{color:var(--muted);font-weight:650;white-space:nowrap}
.todo-table .todo-task strong{display:block;font-size:var(--fs-title);margin-bottom:5px}
.todo-table .todo-question{margin:0;color:var(--muted)}
.todo-table .todo-method{margin:0}
.todo-table .todo-method p{margin:0;color:var(--muted);font-size:var(--fs-note);max-width:60ch}
.done-table tr.done td{background:var(--panel)}
.done-table td.done-task{min-width:220px}
.done-table td.done-result{min-width:300px}
.done-table td.done-method-cell{min-width:320px}
.done-table td.done-status{color:var(--accent);font-weight:650;white-space:nowrap}
.done-table .done-task strong{display:block;font-size:var(--fs-title);margin-bottom:5px}
.done-table .done-question{margin:0;color:var(--muted)}
.done-table .done-method{margin:0;color:var(--muted);font-size:var(--fs-note);max-width:60ch}
/* Child selector on purpose: the wrapper cell drops its padding (the details
   box carries its own), while td inside the embedded report tables keep the
   page-wide 9px 11px cell padding. */
tr.report-row > td{background:var(--panel-2);padding:0}
/* The report lives in a 940px-min table whose wrapper scrolls sideways on
   narrow screens. Pinning the details box to the wrapper's left edge and
   capping it at the viewport keeps prose readable without horizontal reading. */
.row-report{position:sticky;left:0;max-width:calc(100vw - 72px)}
.row-report summary{cursor:pointer;color:var(--accent);font-weight:650;
  font-size:var(--fs-note);padding:9px 11px;list-style:none}
.row-report summary::-webkit-details-marker{display:none}
.row-report summary::before{content:"▸ "}
.row-report[open] summary::before{content:"▾ "}
.report-body{padding:2px 11px 16px;font-size:var(--fs-note);color:var(--muted)}
.report-body h4{margin:14px 0 6px;color:var(--ink)}
.report-body p,.report-body li{max-width:86ch;white-space:normal}
.report-body ul{margin:6px 0;padding-left:20px}
.report-body table{margin:6px 0;min-width:0}
.report-body td,.report-body th{white-space:normal}
dialog.detail{max-width:700px;width:calc(100% - 40px);max-height:82vh;overflow-y:auto;
  background:var(--panel);color:var(--ink);border:1px solid var(--line);border-radius:12px;
  padding:28px 28px 34px;box-shadow:0 24px 60px rgba(0,0,0,.24)}
dialog.detail::backdrop{background:rgba(8,10,8,.58)}
dialog.detail .close{position:absolute;top:15px;right:17px;border:1px solid var(--line);
  background:var(--panel-2);color:var(--ink);border-radius:6px;cursor:pointer;
  font-size:var(--fs-note);padding:4px 11px;font-family:var(--sans)}
dialog.detail h3{margin:0 78px 5px 0;font-size:var(--fs-title)}
dialog.detail .kind{font-family:var(--mono);font-size:var(--fs-note);color:var(--muted);
  margin-bottom:15px}
dialog.detail p{margin:0 0 15px}
dialog.detail dl{margin:0 0 16px;display:grid;grid-template-columns:116px 1fr;gap:9px 13px}
dialog.detail dt{color:var(--muted);font-size:var(--fs-note);padding-top:2px}
dialog.detail dd{margin:0}
dialog.detail details{border-top:1px solid var(--line);padding-top:14px;margin-top:6px}
dialog.detail summary{cursor:pointer;color:var(--accent);font-weight:600}
dialog.detail table{margin-top:12px}
dialog.detail .src{display:inline-block;margin-top:15px}
footer{margin-top:56px;border-top:1px solid var(--line);padding-top:18px;
  color:var(--muted);font-size:var(--fs-note)}
@media (max-width:640px){
  .wrap{padding-left:16px;padding-right:16px}
  .mode-cards{grid-template-columns:minmax(0,1fr)}
  .filters{flex-wrap:nowrap;margin-left:-16px;margin-right:-16px;padding-left:16px;padding-right:16px}
  .variant{grid-template-columns:minmax(0,1fr);gap:7px}
  .variant-name{padding:0}
  .variant-separator{width:auto;height:1px;margin-inline:16px}
  .variant .vname{min-width:0;max-width:100%;width:max-content}
  .engineering-details>summary{align-items:flex-start}
  .test-table{min-width:0}
  .test-table th:first-child,.test-table td:first-child{width:42%}
  .todo-table{min-width:940px}
  .followups{margin-top:32px}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
"""

JS = """
const MODEL = JSON.parse(document.getElementById('model').textContent);
const byName = {};
MODEL.skills.forEach(s => { byName[s.name] = s; });
const gateById = {};
MODEL.human_gates.forEach(g => { gateById[g.id] = g; });
const dialog = document.querySelector('dialog.detail');
const body = document.getElementById('detail-body');

function esc(v){ const d = document.createElement('div'); d.textContent = v == null ? '' : v; return d.innerHTML; }
function row(k, v){ return v ? '<dt>' + esc(k) + '</dt><dd>' + v + '</dd>' : ''; }

function openDetail(html){
  body.innerHTML = html;
  if (!dialog.open) dialog.showModal();
  dialog.scrollTop = 0;
}
/*SOURCE_FN*/
function closeDetail(){ if (dialog.open) dialog.close(); }
// The dialog element is the only hit area outside the content box, so a click
// landing on it is a backdrop click.
dialog.addEventListener('click', event => { if (event.target === dialog) closeDetail(); });

function skillPanel(name){
  const s = byName[name];
  if (!s) return;
  const prov = s.provenance.lock
    ? esc(s.provenance.lock.source) + '<br><span class="mono">' + esc(s.provenance.lock.hash.slice(0,16)) + '…</span>'
    : (s.provenance.declared_source ? '<span class="mono">' + esc(s.provenance.declared_source) + '</span>' : '');
  const tests = MODEL.tests.roster
    .filter(t => t.name.indexOf(name.replace(/-/g,'_')) !== -1)
    .map(t => '<code>' + esc(t.name) + '</code>').join(' ');
  openDetail(
    '<h3>' + esc(s.name) + '</h3>' +
    '<div class="kind">skill · stage ' + esc(s.stage || '未標') + '</div>' +
    '<p>' + esc(s.intent) + '</p>' +
    '<dl>' +
      row('輸出', s.output ? '<code>' + esc(s.output) + '</code>' : '<span style="color:var(--dim)">無 artifact</span>') +
      row('profile', s.profiles.length ? s.profiles.map(p => '<code>' + esc(p) + '</code>').join(' ') : '<span style="color:var(--dim)">不在任何 consuming profile（maintainer 工具）</span>') +
      row('成熟度', esc(s.maturity)) +
    '</dl>' +
    '<details><summary>細節</summary>' +
      '<dl style="margin-top:12px">' +
        row('source_kind', '<code>' + esc(s.source_kind || 'original') + '</code>') +
        row('provenance', prov || '<span style="color:var(--dim)">原生，無上游</span>') +
        row('相關測試', tests || '<span style="color:var(--dim)">無以此技能命名的 suite</span>') +
      '</dl>' +
    '</details>' +
    source(s.path)
  );
}

function gatePanel(id, handle){
  const g = gateById[id];
  if (!g) return;
  const modes = Object.keys(MODEL.execution_modes).sort()
    .filter(m => MODEL.execution_modes[m].human_gates.indexOf(id) !== -1);
  const lensNote = handle && handle.dataset.na === 'true'
    ? '<p class="note">目前選定的 delivery bundle 不會觸發這個判斷點；保留節點是為了讓流程邊界可見。</p>'
    : '';
  openDetail(
    '<h3>' + esc(g.label) + '</h3>' +
    '<div class="kind">human decision · gate ' + esc(g.id) + '</div>' +
    '<p>' + esc(g.decides) + '</p>' +
    '<dl>' +
      row('router 呈現', '<code>' + esc(g.router_label) + '</code>') +
      row('適用模式', modes.map(m => '<code>' + esc(m) + '</code>').join(' ')) +
    '</dl>' +
    lensNote +
    '<details><summary>細節</summary><p class="note" style="margin-top:12px">' +
      '人工判斷點恰好三個，其餘一律機器檢查。核可是檔案上的狀態轉移（awaiting-approval → approved），不是對話裡的承諾。' +
    '</p></details>' +
    source('skill-router/SKILL.md')
  );
}

function modePanel(name){
  const m = MODEL.execution_modes[name];
  if (!m) return;
  const arts = Object.keys(m.artifacts).sort().map(a => {
    const entry = m.artifacts[a];
    const who = entry.producers.length ? entry.producers.join(', ') : '—';
    return '<tr><td><code>' + esc(a) + '</code></td><td class="req" data-v="' + esc(entry.requirement) + '">'
      + esc(entry.requirement) + '</td><td>' + esc(who) + '</td></tr>';
  }).join('');
  openDetail(
    '<h3>' + esc(name) + '</h3>' +
    '<div class="kind">execution mode · flow ' + esc(m.flow) + '</div>' +
    '<dl>' +
      row('人工判斷點', m.human_gates.map(g => '<code>' + esc(g) + '</code>').join(' ')) +
      row('交接', '<code>' + esc(m.handoff) + '</code>') +
    '</dl>' +
    '<details open><summary>artifact 契約</summary>' +
      '<table style="margin-top:10px"><thead><tr><th>artifact</th><th>要求</th><th>producer</th></tr></thead><tbody>'
      + arts + '</tbody></table>' +
      '<p class="note"><code>absent</code> 不是「還沒做」，是這條路徑不產該 artifact；補造它就是違約。</p>' +
    '</details>' +
    source('protocol-registry.json')
  );
}

document.addEventListener('click', event => {
  const target = event.target.closest('[data-skill],[data-gate],[data-mode],.close');
  if (!target) return;
  if (target.classList.contains('close')) { closeDetail(); return; }
  if (target.dataset.skill) { skillPanel(target.dataset.skill); return; }
  if (target.dataset.gate) { gatePanel(target.dataset.gate, target); return; }
  if (target.dataset.mode) { modePanel(target.dataset.mode); return; }
});

const buttons = Array.prototype.slice.call(document.querySelectorAll('.filters button'));
buttons.forEach(button => button.addEventListener('click', () => {
  const wanted = button.dataset.profile;
  buttons.forEach(b => b.setAttribute('aria-pressed', String(b === button)));
  document.querySelectorAll('[data-skill]').forEach(handle => {
    const owner = byName[handle.dataset.skill];
    const inBundle = wanted === 'all' || (owner && owner.profiles.indexOf(wanted) !== -1);
    if (inBundle) handle.removeAttribute('data-out');
    else handle.setAttribute('data-out', 'true');
  });
  const profile = MODEL.profiles[wanted];
  const applicable = wanted === 'all' || !profile || profile.kind !== 'delivery-mode'
    ? null
    : profile.applicable_gates;
  document.querySelectorAll('[data-gate]').forEach(handle => {
    const applies = applicable === null || applicable.indexOf(handle.dataset.gate) !== -1;
    const gate = gateById[handle.dataset.gate];
    if (applies) handle.removeAttribute('data-na');
    else handle.setAttribute('data-na', 'true');
    if (gate) {
      handle.setAttribute(
        'aria-label',
        gate.label + (applies ? '' : '，目前選定的 bundle 不適用')
      );
    }
  });
}));
"""


SOURCE_FN_LOCAL = (
    "function source(path){ return '<a class=\"src\" href=\"../' + esc(path) "
    "+ '\">開啟 ' + esc(path) + ' →</a>'; }"
)
SOURCE_FN_HOSTED = (
    "function source(path){ return '<div class=\"src\" style=\"color:var(--dim)\">"
    "權威來源 <code>' + esc(path) + '</code>（在 repo checkout 內開啟）</div>'; }"
)


def remote_source_fn(source_base: str) -> str:
    """Build the source-link function for a standalone public site."""
    if not source_base.startswith("https://"):
        raise SystemExit("--source-base must be an https:// URL")
    base = source_base.rstrip("/") + "/"
    encoded_base = json.dumps(base, ensure_ascii=False)
    return (
        f"const SOURCE_BASE = {encoded_base};\n"
        "function source(path){ const href = SOURCE_BASE + encodeURI(path); "
        "return '<a class=\"src\" href=\"' + esc(href) + "
        "'\" target=\"_blank\" rel=\"noreferrer\">開啟 ' + esc(path) + ' →</a>'; }"
    )


def skill_chip(skill: dict) -> str:
    mark = ' <span class="ext">ext</span>' if (
        skill["provenance"]["lock"] or skill["provenance"]["declared_source"]
    ) else ""
    return (
        f'<span class="chip" data-skill="{escape(skill["name"])}" role="button" tabindex="0">'
        f'{escape(skill["name"])}{mark}</span>'
    )


def render_inner(model: dict, source_fn: str) -> str:
    skills = model["skills"]
    stages: dict[str, list[dict]] = {}
    for skill in skills:
        stages.setdefault(skill["stage"] or "未標 stage", []).append(skill)

    entry_cards = [
        (
            "人在何時決定",
            "需求、設計取捨與發布需要人做決定。其他步驟由自動檢查確認資料齊全；資訊不足就停下來。",
        ),
        (
            "工作怎麼交接",
            "每一步都把結果寫進固定文件，下一個人或 AI 工具可以從檔案繼續，不必只靠聊天紀錄。",
        ),
        (
            "工程師怎麼安裝",
            "在 .agent/project-manifest.md 設 delivery_mode 與 capability_packs，再跑 bootstrap/onboard.sh 更新安裝內容。",
        ),
        (
            "完成怎麼認定",
            "每次宣稱完成，都要附上當次自動檢查與實際操作的結果。",
        ),
    ]

    flow_blocks = []
    for flow in model["flows"]:
        variants = []
        for variant in flow.get("variants", []):
            chips = []
            for index, node in enumerate(variant.get("nodes", [])):
                if index:
                    chips.append('<span class="arrow">→</span>')
                kind = node.get("kind")
                if kind == "gate":
                    gate = next(
                        (g for g in model["human_gates"] if g["id"] == node["ref"]), None
                    )
                    label = gate["label"] if gate else node["ref"]
                    chips.append(
                        f'<span class="chip gate" data-gate="{escape(node["ref"])}" '
                        f'role="button" tabindex="0">{escape(label)}</span>'
                    )
                elif kind == "skill":
                    chips.append(
                        f'<span class="chip" data-skill="{escape(node["ref"])}" '
                        f'role="button" tabindex="0">{escape(node["ref"])}</span>'
                    )
                else:
                    chips.append(f'<span class="chip handoff">{escape(node["ref"])}</span>')
            name = variant.get("execution_mode") or variant.get("id")
            label = (
                f'<span class="vname chip" data-mode="{escape(name)}" role="button" tabindex="0">{escape(name)}</span>'
                if variant.get("execution_mode")
                else f'<span class="vname">{escape(name)}</span>'
            )
            variants.append(
                f'<div class="variant"><div class="variant-name">{label}</div>'
                f'<div class="variant-separator" aria-hidden="true"></div>'
                f'<div class="variant-flow">{"".join(chips)}</div></div>'
            )
        flow_class = "flow build-flow" if flow.get("id") == "build" else "flow"
        flow_blocks.append(
            f'<div class="{flow_class}" data-flow="{escape(flow["id"])}">'
            f'<h3>{escape(flow["router_heading"])}</h3>'
            f'<p class="intent">{escape(flow["intent"])}</p>{"".join(variants)}</div>'
        )

    artifact_names = sorted(
        {
            name
            for mode in model["execution_modes"].values()
            for name in mode["artifacts"]
        }
    )
    mode_names = sorted(model["execution_modes"])
    header_cells = "".join(f"<th>{escape(m)}</th>" for m in mode_names)
    matrix_rows = []
    for artifact in artifact_names:
        cells = []
        for mode in mode_names:
            requirement = model["execution_modes"][mode]["artifacts"][artifact]["requirement"]
            cells.append(f'<td class="req" data-v="{requirement}">{requirement}</td>')
        matrix_rows.append(
            f'<tr><td><code>{escape(artifact)}</code></td>{"".join(cells)}</tr>'
        )

    delivery = model["work_item"]["delivery_statuses"]
    delivery_rows = []
    for state in delivery:
        required = delivery[state]["required_evidence"]
        delivery_rows.append(
            f'<tr><td><code>{escape(state)}</code></td>'
            f'<td>{escape(", ".join(delivery[state]["allowed_work_statuses"]))}</td>'
            f'<td>{escape(", ".join(required)) if required else "—"}</td></tr>'
        )

    def report_row(copy: dict[str, str], summary: str) -> str:
        report = copy.get("report", "").strip()
        if not report:
            return ""
        return (
            f'<tr class="report-row"><td colspan="4">'
            f'<details class="row-report"><summary>{escape(summary)}</summary>'
            f'<div class="report-body">{report}</div></details></td></tr>'
        )

    done_rows = []
    for done in supported_evidence(model["evidence_map"]):
        done_rows.append(
            f'<tr class="done">'
            f'<td class="done-task"><strong>{escape(done["task"])}</strong>'
            f'<p class="done-question">{escape(done["question"])}</p></td>'
            f'<td class="done-result">{escape(done["result"])}</td>'
            f'<td class="done-method-cell"><p class="done-method">{escape(done["method"])}</p></td>'
            f'<td class="done-status">{escape(done["status"])}</td></tr>'
            + report_row(done, "展開完整 eval 報告")
        )

    todo_rows = []
    for todo in claim_todos(model["claim_limits"]):
        todo_rows.append(
            f'<tr class="limit">'
            f'<td class="todo-task"><strong>{escape(todo["task"])}</strong>'
            f'<p class="todo-question">{escape(todo["question"])}</p></td>'
            f'<td class="todo-result">{escape(todo["result"])}</td>'
            f'<td class="todo-method-cell"><p class="todo-method">{escape(todo["method"])}</p></td>'
            f'<td class="todo-status">{escape(todo["status"])}</td></tr>'
            + report_row(todo, "展開目前進度的完整紀錄")
        )

    roster_groups: dict[str, list[dict[str, str]]] = {}
    for entry in model["tests"]["roster"]:
        bucket = "python 分層" if entry["kind"] == "layer" else (
            "bootstrap suites" if "/bootstrap/" in entry["name"] else "top-level suites"
        )
        roster_groups.setdefault(bucket, []).append(entry)

    profile_labels = {
        "core": "核心 core",
        "frontend": "前端 frontend",
        "optional": "選用 optional",
        "personal": "個人交付 personal",
        "team-sprint": "團隊交付 team-sprint",
    }
    profile_buttons = "".join(
        f'<button data-profile="{escape(name)}" aria-pressed="false">'
        f'{escape(profile_labels.get(name, name))}'
        f' <span style="color:var(--dim)">{len(model["profiles"][name]["skills"])}</span></button>'
        for name in sorted(model["profiles"])
    )

    identity = model["identity"]
    payload = json.dumps(model, sort_keys=True, ensure_ascii=False).replace("<", "\\u003c")

    return f"""<div class="wrap">
<header>
  <h1>skill-commons</h1>
  <p class="lede">skill-commons 是給軟體團隊與 AI 協作者共用的交付流程。它把需求、設計、實作、驗證與發布要留下的資料與檢查規則固定下來，讓不同的人或工具接手時不必重新猜測上下文。</p>
</header>

<section class="mode-guide" aria-labelledby="mode-guide-title">
  <h2 id="mode-guide-title">先選交付方式</h2>
  <div class="mode-cards">
    <article class="mode-card">
      <h3>個人交付 <code>personal</code></h3>
      <p>適合個人或小範圍工作。使用較輕量的交付路徑，由實作者直接完成與驗證，只保留發布核可。</p>
    </article>
    <article class="mode-card">
      <h3>團隊交付 <code>team-sprint</code></h3>
      <p>適合需要正式需求、設計核可與 QA 驗證的團隊工作，讓多人依相同文件規格共同規劃、實作與驗收。</p>
    </article>
  </div>
  <p class="mode-note"><code>delivery mode</code> 決定交付路徑；<code>capability pack</code> 只增加前端或選用能力，不會改變已選的交付方式。</p>
</section>

<div class="filters">
  <span class="lenslabel">檢視安裝組合</span>
  <button data-profile="all" aria-pressed="true">全部 {len(skills)}</button>
  {profile_buttons}
</div>

<h2>先看整體</h2>
<div class="cards">
{"".join(f'<div class="card"><h3>{escape(t)}</h3><p>{escape(d)}</p></div>' for t, d in entry_cards)}
</div>

<h2>交付流水線</h2>
<div class="scroll">{hero_svg()}</div>
<div class="legend">
  <span><i class="m"></i>機器檢查的步驟</span>
  <span><i class="h"></i>人工判斷點（恰好三個）</span>
  <span style="color:var(--dim)">點任一節點看細節</span>
</div>

<h2>五條 flow</h2>
{"".join(flow_blocks)}
<p class="note">flow 由 <code>flows.json</code> 宣告，並與 router 散文、protocol registry 雙向綁定：
任一方單獨改動，<code>tests/test_repo_visual.sh</code> 就會變紅。</p>

<details class="engineering-details">
<summary><span><strong>工程細節</strong><small>查看 {len(skills)} 個技能、契約矩陣、交付狀態與 {len(model['tests']['roster'])} 條自動檢查</small></span></summary>
<div class="engineering-body">
<p class="note technical-stance">這套頁面描述的是宣告式契約與一致性檢查；它不負責在執行中安排工作，也不是 runtime engine、state machine 或 scheduler。權威資料在 repo，這裡提供索引與檔案出口。</p>

<h2>{len(skills)} 個技能</h2>
<div class="stagegrid">
{"".join(
    f'<div class="stage"><h4>{escape(stage)}</h4>'
    + "".join(skill_chip(s) for s in sorted(items, key=lambda x: x["name"]))
    + "</div>"
    for stage, items in sorted(stages.items())
)}
</div>
<p class="note">profile 歸屬讀自 <code>profiles/</code>，不在此頁重新輸入。
不要從技能數量推論成本或品質。</p>

<h2>Artifact 契約</h2>
<p class="note" style="margin:0 0 12px">契約版本 <code>{escape(identity["work_item_schema"])}</code>——
消費端 repo 的 work item 必須符合這一版；舊版 work item 過不了檢查。</p>
<div class="scroll" style="padding:0">
<table><thead><tr><th>artifact</th>{header_cells}</tr></thead>
<tbody>{"".join(matrix_rows)}</tbody></table>
</div>
<p class="note"><code>required</code> 缺件就停止；<code>optional</code> 存在就讀；
<code>absent</code> 是這條路徑不產該 artifact——補造它就是違約。點欄位標題看單一 mode 的完整契約。</p>

<h2>交付狀態</h2>
<div class="scroll" style="padding:0">
<table><thead><tr><th>delivery_status</th><th>允許的 work_status</th><th>必要證據</th></tr></thead>
<tbody>{"".join(delivery_rows)}</tbody></table>
</div>
<p class="note">工作完成不等於已交付。每個狀態要求對應形狀的證據；形狀檢查不證明外部核可或部署真的發生過。</p>

<h2>驗證</h2>
<p class="note">以下列出本頁公開 verification roster 的每一個 test，說明它實際檢查的邊界；單一入口仍是 <code>bash tests/verify.sh</code>。</p>
<div class="rosterwrap">
{"".join(
    f'<div class="stage"><h4>{escape(group)} · {len(entries)}</h4>'
    f'<div class="test-table-wrap"><table class="test-table"><thead>'
    f'<tr><th>test</th><th>它在做什麼</th></tr></thead><tbody>'
    + "".join(
        f'<tr><td><code>{escape(entry["name"])}</code></td>'
        f'<td>{escape(entry["description"])}</td></tr>'
        for entry in sorted(entries, key=lambda item: item["name"])
    )
    + "</tbody></table></div>"
    + "</div>"
    for group, entries in sorted(roster_groups.items())
)}
</div>
<p class="note">單一入口 <code>bash tests/verify.sh</code>，共 {len(model["tests"]["roster"])} 條。
空 roster、空 layer 與缺檔都算錯誤而非通過。真 agent journey 另行執行，不佔確定性 Verify。</p>
</div>
</details><!-- engineering-details -->

<section class="followups evidence-done" aria-label="已完成的實驗證據">
<h2>已完成的實驗證據</h2>
<p class="todo-baseline">上方「驗證」是每次都會重跑的確定性檢查。這一節列的是已經用實驗回答的問題：每一項都附上完整報告，原始 session 紀錄與重播腳本保存在開發 repo 的 work item，不隨公開頁面發布。</p>
<div class="todo-table-wrap">
  <table class="todo-table done-table"><thead><tr><th>已完成的驗證</th><th>結果</th><th>怎麼重播</th><th>狀態</th></tr></thead>
  <tbody>{"".join(done_rows)}</tbody></table>
</div>
</section>

<section class="followups" aria-label="待處理事項">
<h2>待處理事項</h2>
<p class="todo-baseline"><strong>已完成：</strong>在目前測試版本中，需求文件、計畫、安裝組合、工具轉接與發布規則彼此一致；這項自動檢查只證明規則沒有互相矛盾。token 成本基線與無洩漏盲評的實驗證據在上一節。剩下這兩項，還需要更多實驗才能回答。</p>
<div class="todo-table-wrap">
  <table class="todo-table"><thead><tr><th>待處理事項</th><th>完成後可以回答</th><th>技術驗證方法</th><th>目前狀態</th></tr></thead>
  <tbody>{"".join(todo_rows)}</tbody></table>
</div>
</section>

<footer>
  生成自 <code>scripts/repo_visual.py render</code>，資料來自
  <code>protocol-registry.json</code>、<code>profiles.json</code>、<code>flows.json</code>、
  <code>skills-lock.json</code>、各 <code>SKILL.md</code> frontmatter、
  <code>tests/verify.sh --list</code> 與 <code>docs/evaluation.md</code>。
  不含 wall-clock，因此可與自身重生成逐位元比對。
  <br>生成資訊：契約摘要 <code>{escape(identity["content_digest"])}</code> ·
  registry <code>{escape(identity["registry_schema"])}</code> ·
  flows <code>{escape(identity["flows_schema"])}</code>。摘要只在被描述的事實改變時變動，與 commit 無關。
</footer>
</div>

<dialog class="detail" aria-label="細節">
  <button class="close" autofocus>關閉</button>
  <div id="detail-body"></div>
</dialog>

<script id="model" type="application/json">{payload}</script>
<script>{JS.replace('/*SOURCE_FN*/', source_fn)}</script>
"""


def render_document(model: dict, source_fn: str) -> str:
    """Complete standalone document with one chosen source-link policy."""
    return (
        "<!DOCTYPE html>\n"
        '<html lang="zh-Hant">\n'
        "<head>\n"
        '<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width,initial-scale=1">\n'
        "<title>skill-commons Repo Map</title>\n"
        f"<style>{CSS}</style>\n"
        "</head>\n"
        "<body>\n"
        f"{render_inner(model, source_fn)}"
        "</body>\n"
        "</html>\n"
    )


def render_page(model: dict) -> str:
    """Standalone document for the repository copy."""
    return render_document(model, SOURCE_FN_LOCAL)


def render_site(model: dict, source_base: str) -> str:
    """Standalone public site whose detail exits resolve to the source repo."""
    return render_document(model, remote_source_fn(source_base))


def render_artifact(model: dict) -> str:
    """Hosted fragment. The publish host supplies the document shell, and repo
    paths are shown as text because they cannot resolve away from a checkout."""
    return (
        "<title>skill-commons Repo Map</title>\n"
        f"<style>{CSS}</style>\n"
        f"{render_inner(model, SOURCE_FN_HOSTED)}"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("model")
    render_parser = subparsers.add_parser("render")
    render_parser.add_argument(
        "--check",
        action="store_true",
        help="compare the committed page against a fresh render instead of writing",
    )
    render_kind = render_parser.add_mutually_exclusive_group()
    render_kind.add_argument(
        "--artifact",
        action="store_true",
        help="emit the hosted fragment instead of the standalone repository page",
    )
    render_kind.add_argument(
        "--source-base",
        default=None,
        help="emit a standalone public site whose detail links use this https URL base",
    )
    render_parser.add_argument("--out", default=None, help="write to this path instead of the default")
    flows_parser = subparsers.add_parser("check-flows")
    flows_parser.add_argument("--router", default=None)
    flows_parser.add_argument("--flows", default=None)
    args = parser.parse_args(argv)

    root = repo_root()
    if args.command == "model":
        model = build_model(root)
        text = json.dumps(model, sort_keys=True, indent=2, ensure_ascii=False)
        for marker in PRIVATE_MARKERS:
            if marker in text:
                print(f"model carries private reference `{marker}`", file=sys.stderr)
                return 3
        print(text)
        return 0

    if args.command == "render":
        model = build_model(root)
        if args.artifact:
            page = render_artifact(model)
        elif args.source_base:
            page = render_site(model, args.source_base)
        else:
            page = render_page(model)
        for marker in PRIVATE_MARKERS:
            if marker in page:
                print(f"page carries private reference `{marker}`", file=sys.stderr)
                return 3
        target = Path(args.out) if args.out else root / PAGE_PATH
        if args.check:
            if not target.is_file():
                print(f"page missing: {target}", file=sys.stderr)
                return 2
            if target.read_text(encoding="utf-8") != page:
                print(
                    f"page drift: {target} differs from a fresh render; "
                    "regenerate with `python3 scripts/repo_visual.py render`",
                    file=sys.stderr,
                )
                return 1
            print(f"page: {target} matches a fresh render")
            return 0
        target.write_text(page, encoding="utf-8")
        print(f"page: wrote {target}")
        return 0

    router_path = Path(args.router) if args.router else root / "skill-router" / "SKILL.md"
    flows_path = Path(args.flows) if args.flows else root / "flows.json"
    errors = check_flows(root, router_path, flows_path)
    if errors:
        for error in errors:
            print(f"flow drift: {error}", file=sys.stderr)
        return 1
    print("flows: consistent with router prose and protocol registry")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
