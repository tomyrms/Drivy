import { useEffect, useRef, type ReactNode } from 'react';
import { Building2, CalendarDays, ChevronDown, GraduationCap, Monitor, Moon, Sun, UsersRound } from 'lucide-react';
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

const destinations = [
  { value: 'agenda', label: 'Agenda', icon: CalendarDays },
  { value: 'eleves', label: 'Élèves', icon: GraduationCap },
  { value: 'equipe', label: 'Équipe', icon: UsersRound },
] as const;

/** One navigation tree and one mounted page at every viewport width. */
export function PortalFrame({ children, active, onNavigate, schoolName, userName, build }: PortalFrameProps) {
  const theme = useTheme();
  const content = useRef<HTMLElement>(null);
  const previousDestination = useRef(active);
  useEffect(() => {
    if (previousDestination.current === active) return;
    previousDestination.current = active;
    content.current?.focus();
  }, [active]);
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
                {themes.map(option => <DropdownMenuRadioItem key={option.value} value={option.value} closeOnClick><option.icon aria-hidden="true" />{option.label}</DropdownMenuRadioItem>)}
              </DropdownMenuRadioGroup>
            </DropdownMenuGroup>
          </DropdownMenuContent>
        </DropdownMenu>
        <Avatar aria-label={userName}><AvatarFallback>{initials || 'D'}</AvatarFallback></Avatar>
      </div>
    </header>
    <div className="portal-workspace">
      <aside className="portal-sidebar">
        <nav className="portal-navigation" aria-label="Navigation principale">
          <ul>
            {destinations.map(destination => <li key={destination.value}>
              <Button variant="ghost" className="portal-nav-item" aria-current={active === destination.value ? 'page' : undefined}
                onClick={() => { if (active !== destination.value) onNavigate(destination.value); }}>
                <destination.icon aria-hidden="true" /><span>{destination.label}</span>
              </Button>
            </li>)}
          </ul>
        </nav>
      </aside>
      <div className="portal-surface">
        <main id="portal-content" ref={content} tabIndex={-1} className="portal-content" aria-label={destinations.find(destination => destination.value === active)?.label}>{children}</main>
        <footer className="portal-build"><span>Aperçu · Données synthétiques</span><code>{build.slice(0, 12)}</code></footer>
      </div>
    </div>
  </div>;
}
