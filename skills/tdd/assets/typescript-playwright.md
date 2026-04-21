# TypeScript / JavaScript (Playwright) — TDD adapter for E2E

> Verified config + spec syntax against @playwright/test 1.59.1 on Node 24 (April 2026). Browser execution not verified in this adapter — that requires `npx playwright install`.

## When to use Playwright (and when not to)

Reach for Playwright **only** when the behavior genuinely requires a real browser:
- Multi-page navigation flows
- Drag-and-drop, file upload, clipboard
- Real network round-trips against your dev server
- Browser-specific APIs (storage, service workers, IntersectionObserver edge cases)

For component logic, render output, and event handling, [Vitest + Testing Library](typescript-vitest.md) is faster, headless, parallel, and doesn't need a server. Don't run Playwright when Vitest will do.

## Canonical command

```bash
npx playwright test --reporter=line
```

`--reporter=line` is one line per test — concise enough for cycle work. The default `list` reporter is also fine.

Subset:
```bash
npx playwright test tests/e2e/login.spec.ts
npx playwright test --grep "expired JWT"
```

Headed for debug (don't use in CI):
```bash
npx playwright test --headed
npx playwright test --ui
```

## Minimal config

`playwright.config.ts`:
```ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  reporter: 'line',
  use: {
    baseURL: process.env.BASE_URL ?? 'http://localhost:3000',
  },
});
```

The `webServer` block can also be added so Playwright starts your dev server automatically — but for first cycles, start the server in another terminal and let Playwright connect to it.

## Minimal failing test

`tests/e2e/login.spec.ts`:
```ts
import { test, expect } from '@playwright/test';

test.describe('login page', () => {
  test('rejects expired JWT with a user-visible error', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel(/email/i).fill('a@b.co');
    await page.getByLabel(/password/i).fill('expired');
    await page.getByRole('button', { name: /sign in/i }).click();

    await expect(page.getByRole('alert')).toContainText(/token expired/i);
    await expect(page).toHaveURL(/\/login/);
  });
});
```

Without the actual login route implementing the 401 + alert message, the assertions fail → that's the RED.

## Idioms worth knowing

- **Always `await`.** Every `page.*` and `expect(...)` call returns a Promise. A missing `await` makes the test pass for the wrong reason.
- **Query by role first.** `page.getByRole('button', { name: /submit/i })` over `page.locator('#submit-btn')`. Same priority order as Testing Library.
- **`expect` auto-waits.** `await expect(locator).toBeVisible()` retries until it passes or timeout. Don't `sleep()` — use `expect`.
- **One flow per test.** A test should describe one user-visible outcome ("rejects expired JWT", "completes checkout"). Don't chain unrelated assertions across pages in one `test` — split them.
- **No `page.waitForTimeout`.** Hard waits hide flakiness. Wait for the actual condition (`expect.toBeVisible`, `waitForURL`, `waitForResponse`).

## First-time install

```bash
npm install -D @playwright/test
npx playwright install chromium             # one-time browser download (~200MB)
# Linux only — also pulls system deps:
npx playwright install chromium --with-deps
```

For quick CI / cycle work, install only Chromium. Add Firefox/WebKit projects only when a behavior is browser-specific.

## Selecting which browsers run

Add `projects` to the config:
```ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    // Uncomment when a test fails in a specific browser and you need to reproduce:
    // { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    // { name: 'webkit',  use: { ...devices['Desktop Safari'] } },
  ],
});
```

Default to chromium-only; add others on demand. Three browsers × every test = 3× CI time for marginal coverage on most apps.
