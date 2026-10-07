# Repo Map evidence semantics

解讀 Repo Map coverage、precision 或 freshness 結果時才需要讀本檔。

Repo Map inventory 包含 Git tracked 與未 ignored 的 untracked paths。Symlink
不 follow，submodule 不遞迴；supported source 超過 2 MB 只 hash、不 parse。

- Python `.py` / `.pyi` import 使用 AST，precision 為 `syntax_exact`。
- JS/TS 使用 line-oriented literal specifier candidates，precision 永遠是
  `textual_candidate`。包含 `} from "x"` 這類 multiline tail；specifier
  自己拆到下一行時不保證命中。
- Edge kind 是 `module_reference`，不提供 resolved target，也不代表
  `depends_on`。
- Unsupported、syntax error、decode error、too-large 都會反映在 coverage，
  不得偽裝 complete。

Freshness 以 scoped inventory shape、supported source content 與 extractor
fingerprint 為準，不以 commit 狀態代替內容：

- bytes 不變的 `git add` 或 commit 不會使 cache stale。
- supported source content、path add/delete/rename 會 stale。
- unsupported file 內容改變不 stale；它的 add/delete/rename 會改 inventory，
  因此 stale。

`status` 每次仍需重 hash supported inputs，成本為 O(repo)。v1 保持 full
rebuild；若 pilot 證明需要加速，只允許 stat shortcut 加 content-hash fallback，
不引入 incremental parser/database。
