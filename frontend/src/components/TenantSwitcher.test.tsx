import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import TenantSwitcher from './TenantSwitcher'
import * as api from '../lib/api'

vi.mock('../lib/api', async () => {
  const actual = await vi.importActual<typeof import('../lib/api')>('../lib/api')
  return {
    ...actual,
    fetchTenants: vi.fn(),
    getActiveTenantId: vi.fn(() => null),
    setActiveTenantId: vi.fn(),
  }
})

const mockedFetchTenants = vi.mocked(api.fetchTenants)

describe('TenantSwitcher', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renders nothing when fewer than two tenants exist', async () => {
    mockedFetchTenants.mockResolvedValue([{ id: 't1', name: 'Solo', active: true }])

    const { container } = render(<TenantSwitcher />)

    await waitFor(() => expect(mockedFetchTenants).toHaveBeenCalled())
    expect(container.firstChild).toBeNull()
  })

  it('shows the active tenant and lists options on click', async () => {
    mockedFetchTenants.mockResolvedValue([
      { id: 't1', name: 'Acme', active: false },
      { id: 't2', name: 'Beta Corp', active: true },
    ])

    render(<TenantSwitcher />)

    const button = await screen.findByTitle('Switch tenant')
    expect(button.textContent).toContain('Beta Corp')

    fireEvent.click(button)
    expect(screen.getByText('Acme')).toBeInTheDocument()
  })

  it('persists selection when switching', async () => {
    mockedFetchTenants.mockResolvedValue([
      { id: 't1', name: 'Acme', active: true },
      { id: 't2', name: 'Beta Corp', active: false },
    ])

    const reload = vi.fn()
    const original = window.location
    Object.defineProperty(window, 'location', {
      value: { ...original, reload },
      writable: true,
    })

    render(<TenantSwitcher />)

    fireEvent.click(await screen.findByTitle('Switch tenant'))
    fireEvent.click(screen.getByText('Beta Corp'))

    expect(api.setActiveTenantId).toHaveBeenCalledWith('t2')
    expect(reload).toHaveBeenCalled()

    Object.defineProperty(window, 'location', { value: original, writable: true })
  })
})
