/** « La trace » master from docs/implementation/assets/brand-20261006/kit.
 * CurrentColor keeps the symbol legible in both themes and forced colours.
 * The parent brand link supplies the accessible name.
 */
export function BrandSymbol() {
  return <span className="brand-symbol" aria-hidden="true">
    <svg viewBox="0 0 256 256" focusable="false">
      <g className="brand-symbol-light">
        <path d="M170 48C170 36.95 178.95 28 190 28C201.05 28 210 36.95 210 48V208C210 219.05 201.05 228 190 228C180.45 228 172.46 221.3 170.47 212.35C185.56 198.29 195 178.25 195 156C195 133.52 185.37 113.29 170 99.21Z" />
        <path fillRule="evenodd" d="M46 156 A72 72 0 1 0 190 156 A72 72 0 1 0 46 156 Z M78 156 A40 40 0 1 1 158 156 A40 40 0 1 1 78 156 Z" />
      </g>
      <g className="brand-symbol-dark">
        <path d="M170.75 48C170.75 37.37 179.37 28.75 190 28.75C200.63 28.75 209.25 37.37 209.25 48V208C209.25 218.63 200.63 227.25 190 227.25C180.65 227.25 172.86 220.59 171.11 211.75C185.83 197.72 195 177.93 195 156C195 133.89 185.68 113.95 170.75 99.91Z" />
        <path fillRule="evenodd" d="M46.75 156 A71.25 71.25 0 1 0 189.25 156 A71.25 71.25 0 1 0 46.75 156 Z M77.25 156 A40.75 40.75 0 1 1 158.75 156 A40.75 40.75 0 1 1 77.25 156 Z" />
      </g>
    </svg>
  </span>;
}
