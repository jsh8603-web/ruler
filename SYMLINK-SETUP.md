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

## 3. 스킬 파일 sync (옵션 C 적용)

다음 2개는 Obsidian G:\ 볼트 (Google Drive) 에 물리 존재. Google Drive 는 **reparse point 미지원** → symlink/junction 불가. **pre-commit hook 으로 G:\ → repo 단방향 sync** 적용.

- `G:\내 드라이브\obsidian_logan\00_Claude_Control\skills\ruler-wf\skill.md` (SSOT)
- `G:\내 드라이브\obsidian_logan\00_Claude_Control\skills\audit-wf\skill.md` (SSOT)

### 구조
```
D:\projects\ruler\
├── skills/
│   ├── ruler-wf/skill.md      ← G:\ 에서 copy (mirror, 편집 금지)
│   └── audit-wf/skill.md      ← G:\ 에서 copy (mirror, 편집 금지)
├── scripts/
│   └── sync-skills.sh         ← G:\ → repo 단방향 copy
└── .git/hooks/
    └── pre-commit             ← sync-skills.sh --stage 호출
```

### sync 동작 (3-way 지능형)
`sync-skills.sh` 는 `git HEAD` 를 기준점으로 G:\ / D:\ / HEAD 세 버전을 비교해 방향을 자동 결정:

| G: vs HEAD | D: vs HEAD | 동작 |
|---|---|---|
| 일치 | 일치 | no-op |
| 다름 | 일치 | **G: → D:** (외부 편집 흡수, 일반 케이스) |
| 일치 | 다름 | **D: → G:** (ultraplan refine·에이전트 repo 편집 역전파) |
| 다름 | 다름 | **ABORT** (양쪽 독립 편집 = 충돌, exit 2) |

### 에이전트가 어떤 경로로 편집해도 안전
| 편집 경로 | 실제 도달 | 커밋 시 동작 |
|---|---|---|
| `~/.claude/skills/ruler-wf/skill.md` | G:\ (junction) | G: → D: 자동 sync |
| `D:\projects\ruler\skills\ruler-wf\skill.md` | D:\ | D: → G: **역전파** |
| ultraplan refine 결과 | D:\ (repo 경로) | D: → G: **역전파** |
| Obsidian 앱에서 편집 | G:\ | G: → D: 자동 sync |

### 충돌 케이스
두 쪽이 모두 마지막 커밋과 다르면 `sync-skills.sh` 가 exit 2 로 abort. 커밋도 차단됨. 수동 해결:
```bash
diff "/g/내 드라이브/obsidian_logan/00_Claude_Control/skills/ruler-wf/skill.md" \
     "D:/projects/ruler/skills/ruler-wf/skill.md"
# 채택할 쪽 결정 후 반대편에 cp, 다시 git commit
```

### 편집 규칙 (경로 무관하게 안전)
- 어느 경로로 편집하든 `git commit` 시점에 pre-commit hook 이 정리
- 단 **커밋 간격이 길수록 충돌 위험 증가** (양쪽에서 동시 편집 가능성) → 스킬 수정 후 가급적 빨리 커밋
- hook 우회 (`git commit --no-verify`) 시 자동 sync 없음 → 수동으로 `./scripts/sync-skills.sh` 실행 필요

### 수동 실행
```bash
cd /d/projects/ruler && ./scripts/sync-skills.sh
# 또는 스테이징까지:
./scripts/sync-skills.sh --stage
```

### 기각된 대안
- **A (제외)**: ultraplan 이 skill 내용을 못 봐서 refine·review 품질 저하 — 기각
- **B (수동 copy)**: 편집자가 까먹으면 드리프트 — pre-commit hook 으로 강제 해결 (이것이 C)
- **D (skills junction 해체)**: ~20 스킬 재매핑 부담 — 비추

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
  - 스킬 2개는 G:\ Google Drive 제약으로 레포 스코프에서 제외 (옵션 A 초안)
  - 초기 커밋 `3b55c70`

- **2026-04-18 02:00 KST**: 옵션 C (pre-commit sync) 로 승격
  - ultraplan 이 skill 내용을 못 봐서 refine·review 품질 저하 문제 식별
  - `scripts/sync-skills.sh` 작성 (G:\ → repo 단방향 copy)
  - `.git/hooks/pre-commit` 등록 → 커밋 시마다 자동 sync + 스테이징
  - 초기 복사: `skills/ruler-wf/skill.md` (19k), `skills/audit-wf/skill.md` (12k)

- **2026-04-18 02:10 KST**: 단방향 → 3-way 지능형 동기화로 재설계
  - **결함 발견**: 단방향 (G: → D:) 은 D: 에서 편집 (ultraplan refine / agent 직접 편집) 시 다음 commit 에서 덮어써서 **편집 소실**
  - `sync-skills.sh` 를 git HEAD 기준 3-way 판정으로 재작성
  - 일반 케이스 G:→D: 외에 D:→G: 역전파 추가 + 충돌 시 abort
  - 에이전트가 어떤 경로로 편집해도 안전 (`~/.claude/skills/...` 또는 `D:\projects\ruler\skills\...`)
