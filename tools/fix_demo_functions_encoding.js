const fs = require('fs');
const iconv = require('C:\\Users\\khali\\Desktop\\web\\admin_panel\\functions\\node_modules\\iconv-lite');

const targetPath = 'C:\\Users\\khali\\Desktop\\web\\admin_panel\\functions\\index.js';

let content = fs.readFileSync(targetPath, 'utf8');
if (content.charCodeAt(0) === 0xFEFF) {
  content = content.slice(1);
}

const fixed = iconv.decode(iconv.encode(content, 'win1252'), 'utf8');
fs.writeFileSync(targetPath, fixed, 'utf8');

console.log('functions index.js encoding fixed');
