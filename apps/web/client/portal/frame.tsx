import { useEffect, useMemo, useRef, type CSSProperties, type ReactNode } from 'react';
import { BookOpen, Building2, CalendarDays, Check, ChevronDown, GraduationCap, LayoutDashboard, LogOut, Monitor, Moon, Settings, SlidersHorizontal, Sun, UsersRound } from 'lucide-react';
import { BrandSymbol } from '../BrandSymbol';
import { useTheme, type ThemePreference } from '../theme';
import type { NavigationQuery } from '../console/route';
import type { SectionKey } from '../console/sections';
import { Avatar, AvatarFallback } from '../components/ui/avatar';
import { Button } from '../components/ui/button';
import { DropdownMenu, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem, DropdownMenuLabel, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuSeparator, DropdownMenuTrigger } from '../components/ui/dropdown-menu';
import { availableWorkspaces, currentWorkspace, isActiveDestination, isNavItemCurrent, navigationQueryFor, type PortalWorkspaceKey } from './destinations';

export type PortalDestination = SectionKey;
export interface PortalFrameProps {
  children: ReactNode;
  active: SectionKey;
  activeQuery?: NavigationQuery;
  /** Sections wired to a rebuilt page; nothing else is offered. */
  available: readonly SectionKey[];
  onNavigate: (section: SectionKey, query?: NavigationQuery) => void;
  schoolName: string;
  userName: string;
  /** Synthetic preview only: shows the data notice and the build. */
  preview?: { build: string };
  /** Schools the person administers; a choice is offered when there are several. */
  schools?: readonly { id: string; name: string }[];
  currentSchoolId?: string;
  onSchoolChange?: (schoolId: string) => void;
  account?: { onPreferences: () => void; onLogout: () => void; busy?: boolean };
  search?: ReactNode;
}

const workspaceIcons: Record<PortalWorkspaceKey, typeof CalendarDays> = { pilotage: LayoutDashboard, planning: CalendarDays, learners: GraduationCap, team: UsersRound, formations: BookOpen, settings: Settings };

/** One navigation tree and one mounted page at every viewport width. */
export function PortalFrame({ children, active, activeQuery = {}, available, onNavigate, schoolName, userName, preview, schools = [], currentSchoolId, onSchoolChange, account, search }: PortalFrameProps) {
  const theme = useTheme();
  const content = useRef<HTMLElement>(null);
  const workspaces = useMemo(() => availableWorkspaces(new Set(available)), [available]);
  const workspace = currentWorkspace(workspaces, active, activeQuery);
  const currentItem = workspace?.items.find(item => isNavItemCurrent(item, active, activeQuery));
  const destinationKey = `${active}:${activeQuery.audience ?? ''}`;
  const previousDestination = useRef(destinationKey);
  useEffect(() => {
    if (previousDestination.current === destinationKey) return;
    previousDestination.current = destinationKey;
    content.current?.focus();
  }, [destinationKey]);
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
      {schools.length > 1 && onSchoolChange
        ? <DropdownMenu>
            <DropdownMenuTrigger render={<Button variant="ghost" className="portal-school portal-school-switch" aria-label={`École gérée : ${schoolName}`} />}>
              <Building2 aria-hidden="true" /><span>{schoolName}</span><ChevronDown aria-hidden="true" />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start" className="min-w-56">
              <DropdownMenuGroup>
                <DropdownMenuLabel>École gérée</DropdownMenuLabel>
                {schools.map(school => <DropdownMenuItem key={school.id} onClick={() => { if (school.id !== currentSchoolId) onSchoolChange(school.id); }}>
                  <Check aria-hidden="true" className={school.id === currentSchoolId ? undefined : 'invisible'} />{school.name}
                </DropdownMenuItem>)}
              </DropdownMenuGroup>
            </DropdownMenuContent>
          </DropdownMenu>
        : <div className="portal-school"><Building2 aria-hidden="true" /><span>{schoolName}</span></div>}
      <div className="portal-topbar-end">
        {search}
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
        {account
          ? <DropdownMenu>
              <DropdownMenuTrigger render={<Button variant="ghost" size="icon" className="portal-account-trigger" aria-label={`Compte de ${userName}`} disabled={account.busy} />}>
                <Avatar aria-hidden="true"><AvatarFallback>{initials || 'D'}</AvatarFallback></Avatar>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="min-w-56">
                <DropdownMenuGroup>
                  <DropdownMenuLabel>{userName}</DropdownMenuLabel>
                  <DropdownMenuItem onClick={account.onPreferences}><SlidersHorizontal aria-hidden="true" />Préférences</DropdownMenuItem>
                </DropdownMenuGroup>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={account.onLogout}><LogOut aria-hidden="true" />Se déconnecter</DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          : <Avatar aria-label={userName}><AvatarFallback>{initials || 'D'}</AvatarFallback></Avatar>}
      </div>
    </header>
    <div className="portal-workspace">
      <aside className="portal-sidebar">
        <nav className="portal-navigation" aria-label="Navigation principale" data-dense={workspaces.length > 5 ? 'true' : undefined} style={{ '--portal-nav-count': workspaces.length } as CSSProperties}>
          <ul>
            {workspaces.map(item => {
              const Icon = workspaceIcons[item.key], target = item.items[0]!, current = item.key === workspace?.key;
              return <li key={item.key}>
                <Button variant="ghost" className="portal-nav-item" aria-current={current ? 'page' : undefined} aria-label={item.label}
                  onClick={() => { if (!current || currentItem !== target) onNavigate(target.section, navigationQueryFor(item, target, activeQuery)); }}>
                  <Icon aria-hidden="true" /><span className="portal-nav-label" aria-hidden="true">{item.label}</span><span className="portal-nav-short" aria-hidden="true">{item.shortLabel}</span>
                </Button>
              </li>;
            })}
          </ul>
        </nav>
      </aside>
      <div className="portal-surface">
        {workspace && workspace.items.length > 1 && <nav className="portal-local-nav" aria-label={workspace.label}>
          <ul>{workspace.items.map(item => <li key={`${item.section}:${item.query?.audience ?? ''}`}>
            <Button variant="ghost" className="portal-local-item" aria-current={item === currentItem ? 'page' : undefined}
              onClick={() => { if (!isActiveDestination(item, active, activeQuery)) onNavigate(item.section, navigationQueryFor(workspace, item, activeQuery)); }}>{item.label}</Button>
          </li>)}</ul>
        </nav>}
        <main id="portal-content" ref={content} tabIndex={-1} className="portal-content" aria-label={currentItem?.label ?? workspace?.label}>{children}</main>
        {preview && <footer className="portal-build"><span>Aperçu · Données synthétiques</span><code>{preview.build.slice(0, 12)}</code></footer>}
      </div>
    </div>
  </div>;
}
