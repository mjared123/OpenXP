const fs = require('node:fs');
const path = require('node:path');

const root = process.argv[2] || '.';
const localePath = process.argv[3] || path.join(root, 'locale', 'deDE_guide.lua');
const manifest = fs.readFileSync(path.join(root, 'Guides/GuideList-forever.xml'), 'utf8');
const files = Array.from(manifest.matchAll(/<Script\s+file="(Guides\/[^"]+\.lua)"/g), m => m[1]);
if (!files.length) throw Error('No guides listed in Guides/GuideList-forever.xml');

const locale = fs.readFileSync(localePath, 'utf8').replace(/\r\n/g, '\n');
function tableBody(name) {
  const start = locale.indexOf('    ' + name + ' = {\n');
  const end = locale.indexOf('\n    },', start);
  if (start < 0 || end < 0) throw Error('Missing translation table: ' + name);
  return locale.slice(start, end);
}

function translations(name) {
  const rows = tableBody(name).matchAll(/^\s*\[("(?:[^"\\]|\\.)*")\]\s*=\s*("(?:[^"\\]|\\.)*"),/gm);
  return new Map(Array.from(rows, ([, key, text]) => [JSON.parse(key), JSON.parse(text)]));
}

// Keep the slot order in sync with GuideText in Locale.lua.
function skeleton(text) {
  let count = 0;
  const slot = value => ++count <= 26 ? '{' + String.fromCharCode(64 + count) + '}' : value;
  return text.replace(/\|cRXP_([A-Z]+)_.*?\|r/g, (all, kind) =>
    ['FRIENDLY', 'ENEMY', 'LOOT', 'PICK'].includes(kind) ? slot(all) : all)
    .replace(/\|T.*?\|t/g, slot)
    .replace(/\[.*?\]/g, slot)
    .replace(/\d+\.\d+/g, slot)
    .replace(/\d+/g, slot);
}

const groups = new Set(Array.from(tableBody('groups').matchAll(/\[("(?:[^"\\]|\\.)*")\]\s*=\s*true/g), m => JSON.parse(m[1])));
const titleTranslations = translations('titles');
const names = translations('names');
const templates = translations('phrases');
const literals = translations('literals');
const unused = {
  titles: new Set(titleTranslations.keys()), phrases: new Set(templates.keys()), literals: new Set(literals.keys()),
};
const checked = new Set();
const placeholders = s => (s.match(/\{[A-Z]\}/g) || []).sort().join('');
const neutral = s => /^[\s\d=.,]+$/.test(s) || /^\|T.*?\|t(?:\[.*\])?$/.test(s);
let problems = 0, steps = 0, chapters = 0, placementCount = 0;
function issue(file, message) {
  console.log(file + ' ' + message);
  problems++;
}

for (const file of files) {
  const raw = fs.readFileSync(path.join(root, file), 'utf8');
  for (const block of raw.matchAll(/\[\[([\s\S]*?)\]\]/g)) {
    if (!/^\s*#name\s+/m.test(block[1])) continue;
    chapters++;
    const firstLine = raw.slice(0, block.index).split('\n').length;
    for (const [offset, row] of block[1].split(/\r?\n/).entries()) {
      const location = file + ':' + (firstLine + offset);
      const line = row.replace(/--.*$/, '').trim().split(/\s*<<\s*/)[0].trimEnd();
      const header = line.match(/^#(name|displayname|group)\s+(.+)$/);
      if (header) {
        if (header[1] === 'group') {
          if (!groups.has(header[2])) issue(location, 'Guide group has no German localization: ' + header[2]);
        } else {
          if (!titleTranslations.get(header[2])) issue(location, 'Title has no German localization: ' + header[2]);
          unused.titles.delete(header[2]);
        }
        continue;
      }
      if (/^step\b/.test(line)) steps++;
      const tag = line.match(/^\.(\S+)/)?.[1] || '';
      const text = line.match(/>>\s*(.+)$/)?.[1] || line.match(/^[+*](.+)$/)?.[1]?.replaceAll('\\n', '\n');
      if (!text || text.startsWith('/') || ['accept', 'turnin', 'macro'].includes(tag)) continue;
      placementCount++;
      if (checked.has(text)) continue;
      checked.add(text);
      for (const label of text.matchAll(/\[([^\]\n]+)\]|\|cRXP_(?:LOOT|PICK)_([^|\n]+)\|r/g)) {
        const name = (label[1] ?? label[2]).replace(/^\|cRXP_[A-Z]+_(.*?)\|r$/, '$1');
        if (!names.has(name)) issue(location, 'Label has no German localization: ' + name);
      }
      if (literals.has(text)) {
        unused.literals.delete(text);
        continue;
      }
      const key = skeleton(text);
      if (templates.has(key)) {
        if (unused.phrases.delete(key) && placeholders(key) !== placeholders(templates.get(key))) {
          issue(location, 'Placeholder mismatch: ' + key);
        }
      } else if (!neutral(text) && !/^(?:\{[A-Z]\}){1,2}$/.test(key)) {
        issue(location, 'Text has no German localization: ' + text);
      }
    }
  }
}
for (const [kind, entries] of Object.entries(unused)) {
  for (const key of entries) issue(localePath, 'Unused ' + kind + ' entry: ' + key);
}
console.log(files.length + ' guide files, ' + chapters + ' chapters, ' + steps + ' steps, ' +
  placementCount + ' instruction texts, ' + problems + ' differences');
process.exitCode = problems ? 1 : 0;
