import fs from 'node:fs';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import textmate from 'vscode-textmate';
import oniguruma from 'vscode-oniguruma';
const require = createRequire(import.meta.url);
const root = fileURLToPath(new URL('../', import.meta.url));
await oniguruma.loadWASM(fs.readFileSync(require.resolve('vscode-oniguruma/release/onig.wasm')));
const registry = new textmate.Registry({
  onigLib: Promise.resolve({ createOnigScanner: patterns => new oniguruma.OnigScanner(patterns), createOnigString: value => new oniguruma.OnigString(value) }),
  loadGrammar: async scope => scope === 'source.blot.k1' ? textmate.parseRawGrammar(fs.readFileSync(new URL('blot.tmLanguage.json', import.meta.url), 'utf8'), 'blot.tmLanguage.json') : null,
});
const grammar = await registry.loadGrammar('source.blot.k1');
function scope(line, word) {
  const start = line.indexOf(word), end = start + word.length;
  assert(start >= 0);
  return grammar.tokenizeLine(line).tokens.find(token => token.startIndex <= start && token.endIndex >= end)?.scopes.join(' ');
}
assert.match(scope('import "./fn-return.blot" as helpers', './fn-return.blot'), /string\.quoted/);
assert.match(scope('// return fn', 'return'), /comment\.line/);
assert.match(scope('pub let apply: forall [T: Type] => T -> T', 'forall'), /keyword\.control/);
assert.match(scope('pub let apply: forall [T: Type] => T -> T', 'Type'), /storage\.type/);
assert.match(scope('return #Ok(1.5)', '#Ok'), /constant\.language\.variant/);
assert.match(scope('return #Ok(1.5)', '1.5'), /constant\.numeric/);
let files = 0;
function walk(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const path = `${directory}/${entry.name}`;
    if (entry.isDirectory()) { walk(path); continue; }
    if (!entry.name.endsWith('.blot')) continue;
    const source = fs.readFileSync(path, 'utf8');
    let state = textmate.INITIAL;
    for (const line of source.split('\n')) {
      const result = grammar.tokenizeLine(line, state); state = result.ruleStack;
      assert(result.tokens.every(token => token.startIndex >= 0 && token.endIndex >= token.startIndex));
    }
    const formatted = execFileSync(`${root}build/blot`, ['format', path], { cwd: root, encoding: 'utf8' });
    const temporary = `${root}build/editor-format.blot`;
    fs.writeFileSync(temporary, formatted);
    assert.equal(execFileSync(`${root}build/blot`, ['format', temporary], { cwd: root, encoding: 'utf8' }), formatted, `formatter not idempotent: ${path}`);
    files++;
  }
}
walk(`${root}examples`);
assert(files >= 20);
console.log(`EDITOR real TextMate/Oniguruma scopes and ${files} formatter round trips passed`);
