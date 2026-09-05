/* ==========================================================================
   FarsHub Panel — sparkline renderer
   SVG خالص، بدون کتابخانه. viewBox ثابت 100×30 و preserveAspectRatio="none"،
   پس مختصات را در فضای 0–100 حساب می‌کنیم و CSS کشش را مدیریت می‌کند.
   stroke-width با vector-effect ثابت می‌ماند.
   ========================================================================== */

const W = 100;
const H = 30;
const PAD = 2;

/**
 * @param {SVGElement} svg  المان هدف
 * @param {number[]} series مقادیر، قدیمی → جدید
 * @param {{rtl?: boolean}} opts در RTL نمودار آینه می‌شود تا «جدیدترین» سمت
 *                              شروع خواندن بماند
 */
export function sparkline(svg, series, opts = {}) {
  if (!svg) return;
  const pts = (series || []).filter((v) => Number.isFinite(v));

  if (pts.length < 2) {
    svg.replaceChildren();
    return;
  }

  const min = Math.min(...pts);
  const max = Math.max(...pts);
  const span = max - min || 1;
  const stepX = (W - PAD * 2) / (pts.length - 1);

  const coords = pts.map((v, i) => {
    const x = PAD + i * stepX;
    const y = H - PAD - ((v - min) / span) * (H - PAD * 2);
    return [opts.rtl ? W - x : x, y];
  });

  const line = coords
    .map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(2)} ${y.toFixed(2)}`)
    .join(' ');

  const baseX = opts.rtl ? [coords[coords.length - 1][0], coords[0][0]] : [coords[0][0], coords[coords.length - 1][0]];
  const area = `${line} L${baseX[1].toFixed(2)} ${H - PAD} L${baseX[0].toFixed(2)} ${H - PAD} Z`;

  const ns = 'http://www.w3.org/2000/svg';
  const frag = document.createDocumentFragment();

  const areaEl = document.createElementNS(ns, 'path');
  areaEl.setAttribute('class', 'spark__area');
  areaEl.setAttribute('d', area);
  frag.append(areaEl);

  const lineEl = document.createElementNS(ns, 'path');
  lineEl.setAttribute('class', 'spark__line');
  lineEl.setAttribute('d', line);
  frag.append(lineEl);

  const [tipX, tipY] = coords[coords.length - 1];
  const tip = document.createElementNS(ns, 'circle');
  tip.setAttribute('class', 'spark__tip');
  tip.setAttribute('cx', tipX.toFixed(2));
  tip.setAttribute('cy', tipY.toFixed(2));
  tip.setAttribute('r', '1.8');
  frag.append(tip);

  svg.replaceChildren(frag);
}

/** بافر حلقه‌ای برای نگه‌داشتن N نمونه‌ی آخر. */
export function ring(size) {
  const buf = [];
  return {
    push(v) {
      if (Number.isFinite(v)) buf.push(v);
      while (buf.length > size) buf.shift();
      return buf;
    },
    values: () => buf.slice(),
    get length() { return buf.length; },
  };
}
