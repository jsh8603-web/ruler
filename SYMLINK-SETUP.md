---
name: Ruler Repo Symlink 구조
description: D:\projects\ruler 와 ~/.claude/ 간 파일 매핑 및 운영 규칙
tags: [ruler, symlink, infrastructure]
date: 2026-04-18
---

# Ruler Repo Symlink 구조

## 1. 배경

룰러 시스템 (`~/.claude/.ruler/*`) 을 독립 git 레포로 분리하면서 **파일은 여러 위치에서 동일하게 접근** 가능해야 함. 선택한 방식 = **역방향 symlink** (repo = 파일 소유자, 원래 경로는 symlink 로 투과).

- 레포: `D:\projects\ruler\` (remote: https://github.com/jsh8603-web/ruler)
- 원본 참조 경로: `C:\Users\jsh86\.claude\.ruler\` (모든 훅·스크립트·세션이 이 경로로 접근)

## 2. 적용된 symlink

| 원래 경로 | 타입 | 대상 (실제 파일) |
|---|---|---|
| `C:\Users\jsh86\.claude\.ruler` | `<SYMLINKD>` | `D:\projects\ruler\.ruler` |

- **생성 명령**: `mklink /D C:\Users\jsh86\.claude\.ruler D:\projects\ruler\.ruler`
- **권한 요건**: Windows 개발자 모드 ON (또는 관리자 CMD). 현재 개발자 모드 ON 상태로 생성됨
- **검증**: `ls ~/.claude/.ruler` 와 `ls /d/projects/ruler/.ruler` 결과 동일 → 투과 OK

## 3. 스킬 제외 사유 (중요)

다음 2개는 **원래 경로 유지**, ruler 레포 추적 대상 아님:
- `~/.claude/skills/ruler-wf/skill.md`
- `~/.claude/skills/audit-wf/skill.md`

### 이유
`~/.claude/skills/` = Windows junction → `G:\내 드라이브\obsidian_logan\00_Claude_Control\skills\` (Google Drive 볼트). Google Drive 가상 파일시스템은 **reparse point (symlink/junction) 미지원** — 하위에 symlink 생성 시도 시 "잘못된 파일 이름" 에러.

### 현재 정책 (옵션 A)
스킬은 레포 밖, G:\ 에서 직접 편집. Google Drive 가 버전 히스토리 자체 관리. ultraplan refine 번들에는 포함되지 않음 — 룰러 계획의 스킬 편집 step 은 **수동 편집 필수**.

### 향후 전환 가능 옵션
- **B. 수동 copy 스냅샷**: `D:\projects\ruler\skills\` 에 1회 복사 후 드리프트 감수
- **C. git hook 자동 sync**: pre-commit 에서 `cp G:\...\skill.md → D:\projects\ruler\skills\...` 강제
- **D. skills junction 해체**: 비추 (~20 스킬 재매핑 필요)

## 4. 런타임 파일 (.gitignore)

`.ruler/` 안에 있지만 **추적 제외** 대상 (세션이 지속 append/rewrite):

```
.cycle / .idle-strike / .last-patrol-ts / .last-classifier-review / .t2-locked-files
decisions.jsonl / event-patrol-feedback.jsonl
state.md / state-archive.md / state/
log/ / snapshots/ / pending/ / rollback/ / retrospective/ / batch-plans/
.messages/ / .plan-archive/ / .blockers/
*.bak-*
```

→ 상세는 `.gitignore` 참조.

## 5. 운영 규칙

### 편집 방법
- `C:\Users\jsh86\.claude\.ruler\patrol.md` 편집 === `D:\projects\ruler\.ruler\patrol.md` 편집 (완전 동일 파일)
- 어느 경로로 편집해도 `git status` 에 동일하게 반영됨
- 훅·스크립트·세션 코드는 기존 `~/.claude/.ruler/...` 경로 **그대로 유지** (수정 불필요)

### symlink 끊어짐 복구
Windows 업데이트·드라이브 포맷 등으로 symlink 가 끊어지면:

```cmd
rmdir C:\Users\jsh86\.claude\.ruler
mklink /D C:\Users\jsh86\.claude\.ruler D:\projects\ruler\.ruler
```

**주의**: `rmdir` 은 symlink 만 제거 (재귀 삭제 아님). 실수로 `rd /s` 쓰면 `D:\projects\ruler\.ruler\` 실체가 날아감 → 절대 금지.

### 레포 이동 시
`D:\projects\ruler\` 경로를 다른 위치로 옮기면 symlink 대상도 갱신 필요. 위 "복구" 절차와 동일, 단 mklink target 경로만 새 위치로.

### 백업
- `D:\projects\ruler\` → git remote (`jsh8603-web/ruler`) 가 primary 백업
- Google Drive 로 `D:\projects\ruler\` 미동기화 (의도적) — 대용량 런타임 로그가 G:\ 오염 방지

## 6. 검증 스니펫

```bash
# 1) symlink 타입 확인
cmd //c "dir /AL C:\Users\jsh86\.claude" | grep -i ruler
# 기대: <SYMLINKD>     .ruler [D:\projects\ruler\.ruler]

# 2) 투과 검증 (양쪽 ls 결과 동일해야 함)
diff <(ls ~/.claude/.ruler) <(ls /d/projects/ruler/.ruler)
# 기대: (출력 없음)

# 3) git 추적 건수
cd /d/projects/ruler && git ls-files | wc -l
# 기대: 24+ (초기 커밋 시점 기준)
```

## 7. 히스토리

- **2026-04-18 01:52 KST**: 초기 구성
  - `~/.claude/.ruler/*` 물리 이동 → `D:\projects\ruler\.ruler\*`
  - `mklink /D` 으로 원래 경로에 symlink 복원
  - 스킬 2개는 G:\ Google Drive 제약으로 레포 스코프에서 제외
  - 초기 커밋 `3b55c70`
