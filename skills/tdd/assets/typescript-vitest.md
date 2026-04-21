# TypeScript / JavaScript (Vitest) — TDD adapter

> Verified against vitest 4.1.5, @testing-library/react, @testing-library/user-event, supertest, express on Node 24 (April 2026).

## Canonical command

```bash
npx vitest run --reporter=default
```

`run` (vs `vitest` alone) prevents watch mode from hanging the agent. `--reporter=default` is concise enough for cycle work.

Subset:
```bash
npx vitest run src/components/Counter.test.tsx
npx vitest run -t "increments when clicked"
```

## Minimal failing test

`src/calc.test.js`:
```js
import { describe, it, expect } from 'vitest';
import { add } from './calc.js';

describe('add', () => {
  it('returns the sum of two numbers', () => {
    expect(add(2, 3)).toBe(5);
  });
});
```

`src/calc.js` doesn't exist yet → `vitest run` exits 1 with `Test Files 1 failed (1)`. That's the RED.

Make it pass:
```js
// src/calc.js
export function add(a, b) {
  return a + b;
}
```

→ 1 passed, exit 0.

Co-locate `*.test.{js,ts,jsx,tsx}` next to source. That's the convention vitest expects and what most projects follow.

## React + Testing Library

Need `jsdom` for DOM tests. Configure once in `vitest.config.js`:
```js
import { defineConfig } from 'vitest/config';
export default defineConfig({
  test: { environment: 'jsdom' },
});
```

Render + query by role:
```jsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { Greeting } from './Greeting.jsx';

describe('Greeting', () => {
  it('renders the name passed in', () => {
    render(<Greeting name="Ada" />);
    expect(screen.getByRole('heading', { name: /hello, ada/i })).toBeDefined();
  });
});
```

User interaction:
```jsx
import userEvent from '@testing-library/user-event';

it('increments when the button is clicked', async () => {
  render(<Counter />);
  await userEvent.click(screen.getByRole('button', { name: /increment/i }));
  expect(screen.getByText(/count: 1/i)).toBeDefined();
});
```

**Query priority:** `getByRole` → `getByLabelText` → `getByPlaceholderText` → `getByText`. Reach for `getByTestId` only when nothing semantic exists.

`userEvent.click` (and friends) are async — always `await` them. The `userEvent` API is what real users do; prefer it over `fireEvent`.

## Backend — supertest + express

Per-test, mount the app and hit it through supertest. No real network:
```js
import { describe, it, expect } from 'vitest';
import request from 'supertest';
import { createApp } from './app.js';

describe('GET /health', () => {
  it('returns ok', async () => {
    const r = await request(createApp()).get('/health');
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ status: 'ok' });
  });
});
```

For backend-only test files, run with `--environment=node` (or set per-config). Default jsdom is wasted on server code.

## Idioms worth knowing

- **Test name reads as a sentence.** `it('returns 401 for an expired JWT', ...)`. The `it` + name should describe behavior the user/caller cares about.
- **Don't mock your own modules.** If you need to mock something to test it, the seam is in the wrong place. (See [references/mocking.md](../references/mocking.md).)
- **Async tests need `await`.** Forgetting `await` on `userEvent` or `request(...)` leaves promises floating; tests pass for the wrong reason.
- **One behavior per `it`.** Multiple `expect`s are fine if they verify the same observable behavior; split when they test independent behaviors.

## Dev deps

```bash
npm install -D vitest

# React + Testing Library:
npm install -D @testing-library/react @testing-library/user-event jsdom

# Backend:
npm install -D supertest @types/supertest
```

ESM projects (`"type": "module"` in package.json) work out of the box. CommonJS projects need to rename `vitest.config.js` → `vitest.config.mjs` or use TypeScript config.
