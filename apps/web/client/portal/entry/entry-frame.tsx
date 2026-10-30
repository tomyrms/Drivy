import type { ReactNode } from 'react';
import { ChevronDown, LogOut, Monitor, Moon, SlidersHorizontal, Sun } from 'lucide-react';
import { useTheme, type ThemePreference } from '../../theme';
import { BrandSymbol } from '../../BrandSymbol';
import { Avatar, AvatarFallback } from '../../components/ui/avatar';
import { Button } from '../../components/ui/button';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem, DropdownMenuLabel, DropdownMenuRadioGroup, DropdownMenuRadioItem,
  DropdownMenuSeparator, DropdownMenuTrigger,
} from '../../components/ui/dropdown-menu';
import { personInitials } from './entry-model';
import '../portal.css';
import './entry.css';

const themes = [
  { value: 'light', label: 'Clair', icon: Sun },
  { value: 'dark', label: 'Sombre', icon: Moon },
  { value: 'system', label: 'Système', icon: Monitor },
] as const;

export interface EntryAccount { name: string; preferences: string; busy: boolean; onLogout: () => void }

/** Standalone page outside the school console: brand, appearance and, once signed in, the account menu. */
export function EntryFrame({ children, home, account, width = 'narrow', busy = false }: {
  children: ReactNode; home: string; account?: EntryAccount | null; width?: 'narrow' | 'wide'; busy?: boolean;
}) {
  const theme = useTheme();
  const ThemeIcon = theme.preference === 'system' ? Monitor : theme.preference === 'dark' ? Moon : Sun;
  return <div className="portal-app entry-app">
    <a className="portal-skip-link" href="#portal-content">Aller au contenu</a>
    <header className="portal-topbar entry-topbar">
      <a className="portal-brand" href={home} aria-label="Drivy, votre espace"><BrandSymbol /><span>Drivy</span></a>
      <div className="portal-topbar-end">
        <DropdownMenu>
          <DropdownMenuTrigger render={<Button variant="ghost" className="portal-theme-trigger" aria-label="Choisir l’apparence" />}>
            <ThemeIcon aria-hidden="true" /><span>Apparence</span><ChevronDown aria-hidden="true" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="min-w-48">
            <DropdownMenuGroup>
              <DropdownMenuLabel>Apparence</DropdownMenuLabel>
              <DropdownMenuRadioGroup value={theme.preference} onValueChange={value => theme.setTheme(value as ThemePreference)}>
                {themes.map(option => <DropdownMenuRadioItem key={option.value} value={option.value} closeOnClick><option.icon aria-hidden="true" />{option.label}</DropdownMenuRadioItem>)}
              </DropdownMenuRadioGroup>
            </DropdownMenuGroup>
          </DropdownMenuContent>
        </DropdownMenu>
        {account && <DropdownMenu>
          <DropdownMenuTrigger render={<Button variant="ghost" size="icon" className="portal-account-trigger" aria-label={`Compte de ${account.name}`} disabled={account.busy} />}>
            <Avatar aria-hidden="true"><AvatarFallback>{personInitials(account.name) || 'D'}</AvatarFallback></Avatar>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="min-w-56">
            <DropdownMenuGroup>
              <DropdownMenuLabel>{account.name}</DropdownMenuLabel>
              <DropdownMenuItem onClick={() => window.location.assign(account.preferences)}><SlidersHorizontal aria-hidden="true" />Préférences</DropdownMenuItem>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={account.onLogout}><LogOut aria-hidden="true" />Se déconnecter</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>}
      </div>
    </header>
    <main id="portal-content" tabIndex={-1} className={`entry-main entry-main-${width}`} aria-busy={busy}>{children}</main>
  </div>;
}
