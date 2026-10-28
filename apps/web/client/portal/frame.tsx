import type { ReactNode } from 'react';
import { Building2, ChevronDown, Monitor, Moon, Sun } from 'lucide-react';
import { BrandSymbol } from '../BrandSymbol';
import { useTheme, type ThemePreference } from '../theme';
import { Avatar, AvatarFallback } from '../components/ui/avatar';
import { Button } from '../components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuGroup, DropdownMenuLabel, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuTrigger } from '../components/ui/dropdown-menu';

export type PortalDestination = 'agenda' | 'eleves' | 'equipe';
export interface PortalFrameProps {
  children: ReactNode;
  active: PortalDestination;
  onNavigate: (destination: PortalDestination) => void;
  schoolName: string;
  userName: string;
  build: string;
}

/** The first approved scope is one access page. No pretend destination is shown. */
export function PortalFrame({ children, schoolName, userName, build }: PortalFrameProps) {
  const theme = useTheme();
  const initials = userName.trim().split(/\s+/).slice(0, 2).map(part => part.charAt(0)).join('').toLocaleUpperCase('fr');
  const themes = [
    { value: 'light', label: 'Clair', icon: Sun },
    { value: 'dark', label: 'Sombre', icon: Moon },
    { value: 'system', label: 'Système', icon: Monitor },
  ] as const;
  const ThemeIcon = theme.preference === 'system' ? Monitor : theme.preference === 'dark' ? Moon : Sun;
  return <div className="portal-app">
    <a className="portal-skip-link" href="#portal-content">Aller au contenu</a>
    <header className="portal-topbar">
      <div className="portal-brand" aria-label="Drivy"><BrandSymbol /><span>Drivy</span></div>
      <div className="portal-school"><Building2 aria-hidden="true" /><span>{schoolName}</span></div>
      <div className="portal-topbar-end">
        <DropdownMenu>
          <DropdownMenuTrigger render={<Button variant="ghost" className="portal-theme-trigger" aria-label="Choisir l’apparence" />}>
            <ThemeIcon aria-hidden="true" /><span>Apparence</span><ChevronDown aria-hidden="true" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="min-w-48">
            <DropdownMenuGroup>
              <DropdownMenuLabel>Apparence</DropdownMenuLabel>
              <DropdownMenuRadioGroup value={theme.preference} onValueChange={value => theme.setTheme(value as ThemePreference)}>
                {themes.map(option => <DropdownMenuRadioItem key={option.value} value={option.value}><option.icon aria-hidden="true" />{option.label}</DropdownMenuRadioItem>)}
              </DropdownMenuRadioGroup>
            </DropdownMenuGroup>
          </DropdownMenuContent>
        </DropdownMenu>
        <Avatar aria-label={userName}><AvatarFallback>{initials || 'D'}</AvatarFallback></Avatar>
      </div>
    </header>
    <main id="portal-content" tabIndex={-1} className="portal-content">{children}</main>
    <footer className="portal-build"><span>Aperçu · Données synthétiques</span><code>{build.slice(0, 12)}</code></footer>
  </div>;
}
