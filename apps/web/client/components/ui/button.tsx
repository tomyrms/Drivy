import { Button as ButtonPrimitive } from '@base-ui/react/button';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

/** shadcn/ui Base UI button, with Drivy variants and 44 px minimum targets. */
const buttonVariants = cva('ui-button', {
  variants: {
    variant: {
      default: 'ui-button-primary', outline: 'ui-button-outline', secondary: 'ui-button-secondary',
      ghost: 'ui-button-ghost', destructive: 'ui-button-destructive', link: 'ui-button-link',
    },
    size: { default: '', sm: 'ui-button-sm', xs: 'ui-button-sm', lg: 'ui-button-lg', icon: 'ui-button-icon', 'icon-sm': 'ui-button-icon', 'icon-xs': 'ui-button-icon', 'icon-lg': 'ui-button-icon ui-button-lg' },
  },
  defaultVariants: { variant: 'default', size: 'default' },
});

function Button({ className, variant = 'default', size = 'default', ...props }: ButtonPrimitive.Props & VariantProps<typeof buttonVariants>) {
  return <ButtonPrimitive data-slot="button" data-variant={variant} data-size={size} className={cn(buttonVariants({ variant, size }), className)} {...props} />;
}

export { Button, buttonVariants };
