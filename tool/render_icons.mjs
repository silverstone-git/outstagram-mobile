// usage: bun render.mjs <mark.svg> <outdir>  -> centred navy-tile icons (no transparency)
import { Resvg } from '@resvg/resvg-js';
import fs from 'node:fs';
const [, , markPath, out] = process.argv;
const path = fs.readFileSync(markPath, 'utf8').match(/<path d="([^"]+)"/s)[1].replace(/\s+/g, ' ');
const grad = '<linearGradient id="g" gradientUnits="userSpaceOnUse" x1="22" y1="12" x2="254" y2="214"><stop offset="0" stop-color="#B7FF39"/><stop offset=".48" stop-color="#39F56B"/><stop offset="1" stop-color="#00C98B"/></linearGradient>';
// mark bbox ~ (22..254, 12..214), centre (138,113)
const tile = (scale, rx) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><defs>${grad}</defs>` +
  `<rect width="256" height="256" rx="${rx}" fill="#101020"/>` +
  `<g transform="translate(${128 - 138 * scale} ${128 - 113 * scale}) scale(${scale})"><path fill="url(#g)" d="${path}"/></g></svg>`;
fs.mkdirSync(out, { recursive: true });
const jobs = [
  ['favicon.svg', tile(0.82, 56), null],
  ['apple-touch-icon.png', tile(0.66, 0), 180],
  ['icon-192.png', tile(0.66, 0), 192],
  ['icon-512.png', tile(0.66, 0), 512],
  ['icon-maskable-512.png', tile(0.52, 0), 512],
  ['play-icon-512.png', tile(0.66, 0), 512],
];
for (const [name, svg, size] of jobs) {
  if (!size) { fs.writeFileSync(`${out}/${name}`, svg); continue; }
  fs.writeFileSync(`${out}/${name}`, new Resvg(svg, { fitTo: { mode: 'width', value: size } }).render().asPng());
}
console.log('ok', fs.readdirSync(out).join(' '));
