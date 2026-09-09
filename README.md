# UsageOverlay

macOS 메뉴바에서 Claude(claude.ai)와 ChatGPT(chatgpt.com)의 세션/주간 한도 **잔여량**을
보여주는 앱. 각 서비스의 공식 앱과 같은 기준(남은 %)으로 표시합니다.

메뉴바에는 `CL 77 · GPT 52`처럼 잔여 %만 짧게 표시되고, 여유가 없을 때만 주황/빨강으로
바뀝니다. 드롭다운은 커스텀 뷰로 그린 캡슐 게이지로 표시되며 라이트/다크 모드를 모두 지원합니다.

| 잔여량 | 색 |
|---|---|
| 40% 이상 | 초록 |
| 15–40% | 주황 |
| 15% 미만 | 빨강 |

드롭다운 레이아웃을 이미지로 확인하려면:

```bash
./.build/release/UsageOverlay --render-preview /tmp/menu.png
```

Anthropic과 OpenAI 둘 다 이 값을 위한 **공식 공개 API가 없습니다.** 이 앱은 웹앱이 내부적으로
쓰는 비공식 API를 로그인 쿠키로 호출하는 방식이라, 두 회사가 언제든 응답 형식을 바꾸면
깨질 수 있습니다. 개인 계정에 한해서만 사용하세요 (다른 사람 계정 스크래핑 금지).

## 1. 빌드 & 설치

```bash
./build.sh
cp -R dist/UsageOverlay.app /Applications/
open /Applications/UsageOverlay.app
```

메뉴바에 `Usage: not set up` 라고 뜨면 정상 실행된 것입니다 (아직 설정 전).

로그인 시 자동 실행하려면: 시스템 설정 → 일반 → 로그인 항목 → `+` → UsageOverlay.app 추가.

## 2. 로그인

메뉴바 아이콘 클릭 → **"Claude 로그인…"** 또는 **"ChatGPT 로그인…"**.

앱에 내장된 브라우저 창이 뜹니다. **이 창은 Safari/Chrome과 쿠키를 공유하지 않으므로,
평소 브라우저에서 로그인되어 있더라도 이 창 안에서 한 번은 직접 로그인해야 합니다.**
로그인이 완료되면 (아래 인증 쿠키가 생기면) 자동으로 감지해서 저장하고 창이 닫힙니다.

| | 인증 쿠키 | 요청 방식 |
|---|---|---|
| Claude | `sessionKey` | 숨겨진 WKWebView (Cloudflare 우회) |
| ChatGPT | `__Secure-next-auth.session-token.0/.1` | 일반 HTTPS + Bearer 토큰 |

> 자동 감지는 **정확한 쿠키 이름**으로만 판단합니다. 예전에는 "이름에 session 포함"으로
> 느슨하게 판단했는데, claude.ai는 로그아웃 상태에서도 `activitySessionId` 쿠키를 주기 때문에
> 로그인하지도 않았는데 "연결됨"으로 표시되고 `Invalid authorization`이 나는 버그가 있었습니다.

자동 감지가 안 되면 창 아래쪽의 **"로그인 완료 — 지금 저장"** 버튼을 누르세요 (인증 쿠키가
없으면 저장을 거부하고 안내합니다).

### ⚠️ Google 로그인은 내장 창에서 작동하지 않습니다

Google은 앱에 내장된 웹뷰에서의 OAuth 로그인을 정책적으로 차단합니다(피싱 방지). 그래서 내장
창에서 "Google로 계속하기"를 누르면 *"로그인 중 오류가 발생했습니다"* 가 뜹니다. 우회하지 말고
아래 둘 중 하나를 쓰세요.

**방법 A — 이메일 로그인 (권장)**
내장 창에서 "이메일로 계속하기"를 선택하고, 메일로 온 코드를 입력합니다.
Google로 가입한 계정이어도 같은 이메일로 코드 로그인이 됩니다.

**방법 B — sessionKey 붙여넣기**
메뉴바 → **"↳ Claude sessionKey 직접 붙여넣기…"**

