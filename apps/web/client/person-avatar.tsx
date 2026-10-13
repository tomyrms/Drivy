import './person-avatar.css';

/** A visual anchor only: the person's name remains the accessible text next to it. */
export function PersonAvatar({ name, size = 'small' }: { name: string; size?: 'small' | 'large' }) {
  const words = name.trim().split(/\s+/).filter(Boolean);
  const initials = [words[0], words.length > 1 ? words.at(-1) : undefined]
    .filter((word): word is string => !!word).map(word => [...word][0]).join('').toLocaleUpperCase('fr');
  return <span className={`person-avatar${size === 'large' ? ' person-avatar-large' : ''}`} aria-hidden="true">{initials || '·'}</span>;
}
