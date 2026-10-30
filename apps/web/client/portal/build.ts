declare const __DRIVY_BUILD_SHA__: string;

/** Public source revision only; never includes configuration or person/school identifiers. */
export const buildSha = typeof __DRIVY_BUILD_SHA__ === 'string' ? __DRIVY_BUILD_SHA__ : 'development';
