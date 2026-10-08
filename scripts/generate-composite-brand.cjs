const fs = require('fs');
const path = require('path');

const sections = [
  ['Music', 'music'],
  ['Video', 'video'],
  ['Browser', 'browser'],
  ['Trading', 'trading'],
  ['Downloader', 'download'],
];
const wordmark = fs.readFileSync('Assets.xcassets/JizaWordmark.imageset/wordmark.png').toString('base64');

for (const [title, slug] of sections) {
  const letteringFile = fs.readdirSync('Brand').find(name => name.includes(`lettering-${slug}-`));
  if (!letteringFile) throw new Error(`Missing ${slug} lettering asset`);
  const lettering = fs.readFileSync(path.join('Brand', letteringFile)).toString('base64');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="240" height="48" viewBox="0 0 240 48"><image x="0" y="7" width="68" height="34" href="data:image/png;base64,${wordmark}"/><image x="76" y="0" width="164" height="48" href="data:image/png;base64,${lettering}"/></svg>`;
  const directory = `Assets.xcassets/Jiza${title}Brand.imageset`;
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(path.join(directory, `jiza-${slug}.svg`), svg);
  fs.writeFileSync(path.join(directory, 'Contents.json'), JSON.stringify({
    images: [{ filename: `jiza-${slug}.svg`, idiom: 'universal' }],
    info: { author: 'xcode', version: 1 },
    properties: { 'template-rendering-intent': 'template' },
  }, null, 2));
}
