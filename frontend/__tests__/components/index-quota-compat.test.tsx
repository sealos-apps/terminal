import React from 'react';
import { flushSync } from 'react-dom';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import Index from '@/pages/index';

const triggerQuotaCheck = vi.fn();
const applyApp = vi.fn();

vi.mock('@/store/session', () => ({
  default: () => ({
    isUserLogin: () => true,
    session: { user: { id: 'user-test' } }
  })
}));

vi.mock('@/api/terminal', () => ({
  getEnv: vi.fn()
}));

vi.mock('@/service/request', () => ({
  default: {
    post: (...args: unknown[]) => applyApp(...args)
  }
}));

vi.mock('@labring/sealos-shared-sdk', () => ({
  useQuotaGuarded: () => triggerQuotaCheck
}));

vi.mock('@tanstack/react-query', () => ({
  useQuery: (keyOrOptions: unknown, queryFn?: () => unknown, options?: { enabled?: boolean }) => {
    if (typeof keyOrOptions === 'object' && keyOrOptions !== null && 'queryKey' in keyOrOptions) {
      return { data: { data: { data: {} } }, isSuccess: true };
    }

    if (options?.enabled) void queryFn?.();
    return {};
  }
}));

vi.mock('@chakra-ui/react', () => ({
  Box: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
  Button: ({ children, onClick }: React.PropsWithChildren<{ onClick?: () => void }>) => (
    <button type="button" onClick={onClick}>
      {children}
    </button>
  ),
  Flex: ({ children }: React.PropsWithChildren) => <div>{children}</div>,
  Spinner: () => <div>Loading</div>,
  useToast: () => vi.fn()
}));

vi.mock('@/components/terminal', () => ({
  default: () => <div>Terminal</div>
}));

vi.mock('@/pages/index.module.scss', () => ({ default: {} }));

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  triggerQuotaCheck.mockReset();
  applyApp.mockReset();
  applyApp.mockResolvedValue({ data: { code: 200, data: '' } });
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  flushSync(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
});

const renderPage = () => {
  flushSync(() => root.render(<Index site="https://desktop.example.test" />));
};

describe('Terminal quota compatibility', () => {
  test('continues when a legacy Desktop does not declare the workspace quota RPC', async () => {
    triggerQuotaCheck.mockRejectedValue({ success: false, message: 'function is not declare' });

    renderPage();

    await vi.waitFor(() => {
      expect(applyApp).toHaveBeenCalledWith('/api/apply');
    });
  });

  test('blocks terminal creation and offers retry for other quota-check failures', async () => {
    triggerQuotaCheck.mockRejectedValue(new Error('timeout'));

    renderPage();

    await vi.waitFor(() => {
      expect(container.textContent).toContain('Unable to verify workspace quota.');
    });
    expect(applyApp).not.toHaveBeenCalled();

    triggerQuotaCheck.mockResolvedValue(false);
    container.querySelector<HTMLButtonElement>('button')?.click();

    await vi.waitFor(() => {
      expect(triggerQuotaCheck).toHaveBeenCalledTimes(2);
    });
  });
});