1. 평소 쓰는 브라우저(Safari/Chrome)에서 claude.ai에 로그인.
2. 개발자 도구(⌥⌘I) → **Application**(Chrome)/**Storage**(Safari) → Cookies → `https://claude.ai`
3. `sessionKey` 행의 **Value**를 복사 (`sk-ant-sid01-…`).
4. 메뉴의 붙여넣기 항목에 입력 → 저장.

붙여넣은 값은 앱의 쿠키 저장소에 직접 주입되므로, 이후 갱신은 로그인 없이 계속 동작합니다.
세션이 만료되면 `Invalid authorization`이 뜨고, 같은 방법으로 다시 넣으면 됩니다.

### 확인된 엔드포인트

각각 [claude-usage-widget](https://github.com/SlavomirDurej/claude-usage-widget),
[AIQuotaBar](https://github.com/yagcioglutoprak/AIQuotaBar)를 참고해 찾았고, 실제 응답으로 검증했습니다.

**Claude** — `GET /api/organizations` → 첫 조직 `uuid`, 이어서
`GET /api/organizations/{uuid}/usage` → `five_hour.utilization`, `seven_day.utilization` (+ `resets_at`).
claude.ai는 Cloudflare 봇 차단이 있어서 일반 HTTP 요청은 403이 납니다. 그래서 이 요청만
**숨겨진 WKWebView**로 보냅니다 (로그인 때 저장된 실제 브라우저 쿠키를 그대로 사용).

**ChatGPT** — `GET /api/auth/session` → `accessToken`, 이어서
`GET /backend-api/wham/usage` (`Authorization: Bearer …`) →
`rate_limit.primary_window`(5시간, `limit_window_seconds: 18000`),
`rate_limit.secondary_window`(1주, `604800`). 각 window에 `used_percent`와 `reset_at`(epoch초).
이 두 window는 공식 ChatGPT 앱의 "남은 사용량" 패널과 **동일한 값**입니다
(공식 앱은 *남은* 비율을, 이 앱은 *사용한* 비율과 남은 비율을 함께 표시).

둘 다 비공식 API라 언제든 바뀔 수 있습니다. `HTTP 401`이나 `Invalid authorization`이 뜨면
세션이 만료된 것이니 같은 로그인 버튼을 다시 누르세요.

### 응답이 이상할 때

성공한 마지막 응답이 설정 폴더에 `last-response-<Provider>.json`으로 저장됩니다.
필드 이름이 바뀌었다면 이 파일을 열어보고 `config.json`의 `percentPath` 등을 고치면 됩니다.
경로에는 `a.b|c.d`처럼 `|`로 후보를 여러 개 적을 수 있고, 먼저 맞는 것이 사용됩니다.

### 수동 설정 (자동 로그인이 안 될 때)

ChatGPT는 `secrets.json`의 쿠키를 직접 씁니다. Claude는 숨겨진 WKWebView의 쿠키 저장소를
쓰기 때문에 `secrets.json` 값은 사용되지 않습니다 (내장 창 로그인이 유일한 경로).

1. 브라우저 개발자 도구 → Network 탭 → `chatgpt.com` 요청 클릭 → Request Headers의
   `Cookie` 줄 전체를 복사.
2. 메뉴바 → **Open Config Folder… (고급)** → `secrets.json`의 `chatgpt_cookie`에 붙여넣기.
3. 같은 폴더의 `config.json`에서 `enabled`를 `true`로.
4. 메뉴바 → Refresh Now.

## 3. 설정 파일 위치

```
~/Library/Application Support/UsageOverlay/config.json   ← 엔드포인트/경로 설정 (비밀 아님)
~/Library/Application Support/UsageOverlay/secrets.json  ← 쿠키 값 (600 권한, 절대 커밋/공유 금지)
```

메뉴바 아이콘 → **Open Config Folder…** 로 바로 열 수 있습니다.
저장 후 메뉴바 → **Refresh Now** (또는 `refreshIntervalSeconds` 간격마다 자동 갱신).

### config.json 필드 설명

| 필드 | 설명 |
|---|---|
| `url`, `method`, `headers`, `body` | 요청 자체 |
| `percentPath` | 응답 JSON에서 사용량(%) 또는 비율(0~1)이 있는 경로 (dot/`[idx]` 표기) |
| `percentIsFraction` | `percentPath` 값이 0~1 비율이면 `true` |
| `usedPath` / `limitPath` | %가 없고 "사용량/한도" 두 숫자만 있을 때 대안으로 사용 (used/limit*100 계산) |
| `resetAtPath`, `resetAtFormat` | 리셋 시각 (`iso8601` / `epochSeconds` / `epochMillis`) |
| `secondaryLabel` 등 | 두 번째 윈도우(예: 5시간 세션 + 주간)가 있을 때 |
| `orgIdURL`, `orgIdPath` | `url`에 `{organizationId}` 토큰이 있으면, 먼저 이 URL을 같은 헤더로 호출해 조직 ID를 알아내 치환 (Claude 기본값에 이미 설정됨) |
| `tokenURL`, `tokenPath`, `tokenHeaderName`, `tokenHeaderPrefix` | 실제 요청 전에 다른 URL을 먼저 호출해 토큰을 얻고, 그 값을 헤더에 넣어야 할 때 (ChatGPT 기본값에 이미 설정됨) |

`headers`의 값에서 `${claude_cookie}`, `${chatgpt_cookie}` 같은 `${...}` 표기는
`secrets.json`의 같은 키 값으로 자동 치환됩니다.

## 4. 쿠키가 만료되면

로그아웃하거나 세션이 끊기면 메뉴에 `HTTP 401` 같은 에러가 표시됩니다.
브라우저에서 다시 로그인 후 쿠키를 새로 복사해서 `secrets.json`을 갱신하고 Refresh Now.

## 보안 참고

- `secrets.json`은 로그인 쿠키(사실상 세션 토큰)를 평문으로 담고 있습니다. 파일 권한은 600으로
  자동 설정되지만, 이 파일을 git에 커밋하거나 다른 사람과 공유하지 마세요.
- 이 앱은 여러분 자신의 계정 사용량만 조회하도록 설계되었습니다.
