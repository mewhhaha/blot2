import { dirname, join } from "node:path";
import type {
  DocCodeBlock,
  DocEffect,
  DocModule,
  DocPackage,
  DocTrait,
  DocType,
  DocValue,
  SymbolResolver,
} from "./doc.ts";

export interface PrecompiledDocExample {
  id: string;
  wasmBase64: string;
  entry: string | null;
  resultType: string | null;
  isText: boolean;
  expected: string | null;
  isTestSuite: boolean;
  tests?: readonly {
    exportName: string;
    displayName: string;
    kind: "check" | "trap";
  }[];
  error?: string;
}

export interface HtmlDocOptions {
  outDir: string;
  examples?: ReadonlyMap<string, PrecompiledDocExample>;
  title?: string;
}

export function escapeHtml(text: string): string {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function escapeAttr(text: string): string {
  return escapeHtml(text);
}

function slugifyHeading(text: string): string {
  return text
    .toLowerCase()
    .replace(/`([^`]+)`/g, "$1")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "section";
}

/** Lightweight syntax highlighter for Squid code blocks (HTML-safe). */
export function highlightSquidHtml(code: string): string {
  const keywords = new Set([
    "type",
    "is",
    "data",
    "opaque",
    "trait",
    "effect",
    "impl",
    "for",
    "func",
    "const",
    "let",
    "return",
    "if",
    "then",
    "else",
    "case",
    "of",
    "in",
    "import",
    "export",
    "from",
    "as",
    "private",
    "where",
    "own",
    "and",
    "or",
    "not",
    "true",
    "false",
    "break",
    "continue",
    "ever",
    "handler",
    "use",
    "do",
    "test",
    "expect_trap",
    "spark",
    "kernel",
    "process",
    "self",
    "forall",
    "exists",
  ]);
  let out = "";
  let i = 0;
  const n = code.length;
  while (i < n) {
    const ch = code[i];
    // Line comment
    if (ch === "/" && code[i + 1] === "/") {
      let end = i + 2;
      while (end < n && code[end] !== "\n") end++;
      out += `<span class="tok-com">${escapeHtml(code.slice(i, end))}</span>`;
      i = end;
      continue;
    }
    // String literal
    if (ch === '"') {
      let end = i + 1;
      while (end < n && code[end] !== '"') {
        if (code[end] === "\\" && end + 1 < n) end += 2;
        else end++;
      }
      if (end < n) end++;
      out += `<span class="tok-str">${escapeHtml(code.slice(i, end))}</span>`;
      i = end;
      continue;
    }
    // Constructor $Name
    if (ch === "$" && i + 1 < n && /[A-Z]/.test(code[i + 1])) {
      let end = i + 1;
      while (end < n && /[A-Za-z0-9_]/.test(code[end])) end++;
      out += `<span class="tok-ctor">${escapeHtml(code.slice(i, end))}</span>`;
      i = end;
      continue;
    }
    // Intrinsic @name.op or modifier #kernel / #process / #if
    if (
      (ch === "@" || ch === "#") && i + 1 < n && /[A-Za-z_]/.test(code[i + 1])
    ) {
      let end = i + 1;
      while (end < n && /[A-Za-z0-9_.]/.test(code[end])) end++;
      out += `<span class="tok-meta">${escapeHtml(code.slice(i, end))}</span>`;
      i = end;
      continue;
    }
    // Number literal
    if (/[0-9]/.test(ch)) {
      let end = i + 1;
      if (ch === "0" && (code[end] === "x" || code[end] === "X")) {
        end++;
        while (end < n && /[0-9A-Fa-f_]/.test(code[end])) end++;
      } else {
        while (end < n && /[0-9_]/.test(code[end])) end++;
        if (code[end] === "." && end + 1 < n && /[0-9]/.test(code[end + 1])) {
          end++;
          while (end < n && /[0-9_]/.test(code[end])) end++;
        }
        if (code[end] === "e" || code[end] === "E") {
          end++;
          if (code[end] === "+" || code[end] === "-") end++;
          while (end < n && /[0-9_]/.test(code[end])) end++;
        }
      }
      out += `<span class="tok-num">${escapeHtml(code.slice(i, end))}</span>`;
      i = end;
      continue;
    }
    // Identifier / keyword / Type
    if (/[A-Za-z_]/.test(ch)) {
      let end = i + 1;
      while (end < n && /[A-Za-z0-9_]/.test(code[end])) end++;
      const word = code.slice(i, end);
      const lineStart = code.lastIndexOf("\n", i - 1) + 1;
      const beforeWord = code.slice(lineStart, i);
      const isDeclIo = word === "io" &&
        /^[ \t]*(?:private[ \t]+)?$/.test(beforeWord) &&
        /[ \t]/.test(code[end] ?? "");
      if (keywords.has(word) || isDeclIo) {
        out += `<span class="tok-kw">${escapeHtml(word)}</span>`;
      } else if (/^[A-Z]/.test(word)) {
        out += `<span class="tok-ty">${escapeHtml(word)}</span>`;
      } else {
        out += escapeHtml(word);
      }
      i = end;
      continue;
    }
    out += escapeHtml(ch);
    i++;
  }
  return out;
}

function renderInlineMarkdownHtml(
  text: string,
  resolveLink: SymbolResolver,
  currentModuleId: string,
): string {
  let out = "";
  let i = 0;
  const n = text.length;
  while (i < n) {
    // Inline code `...`
    if (text[i] === "`") {
      let ticks = 1;
      while (i + ticks < n && text[i + ticks] === "`") ticks++;
      const delim = "`".repeat(ticks);
      const close = text.indexOf(delim, i + ticks);
      if (close !== -1) {
        const inner = text.slice(i + ticks, close);
        out += `<code>${escapeHtml(inner)}</code>`;
        i = close + ticks;
        continue;
      }
    }
    // Shorthand intra-doc link [`Target`]
    if (text[i] === "[" && text[i + 1] === "`") {
      const closeTick = text.indexOf("`]", i + 2);
      if (closeTick !== -1 && text[closeTick + 2] !== "(") {
        const target = text.slice(i + 2, closeTick).trim();
        const resolved = resolveLink(target, currentModuleId);
        if (resolved) {
          out += `<a class="sym-link" href="${
            escapeAttr(resolved.htmlHref)
          }"><code>${escapeHtml(target)}</code></a>`;
        } else {
          out += `<code class="sym-unresolved">${escapeHtml(target)}</code>`;
        }
        i = closeTick + 2;
        continue;
      }
    }
    // Markdown link [label](dest) (including [label](`Symbol`) and [label](squid:Symbol))
    if (text[i] === "[") {
      const closeBracket = findMatchingBracket(text, i);
      if (closeBracket !== -1 && text[closeBracket + 1] === "(") {
        const closeParen = text.indexOf(")", closeBracket + 2);
        if (closeParen !== -1) {
          const labelRaw = text.slice(i + 1, closeBracket);
          const destRaw = text.slice(closeBracket + 2, closeParen).trim();
          const labelHtml = renderInlineMarkdownHtml(
            labelRaw,
            resolveLink,
            currentModuleId,
          );
          if (
            (destRaw.startsWith("`") && destRaw.endsWith("`") &&
              destRaw.length > 2) ||
            destRaw.startsWith("squid:")
          ) {
            const sym = destRaw.startsWith("squid:")
              ? destRaw.slice(5).trim()
              : destRaw.slice(1, -1).trim();
            const resolved = resolveLink(sym, currentModuleId);
            if (resolved) {
              out += `<a class="sym-link" href="${
                escapeAttr(resolved.htmlHref)
              }">${labelHtml}</a>`;
            } else {
              out += `<span class="sym-unresolved">${labelHtml}</span>`;
            }
          } else if (isSafeHref(destRaw)) {
            const external = /^https?:\/\//i.test(destRaw);
            const attrs = external
              ? ` target="_blank" rel="noopener noreferrer"`
              : "";
            out += `<a href="${escapeAttr(destRaw)}"${attrs}>${labelHtml}</a>`;
          } else {
            out += labelHtml;
          }
          i = closeParen + 1;
          continue;
        }
      }
    }
    // Bold **...**
    if (text[i] === "*" && text[i + 1] === "*") {
      const close = text.indexOf("**", i + 2);
      if (close !== -1) {
        out += `<strong>${
          renderInlineMarkdownHtml(
            text.slice(i + 2, close),
            resolveLink,
            currentModuleId,
          )
        }</strong>`;
        i = close + 2;
        continue;
      }
    }
    // Italic *...*
    if (text[i] === "*" && text[i + 1] !== " ") {
      const close = text.indexOf("*", i + 1);
      if (close !== -1 && close > i + 1 && text[close - 1] !== " ") {
        out += `<em>${
          renderInlineMarkdownHtml(
            text.slice(i + 1, close),
            resolveLink,
            currentModuleId,
          )
        }</em>`;
        i = close + 1;
        continue;
      }
    }
    // Strikethrough ~~...~~
    if (text[i] === "~" && text[i + 1] === "~") {
      const close = text.indexOf("~~", i + 2);
      if (close !== -1) {
        out += `<del>${
          renderInlineMarkdownHtml(
            text.slice(i + 2, close),
            resolveLink,
            currentModuleId,
          )
        }</del>`;
        i = close + 2;
        continue;
      }
    }
    out += escapeHtml(text[i]);
    i++;
  }
  return out;
}

function findMatchingBracket(text: string, openIndex: number): number {
  let depth = 0;
  let inCode = false;
  for (let i = openIndex; i < text.length; i++) {
    const ch = text[i];
    if (ch === "`") {
      inCode = !inCode;
      continue;
    }
    if (inCode) continue;
    if (ch === "[") depth++;
    else if (ch === "]") {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function isSafeHref(href: string): boolean {
  const lower = href.trim().toLowerCase();
  if (
    lower.startsWith("javascript:") || lower.startsWith("data:") ||
    lower.startsWith("vbscript:")
  ) {
    return false;
  }
  return true;
}

export function renderMarkdownHtml(
  markdown: string,
  currentModuleId: string,
  resolveLink: SymbolResolver,
  codeBlocks: readonly DocCodeBlock[],
  examples?: ReadonlyMap<string, PrecompiledDocExample>,
): string {
  if (!markdown.trim()) return "";
  const lines = markdown.replace(/\r\n?/g, "\n").split("\n");
  const out: string[] = [];
  let blockCursor = 0;
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) {
      i++;
      continue;
    }
    // Fenced code block
    const fenceMatch = line.match(/^(`{3,}|~{3,})\s*(.*)$/);
    if (fenceMatch) {
      const fence = fenceMatch[1];
      const info = fenceMatch[2].trim();
      const lang = (info.split(/[\s,]+/)[0] ?? "").toLowerCase();
      const bodyLines: string[] = [];
      i++;
      while (i < lines.length && !lines[i].startsWith(fence)) {
        bodyLines.push(lines[i]);
        i++;
      }
      if (i < lines.length) i++;
      const code = bodyLines.join("\n");
      const matchedBlock = lang === "squid"
        ? codeBlocks[blockCursor++]
        : undefined;
      const precompiled = matchedBlock
        ? examples?.get(matchedBlock.id)
        : undefined;
      const codeHtml = lang === "squid"
        ? highlightSquidHtml(code)
        : escapeHtml(code);
      if (precompiled && !precompiled.error) {
        const badge = precompiled.isTestSuite
          ? "runnable test"
          : "runnable example";
        out.push(
          `<div class="code-example" data-example-id="${
            escapeAttr(precompiled.id)
          }">` +
            `<div class="code-toolbar">` +
            `<span class="code-lang">squid · ${badge}</span>` +
            `<div class="code-actions">` +
            `<button type="button" class="btn-run" data-run-example="${
              escapeAttr(precompiled.id)
            }">▶ Run</button>` +
            `<button type="button" class="btn-copy" data-copy-code>Copy</button>` +
            `</div></div>` +
            `<pre><code class="lang-squid">${codeHtml}</code></pre>` +
            `<div class="example-output" hidden></div>` +
            `</div>`,
        );
      } else {
        const modeLabel = matchedBlock && matchedBlock.mode !== "run"
          ? ` (${matchedBlock.mode})`
          : "";
        out.push(
          `<div class="code-block">` +
            `<div class="code-toolbar">` +
            `<span class="code-lang">${
              escapeHtml(lang || "text")
            }${modeLabel}</span>` +
            `<button type="button" class="btn-copy" data-copy-code>Copy</button>` +
            `</div>` +
            `<pre><code class="lang-${
              escapeAttr(lang || "text")
            }">${codeHtml}</code></pre>` +
            `</div>`,
        );
      }
      continue;
    }

    // Headings
    const headingMatch = line.match(/^(#{1,6})\s+(.+?)\s*#*$/);
    if (headingMatch) {
      const level = Math.min(6, headingMatch[1].length + 1);
      const rawText = headingMatch[2];
      const id = slugifyHeading(rawText);
      out.push(
        `<h${level} id="${escapeAttr(id)}">${
          renderInlineMarkdownHtml(rawText, resolveLink, currentModuleId)
        }</h${level}>`,
      );
      i++;
      continue;
    }

    // Horizontal rule
    if (/^(?:[-*_]\s*){3,}$/.test(line.trim())) {
      out.push("<hr>");
      i++;
      continue;
    }

    // Blockquote / GitHub callout
    if (line.trimStart().startsWith(">")) {
      const quoteLines: string[] = [];
      while (i < lines.length && lines[i].trimStart().startsWith(">")) {
        quoteLines.push(lines[i].replace(/^\s*>\s?/, ""));
        i++;
      }
      const first = quoteLines[0] ?? "";
      const alertMatch = first.match(
        /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]$/i,
      );
      if (alertMatch) {
        const kind = alertMatch[1].toLowerCase();
        const body = renderMarkdownHtml(
          quoteLines.slice(1).join("\n"),
          currentModuleId,
          resolveLink,
          [],
          undefined,
        );
        out.push(
          `<aside class="callout callout-${kind}"><div class="callout-title">${
            escapeHtml(alertMatch[1].toUpperCase())
          }</div>${body}</aside>`,
        );
      } else {
        const body = renderMarkdownHtml(
          quoteLines.join("\n"),
          currentModuleId,
          resolveLink,
          [],
          undefined,
        );
        out.push(`<blockquote>${body}</blockquote>`);
      }
      continue;
    }

    // GFM Table
    if (
      line.includes("|") && i + 1 < lines.length &&
      /^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(lines[i + 1])
    ) {
      const parseRow = (row: string): string[] =>
        row.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) =>
          c.trim()
        );
      const headers = parseRow(line);
      i += 2;
      const rows: string[][] = [];
      while (i < lines.length && lines[i].trim() && lines[i].includes("|")) {
        rows.push(parseRow(lines[i]));
        i++;
      }
      const headHtml = headers.map((h) =>
        `<th>${renderInlineMarkdownHtml(h, resolveLink, currentModuleId)}</th>`
      ).join("");
      const bodyHtml = rows.map((r) =>
        `<tr>${
          headers.map((_, idx) =>
            `<td>${
              renderInlineMarkdownHtml(
                r[idx] ?? "",
                resolveLink,
                currentModuleId,
              )
            }</td>`
          ).join("")
        }</tr>`
      ).join("");
      out.push(
        `<div class="table-wrap"><table><thead><tr>${headHtml}</tr></thead><tbody>${bodyHtml}</tbody></table></div>`,
      );
      continue;
    }

    // Unordered or ordered list
    const ulMatch = line.match(/^\s*[-*+]\s+(.*)$/);
    const olMatch = line.match(/^\s*\d+\.\s+(.*)$/);
    if (ulMatch || olMatch) {
      const ordered = Boolean(olMatch);
      const tag = ordered ? "ol" : "ul";
      const items: string[] = [];
      const itemRe = ordered ? /^\s*\d+\.\s+(.*)$/ : /^\s*[-*+]\s+(.*)$/;
      while (i < lines.length) {
        const m = lines[i].match(itemRe);
        if (!m) break;
        const itemParts = [m[1]];
        i++;
        while (
          i < lines.length && lines[i].trim() && !itemRe.test(lines[i]) &&
          /^\s{2,}/.test(lines[i])
        ) {
          itemParts.push(lines[i].trim());
          i++;
        }
        items.push(
          `<li>${
            renderInlineMarkdownHtml(
              itemParts.join(" "),
              resolveLink,
              currentModuleId,
            )
          }</li>`,
        );
      }
      out.push(`<${tag}>${items.join("")}</${tag}>`);
      continue;
    }

    // Paragraph
    const para: string[] = [];
    while (
      i < lines.length && lines[i].trim() &&
      !/^(`{3,}|~{3,})/.test(lines[i]) &&
      !/^#{1,6}\s+/.test(lines[i]) &&
      !lines[i].trimStart().startsWith(">") &&
      !/^\s*(?:[-*+]|\d+\.)\s+/.test(lines[i])
    ) {
      para.push(lines[i].trim());
      i++;
    }
    out.push(
      `<p>${
        renderInlineMarkdownHtml(para.join(" "), resolveLink, currentModuleId)
      }</p>`,
    );
  }
  return out.join("\n");
}

function moduleHtmlPath(modId: string): string {
  return `modules/${modId}.html`;
}

function relativeRootPrefix(modId: string): string {
  const depth = modId.split("/").length; // inside modules/
  return "../".repeat(depth);
}

function renderSidebar(
  pkg: DocPackage,
  activeModuleId: string | null,
  rootPrefix: string,
): string {
  const links = pkg.modules.map((mod) => {
    const active = mod.id === activeModuleId ? ' class="active"' : "";
    return `<li><a${active} href="${rootPrefix}${
      escapeAttr(moduleHtmlPath(mod.id))
    }">${escapeHtml(mod.importPath)}</a></li>`;
  }).join("\n");
  return `<nav class="sidebar" aria-label="Modules">
  <div class="sidebar-brand">
    <a href="${rootPrefix}index.html">${escapeHtml(pkg.name)}</a>
    <span class="badge">squid doc</span>
  </div>
  <div class="search-box">
    <input id="doc-search" type="search" placeholder="Search symbols (/)..." autocomplete="off" aria-label="Search symbols">
    <div id="search-results" class="search-results" hidden></div>
  </div>
  <div class="sidebar-section">Modules</div>
  <ul class="module-list">${links}</ul>
</nav>`;
}

function renderValueSection(
  val: DocValue,
  mod: DocModule,
  resolveLink: SymbolResolver,
  examples?: ReadonlyMap<string, PrecompiledDocExample>,
): string {
  const badges: string[] = [];
  if (val.modifier) {
    const label = val.modifier === "io" ? "io" : `#${val.modifier}`;
    badges.push(
      `<span class="pill pill-mod">${escapeHtml(label)}</span>`,
    );
  }
  if (val.private) badges.push(`<span class="pill pill-priv">private</span>`);
  const docHtml = renderMarkdownHtml(
    val.doc,
    mod.id,
    resolveLink,
    val.codeBlocks,
    examples,
  );
  return `<article class="item" id="${escapeAttr(val.anchor)}">
  <div class="item-header">
    <span class="item-kind kind-${escapeAttr(val.kind)}">${
    escapeHtml(val.kind)
  }</span>
    <a class="item-name" href="#${escapeAttr(val.anchor)}">${
    escapeHtml(val.name)
  }</a>
    ${badges.join(" ")}
  </div>
  <pre class="signature"><code>${highlightSquidHtml(val.signature)}</code></pre>
  ${docHtml ? `<div class="item-doc">${docHtml}</div>` : ""}
</article>`;
}

function renderTypeSection(
  ty: DocType,
  mod: DocModule,
  resolveLink: SymbolResolver,
  examples?: ReadonlyMap<string, PrecompiledDocExample>,
): string {
  const headerParams = ty.params.length ? ` ${ty.params.join(" ")}` : "";
  let sig = `type ${ty.name}${headerParams}`;
  if (ty.kind === "opaque") sig += " is opaque";
  else if (ty.kind === "alias" && ty.alias) sig += ` = ${ty.alias}`;
  else sig += " is data";

  const docHtml = renderMarkdownHtml(
    ty.doc,
    mod.id,
    resolveLink,
    ty.codeBlocks,
    examples,
  );

  let bodyHtml = "";
  if (ty.opaque) {
    bodyHtml +=
      `<p class="opaque-note">Opaque type: representation and constructors are private to this module.</p>`;
  } else if (ty.constructors.length > 0) {
    const ctors = ty.constructors.map((c) => {
      const cdoc = c.doc
        ? `<div class="sub-doc">${
          renderMarkdownHtml(c.doc, mod.id, resolveLink, [], undefined)
        }</div>`
        : "";
      if (c.fields.length > 0) {
        const fields = c.fields.map((f) => {
          const def = f.hasDefault
            ? ' <span class="pill pill-def">default</span>'
            : "";
          const fdoc = f.doc
            ? `<div class="field-doc">${
              renderInlineMarkdownHtml(f.doc, resolveLink, mod.id)
            }</div>`
            : "";
          return `<li><code>${escapeHtml(f.name)}: ${
            highlightSquidHtml(f.type)
          }</code>${def}${fdoc}</li>`;
        }).join("\n");
        return `<div class="ctor"><div class="ctor-head"><code>$${
          escapeHtml(c.name)
        }</code></div>${cdoc}<ul class="field-list">${fields}</ul></div>`;
      }
      const pay = c.payload ? ` ${highlightSquidHtml(c.payload)}` : "";
      return `<div class="ctor"><div class="ctor-head"><code>$${
        escapeHtml(c.name)
      }${pay}</code></div>${cdoc}</div>`;
    }).join("\n");
    bodyHtml += `<div class="sub-section"><h4>Constructors</h4>${ctors}</div>`;
  }

  if (ty.methods.length > 0) {
    const methodsHtml = ty.methods.map((m) =>
      renderValueSection(m, mod, resolveLink, examples)
    ).join("\n");
    bodyHtml +=
      `<div class="sub-section"><h4>Associated Members</h4>${methodsHtml}</div>`;
  }

  return `<article class="item" id="${escapeAttr(ty.anchor)}">
  <div class="item-header">
    <span class="item-kind kind-type">${escapeHtml(ty.kind)}</span>
    <a class="item-name" href="#${escapeAttr(ty.anchor)}">${
    escapeHtml(ty.name)
  }</a>
    ${ty.private ? '<span class="pill pill-priv">private</span>' : ""}
  </div>
  <pre class="signature"><code>${highlightSquidHtml(sig)}</code></pre>
  ${docHtml ? `<div class="item-doc">${docHtml}</div>` : ""}
  ${bodyHtml}
</article>`;
}

function renderTraitSection(
  tr: DocTrait,
  mod: DocModule,
  resolveLink: SymbolResolver,
  examples?: ReadonlyMap<string, PrecompiledDocExample>,
): string {
  const params = tr.params.length ? ` ${tr.params.join(" ")}` : "";
  const whereClause = tr.where.length
    ? ` where { ${tr.where.join(", ")} }`
    : "";
  const sig = `type ${tr.name}${params} is trait${whereClause}`;
  const docHtml = renderMarkdownHtml(
    tr.doc,
    mod.id,
    resolveLink,
    tr.codeBlocks,
    examples,
  );
  const membersHtml = tr.members.length
    ? `<div class="sub-section"><h4>Members</h4><ul class="field-list">${
      tr.members.map((m) => {
        const ty = m.type ? `: ${highlightSquidHtml(m.type)}` : "";
        return `<li><span class="pill">${escapeHtml(m.kind)}</span> <code>${
          escapeHtml(m.name)
        }${ty}</code></li>`;
      }).join("\n")
    }</ul></div>`
    : "";
  return `<article class="item" id="${escapeAttr(tr.anchor)}">
  <div class="item-header">
    <span class="item-kind kind-trait">trait</span>
    <a class="item-name" href="#${escapeAttr(tr.anchor)}">${
    escapeHtml(tr.name)
  }</a>
  </div>
  <pre class="signature"><code>${highlightSquidHtml(sig)}</code></pre>
  ${docHtml ? `<div class="item-doc">${docHtml}</div>` : ""}
  ${membersHtml}
</article>`;
}

function renderEffectSection(
  eff: DocEffect,
  mod: DocModule,
  resolveLink: SymbolResolver,
  examples?: ReadonlyMap<string, PrecompiledDocExample>,
): string {
  const params = eff.params.length ? ` ${eff.params.join(" ")}` : "";
  const sig = eff.callable && eff.operations.length === 1
    ? `effect ${eff.name}${params}: ${eff.operations[0].parameter} -> ${
      eff.operations[0].result
    }`
    : `type ${eff.name}${params} is effect`;
  const docHtml = renderMarkdownHtml(
    eff.doc,
    mod.id,
    resolveLink,
    eff.codeBlocks,
    examples,
  );
  const opsHtml = !eff.callable && eff.operations.length > 0
    ? `<div class="sub-section"><h4>Operations</h4><ul class="field-list">${
      eff.operations.map((op) =>
        `<li><code>${escapeHtml(op.name)}: ${
          highlightSquidHtml(`${op.parameter} -> ${op.result}`)
        }</code></li>`
      ).join("\n")
    }</ul></div>`
    : "";
  return `<article class="item" id="${escapeAttr(eff.anchor)}">
  <div class="item-header">
    <span class="item-kind kind-effect">effect</span>
    <a class="item-name" href="#${escapeAttr(eff.anchor)}">${
    escapeHtml(eff.name)
  }</a>
  </div>
  <pre class="signature"><code>${highlightSquidHtml(sig)}</code></pre>
  ${docHtml ? `<div class="item-doc">${docHtml}</div>` : ""}
  ${opsHtml}
</article>`;
}

function renderPageShell(
  title: string,
  rootPrefix: string,
  sidebarHtml: string,
  mainHtml: string,
): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <link rel="stylesheet" href="${rootPrefix}style.css">
</head>
<body data-root="${escapeAttr(rootPrefix)}">
  <div class="layout">
    ${sidebarHtml}
    <main class="content">
      ${mainHtml}
    </main>
  </div>
  <script src="${rootPrefix}search-index.js"></script>
  <script src="${rootPrefix}examples.js"></script>
  <script src="${rootPrefix}runner.js"></script>
  <script src="${rootPrefix}search.js"></script>
</body>
</html>
`;
}

export const DOC_CSS = `:root {
  --bg: #ffffff;
  --bg-alt: #f6f8fa;
  --bg-code: #f3f5f8;
  --fg: #1f2328;
  --muted: #59636e;
  --border: #d0d7de;
  --accent: #0969da;
  --accent-soft: #ddf4ff;
  --ok: #1a7f37;
  --err: #cf222e;
  --kw: #cf222e;
  --ty: #0550ae;
  --ctor: #8250df;
  --str: #0a3069;
  --num: #0550ae;
  --com: #6e7781;
  --meta: #953800;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117;
    --bg-alt: #161b22;
    --bg-code: #161b22;
    --fg: #e6edf3;
    --muted: #8b949e;
    --border: #30363d;
    --accent: #58a6ff;
    --accent-soft: #1f334d;
    --ok: #3fb950;
    --err: #f85149;
    --kw: #ff7b72;
    --ty: #79c0ff;
    --ctor: #d2a8ff;
    --str: #a5d6ff;
    --num: #79c0ff;
    --com: #8b949e;
    --meta: #ffa657;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: var(--bg);
  color: var(--fg);
  line-height: 1.6;
}
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
code, pre {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.9em;
}
code {
  background: var(--bg-code);
  padding: 0.12em 0.36em;
  border-radius: 4px;
}
pre {
  background: var(--bg-code);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 0.9rem 1rem;
  overflow-x: auto;
  margin: 0.6rem 0;
}
pre code { background: none; padding: 0; font-size: 0.88rem; }
.layout { display: flex; min-height: 100vh; }
.sidebar {
  width: 270px;
  flex-shrink: 0;
  border-right: 1px solid var(--border);
  background: var(--bg-alt);
  padding: 1.25rem 1rem;
  position: sticky;
  top: 0;
  max-height: 100vh;
  overflow-y: auto;
}
.sidebar-brand {
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-weight: 700;
  font-size: 1.1rem;
  margin-bottom: 1rem;
}
.badge {
  font-size: 0.72rem;
  padding: 0.15rem 0.45rem;
  border-radius: 999px;
  background: var(--accent-soft);
  color: var(--accent);
  font-weight: 600;
}
.search-box { position: relative; margin-bottom: 1rem; }
#doc-search {
  width: 100%;
  padding: 0.45rem 0.65rem;
  border: 1px solid var(--border);
  border-radius: 6px;
  background: var(--bg);
  color: var(--fg);
  font-size: 0.9rem;
}
.search-results {
  position: absolute;
  left: 0;
  right: 0;
  top: 2.4rem;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 8px;
  box-shadow: 0 8px 24px rgba(0,0,0,0.18);
  max-height: 340px;
  overflow-y: auto;
  z-index: 20;
}
.search-item {
  display: block;
  padding: 0.45rem 0.65rem;
  border-bottom: 1px solid var(--border);
  color: var(--fg);
}
.search-item:last-child { border-bottom: none; }
.search-item:hover { background: var(--bg-alt); text-decoration: none; }
.search-item-head { display: flex; gap: 0.4rem; align-items: center; }
.search-item-sig { color: var(--muted); font-size: 0.78rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sidebar-section {
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--muted);
  margin: 1rem 0 0.4rem;
}
.module-list { list-style: none; padding: 0; margin: 0; }
.module-list li { margin: 0.15rem 0; }
.module-list a {
  display: block;
  padding: 0.25rem 0.5rem;
  border-radius: 6px;
  color: var(--fg);
  font-size: 0.92rem;
}
.module-list a:hover { background: var(--border); text-decoration: none; }
.module-list a.active { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
.content {
  flex: 1;
  min-width: 0;
  max-width: 920px;
  padding: 2rem 2.5rem 4rem;
}
.mod-title { margin-top: 0; font-size: 1.9rem; border-bottom: 1px solid var(--border); padding-bottom: 0.5rem; }
.mod-summary { color: var(--muted); font-size: 0.9rem; margin-top: -0.25rem; }
.section-heading { margin-top: 2.2rem; font-size: 1.25rem; border-bottom: 1px solid var(--border); padding-bottom: 0.3rem; }
.item {
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 1rem 1.2rem;
  margin: 1rem 0;
  background: var(--bg);
}
.item-header { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; }
.item-kind {
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  padding: 0.12rem 0.45rem;
  border-radius: 5px;
  background: var(--bg-alt);
  border: 1px solid var(--border);
}
.kind-type { color: var(--ty); }
.kind-trait { color: var(--ctor); }
.kind-effect { color: var(--meta); }
.kind-func, .kind-kernel, .kind-process { color: var(--accent); }
.item-name { font-weight: 700; font-size: 1.08rem; color: var(--fg); }
.signature { margin: 0.6rem 0 0.7rem; background: var(--bg-alt); }
.pill {
  font-size: 0.72rem;
  padding: 0.08rem 0.4rem;
  border-radius: 999px;
  border: 1px solid var(--border);
  color: var(--muted);
}
.pill-mod { color: var(--meta); border-color: var(--meta); }
.pill-def { color: var(--ok); }
.sub-section { margin-top: 0.9rem; }
.sub-section h4 { margin: 0.5rem 0 0.4rem; font-size: 0.92rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.04em; }
.ctor { margin: 0.45rem 0; padding-left: 0.75rem; border-left: 2px solid var(--border); }
.field-list { margin: 0.35rem 0; padding-left: 1.2rem; }
.field-list li { margin: 0.25rem 0; }
.field-doc { color: var(--muted); font-size: 0.88rem; margin-top: 0.1rem; }
.opaque-note { color: var(--muted); font-style: italic; font-size: 0.9rem; }
.code-example, .code-block {
  border: 1px solid var(--border);
  border-radius: 8px;
  margin: 0.8rem 0;
  overflow: hidden;
  background: var(--bg-code);
}
.code-example pre, .code-block pre { border: none; border-radius: 0; margin: 0; }
.code-toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.35rem 0.7rem;
  background: var(--bg-alt);
  border-bottom: 1px solid var(--border);
  font-size: 0.78rem;
  color: var(--muted);
}
.code-actions { display: flex; gap: 0.4rem; }
.btn-run, .btn-copy {
  cursor: pointer;
  border: 1px solid var(--border);
  background: var(--bg);
  color: var(--fg);
  border-radius: 5px;
  padding: 0.18rem 0.55rem;
  font-size: 0.78rem;
  font-weight: 600;
}
.btn-run { background: var(--accent); color: #fff; border-color: var(--accent); }
.btn-run:hover { filter: brightness(1.08); }
.btn-copy:hover { background: var(--bg-code); }
.example-output {
  border-top: 1px solid var(--border);
  padding: 0.55rem 0.85rem;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.84rem;
  white-space: pre-wrap;
  background: var(--bg);
}
.example-output.ok { color: var(--ok); }
.example-output.err { color: var(--err); }
.callout {
  border-left: 4px solid var(--accent);
  background: var(--bg-alt);
  padding: 0.65rem 1rem;
  border-radius: 0 6px 6px 0;
  margin: 0.8rem 0;
}
.callout-warning, .callout-caution { border-left-color: var(--err); }
.callout-tip { border-left-color: var(--ok); }
.callout-title { font-weight: 700; font-size: 0.8rem; letter-spacing: 0.04em; margin-bottom: 0.25rem; }
.table-wrap { overflow-x: auto; margin: 0.8rem 0; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid var(--border); padding: 0.45rem 0.7rem; text-align: left; }
th { background: var(--bg-alt); }
.mod-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 1rem; margin-top: 1rem; }
.mod-card {
  display: block;
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 1rem;
  background: var(--bg);
  color: var(--fg);
}
.mod-card:hover { border-color: var(--accent); text-decoration: none; }
.mod-card h3 { margin: 0 0 0.35rem; color: var(--accent); font-size: 1.05rem; }
.mod-card p { margin: 0; color: var(--muted); font-size: 0.88rem; }
.tok-kw { color: var(--kw); font-weight: 600; }
.tok-ty { color: var(--ty); }
.tok-ctor { color: var(--ctor); }
.tok-str { color: var(--str); }
.tok-num { color: var(--num); }
.tok-com { color: var(--com); font-style: italic; }
.tok-meta { color: var(--meta); }
@media (max-width: 820px) {
  .layout { flex-direction: column; }
  .sidebar { width: 100%; position: static; max-height: none; border-right: none; border-bottom: 1px solid var(--border); }
  .content { padding: 1.25rem; }
}
`;

/**
 * Pure-JS browser ABI 8 + squid:traps v1 + BTST v1 runner for static HTML docs.
 * Works both on static HTTP hosts (GitHub Pages, etc.) and local file:// previews.
 */
export const DOC_RUNNER_JS = `(function () {
  var TRAP_SITE_OFFSET = 772;
  var BTST_MAGIC = 0x42545354;

  function decodeBase64(b64) {
    var bin = atob(b64);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function decodeText(words) {
    var parts = [];
    for (var i = 0; i < words.length; i++) {
      var cp = words[i];
      if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
        throw new Error("Invalid Unicode scalar: " + cp);
      }
      parts.push(String.fromCodePoint(cp));
    }
    return parts.join("");
  }

  function readTrapTable(mod) {
    var sections = WebAssembly.Module.customSections(mod, "squid:traps");
    if (!sections.length) return [];
    var bytes = new Uint8Array(sections[0]);
    if (bytes.length < 5 || bytes[0] !== 1) return [];
    var view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    var count = view.getUint32(1, true);
    var off = 5;
    var dec = new TextDecoder("utf-8");
    var entries = [];
    for (var i = 0; i < count && off + 17 <= bytes.length; i++) {
      var k = bytes[off++];
      var kind = k === 1 ? "panic" : k === 2 ? "bounds" : "unreachable";
      off += 12; // unit, start, end
      var len = view.getUint32(off, true);
      off += 4;
      var msg = dec.decode(bytes.subarray(off, off + len));
      off += len;
      entries.push({ kind: kind, message: msg });
    }
    return entries;
  }

  function formatTrap(err, traps, mem) {
    if (mem && mem.buffer.byteLength >= TRAP_SITE_OFFSET + 4 && traps.length) {
      var id = new DataView(mem.buffer).getUint32(TRAP_SITE_OFFSET, true);
      if (id >= 1 && id <= traps.length) {
        var t = traps[id - 1];
        if (t.kind === "panic") return t.message ? 'panic: "' + t.message + '"' : "panic";
        if (t.kind === "bounds") return t.message || "index out of bounds";
        return t.message ? "unreachable: " + t.message : "unreachable";
      }
    }
    return err && err.message ? err.message : String(err);
  }

  function readArray(mem, ptr, kind) {
    var view = new DataView(mem.buffer);
    var len = view.getUint32(ptr, true);
    if (kind === "Array F32") {
      var f = new Float32Array(len);
      for (var i = 0; i < len; i++) f[i] = view.getFloat32(ptr + 4 + i * 4, true);
      return f;
    }
    var u = new Uint32Array(len);
    for (var j = 0; j < len; j++) u[j] = view.getUint32(ptr + 4 + j * 4, true);
    return u;
  }

  function decodeBtst(words) {
    if (words.length < 4 || words[0] !== BTST_MAGIC || words[1] !== 1) return null;
    var passed = words[2];
    var failed = words[3];
    var off = 4;
    function str() {
      var len = words[off++];
      var s = decodeText(words.subarray(off, off + len));
      off += len;
      return s;
    }
    var failures = [];
    for (var i = 0; i < failed; i++) {
      failures.push({ group: str(), label: str(), message: str(), expected: str(), actual: str() });
    }
    return { passed: passed, failed: failed, failures: failures };
  }

  function formatF32(v) {
    if (!Number.isFinite(v)) return String(v);
    var s = String(Math.fround(v));
    return s.indexOf(".") === -1 && s.indexOf("e") === -1 ? s + ".0" : s;
  }

  async function runExample(spec) {
    var bytes = decodeBase64(spec.wasmBase64);
    var mod = await WebAssembly.compile(bytes);
    var traps = readTrapTable(mod);
    var inst = await WebAssembly.instantiate(mod, {});
    var exp = inst.exports;
    var mem = exp["squid:memory"] || exp.memory;
    var reset = exp["squid:reset"];
    var finish = exp["squid:finish_invocation"];

    if (spec.isTestSuite && spec.tests && spec.tests.length) {
      var passed = 0;
      var failed = 0;
      var lines = [];
      for (var i = 0; i < spec.tests.length; i++) {
        var t = spec.tests[i];
        if (typeof reset === "function") reset(0);
        try {
          exp[t.exportName]();
          if (typeof finish === "function") finish();
          if (t.kind === "trap") {
            failed++;
            lines.push("✗ " + t.displayName + " (expected trap, returned normally)");
          } else {
            passed++;
            lines.push("✓ " + t.displayName);
          }
        } catch (err) {
          if (t.kind === "trap") {
            passed++;
            lines.push("✓ " + t.displayName + " (trapped as expected: " + formatTrap(err, traps, mem) + ")");
          } else {
            failed++;
            lines.push("✗ " + t.displayName + " (" + formatTrap(err, traps, mem) + ")");
          }
        }
      }
      lines.push(passed + " passed, " + failed + " failed");
      return { ok: failed === 0, text: lines.join("\\n") };
    }

    if (typeof reset === "function") reset(0);
    try {
      var raw = exp[spec.entry]();
      if (typeof finish === "function") finish();
      var text = "()";
      if (spec.resultType === "U32") text = String(raw >>> 0);
      else if (spec.resultType === "Bool") text = raw ? "true" : "false";
      else if (spec.resultType === "F32") text = formatF32(raw);
      else if (spec.resultType === "Array U32") {
        var words = readArray(mem, raw >>> 0, "Array U32");
        var btst = decodeBtst(words);
        if (btst) {
          var summary = btst.passed + " passed, " + btst.failed + " failed";
          if (btst.failed > 0) {
            var errs = btst.failures.map(function (f) {
              return "✗ " + f.label + ": " + f.message;
            });
            return { ok: false, text: errs.concat([summary]).join("\\n") };
          }
          return { ok: true, text: "✓ " + summary };
        }
        text = spec.isText ? JSON.stringify(decodeText(words)) : "#[" + Array.from(words).join(", ") + "]";
      } else if (spec.resultType === "Array F32") {
        var floats = readArray(mem, raw >>> 0, "Array F32");
        text = "#[" + Array.from(floats).map(formatF32).join(", ") + "]";
      }
      var suffix = spec.expected ? "  (expected " + spec.expected + ")" : "";
      return { ok: true, text: "=> " + text + suffix };
    } catch (err) {
      return { ok: false, text: "trap: " + formatTrap(err, traps, mem) };
    }
  }

  if (typeof globalThis !== "undefined") {
    globalThis.__squidDocRunExample = runExample;
  }

  if (typeof document !== "undefined") {
    document.addEventListener("click", function (ev) {
      var target = ev.target;
      if (!target || !target.closest) return;
      var copyBtn = target.closest("[data-copy-code]");
      if (copyBtn) {
        var wrap = copyBtn.closest(".code-example, .code-block");
        var codeEl = wrap && wrap.querySelector("pre code");
        if (codeEl && navigator.clipboard) {
          navigator.clipboard.writeText(codeEl.textContent || "").then(function () {
            copyBtn.textContent = "Copied";
            setTimeout(function () { copyBtn.textContent = "Copy"; }, 1200);
          });
        }
        return;
      }
      var runBtn = target.closest("[data-run-example]");
      if (runBtn) {
        var id = runBtn.getAttribute("data-run-example");
        var box = runBtn.closest(".code-example");
        var outEl = box && box.querySelector(".example-output");
        var map = globalThis.__SQUID_DOC_EXAMPLES || {};
        var spec = map[id];
        if (!spec || !outEl) return;
        outEl.hidden = false;
        outEl.className = "example-output";
        outEl.textContent = "Running…";
        var t0 = performance.now();
        runExample(spec).then(function (res) {
          var ms = (performance.now() - t0).toFixed(1);
          outEl.className = "example-output " + (res.ok ? "ok" : "err");
          outEl.textContent = res.text + "  [" + ms + " ms]";
        }).catch(function (err) {
          outEl.className = "example-output err";
          outEl.textContent = "Error: " + (err && err.message ? err.message : String(err));
        });
      }
    });
  }
})();
`;

const DOC_SEARCH_JS = `(function () {
  var input = document.getElementById("doc-search");
  var box = document.getElementById("search-results");
  if (!input || !box) return;
  var root = document.body.getAttribute("data-root") || "";
  var items = globalThis.__SQUID_DOC_SEARCH || [];

  function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function render(query) {
    var q = query.trim().toLowerCase();
    if (!q) { box.hidden = true; box.innerHTML = ""; return; }
    var matches = [];
    for (var i = 0; i < items.length; i++) {
      var it = items[i];
      var hay = (it.name + " " + it.module + " " + it.signature + " " + it.summary).toLowerCase();
      var idx = hay.indexOf(q);
      if (idx !== -1) {
        var score = it.name.toLowerCase() === q ? 0 : it.name.toLowerCase().indexOf(q) === 0 ? 1 : idx;
        matches.push({ score: score, item: it });
      }
    }
    matches.sort(function (a, b) { return a.score - b.score; });
    matches = matches.slice(0, 20);
    if (!matches.length) {
      box.innerHTML = '<div class="search-item">No matching symbols</div>';
      box.hidden = false;
      return;
    }
    box.innerHTML = matches.map(function (m) {
      var it = m.item;
      return '<a class="search-item" href="' + esc(root + it.href) + '">' +
        '<div class="search-item-head"><span class="item-kind kind-' + esc(it.kind) + '">' + esc(it.kind) + '</span>' +
        '<strong>' + esc(it.name) + '</strong>' +
        '<span class="pill">' + esc(it.module) + '</span></div>' +
        '<div class="search-item-sig">' + esc(it.signature) + '</div></a>';
    }).join("");
    box.hidden = false;
  }

  input.addEventListener("input", function () { render(input.value); });
  document.addEventListener("keydown", function (ev) {
    if (ev.key === "/" && document.activeElement !== input) {
      ev.preventDefault();
      input.focus();
    } else if (ev.key === "Escape") {
      box.hidden = true;
      input.blur();
    }
  });
  document.addEventListener("click", function (ev) {
    if (!ev.target.closest || !ev.target.closest(".search-box")) {
      box.hidden = true;
    }
  });
})();
`;

function firstSentence(doc: string): string {
  const clean = doc
    .replace(/```[\s\S]*?```/g, "")
    .split("\n")
    .map((l) => l.trim())
    .find((l) => l && !l.startsWith("#") && !l.startsWith(">"));
  if (!clean) return "";
  return clean.length > 140 ? `${clean.slice(0, 137)}...` : clean;
}

export async function generateHtmlDocs(
  pkg: DocPackage,
  resolveLink: SymbolResolver,
  options: HtmlDocOptions,
): Promise<{ files: string[]; exampleCount: number }> {
  const { outDir, examples } = options;
  await Deno.mkdir(outDir, { recursive: true });
  const written: string[] = [];

  // Build client-side search index
  const searchEntries: Array<{
    name: string;
    kind: string;
    module: string;
    signature: string;
    summary: string;
    href: string;
  }> = [];
  for (const mod of pkg.modules) {
    const modHref = moduleHtmlPath(mod.id);
    searchEntries.push({
      name: mod.importPath,
      kind: "module",
      module: mod.importPath,
      signature: `module ${mod.importPath}`,
      summary: firstSentence(mod.doc),
      href: modHref,
    });
    for (const ty of mod.types) {
      searchEntries.push({
        name: ty.name,
        kind: "type",
        module: mod.importPath,
        signature: `type ${ty.name}${
          ty.params.length ? ` ${ty.params.join(" ")}` : ""
        } is ${ty.kind}`,
        summary: firstSentence(ty.doc),
        href: `${modHref}#${ty.anchor}`,
      });
      for (const m of ty.methods) {
        searchEntries.push({
          name: m.name,
          kind: m.kind,
          module: mod.importPath,
          signature: m.signature,
          summary: firstSentence(m.doc),
          href: `${modHref}#${m.anchor}`,
        });
      }
    }
    for (const tr of mod.traits) {
      searchEntries.push({
        name: tr.name,
        kind: "trait",
        module: mod.importPath,
        signature: `type ${tr.name} is trait`,
        summary: firstSentence(tr.doc),
        href: `${modHref}#${tr.anchor}`,
      });
    }
    for (const eff of mod.effects) {
      searchEntries.push({
        name: eff.name,
        kind: "effect",
        module: mod.importPath,
        signature: `effect ${eff.name}`,
        summary: firstSentence(eff.doc),
        href: `${modHref}#${eff.anchor}`,
      });
    }
    for (const val of mod.values) {
      searchEntries.push({
        name: val.name,
        kind: val.kind,
        module: mod.importPath,
        signature: val.signature,
        summary: firstSentence(val.doc),
        href: `${modHref}#${val.anchor}`,
      });
    }
  }

  const examplesObj: Record<string, PrecompiledDocExample> = Object.create(
    null,
  );
  let exampleCount = 0;
  if (examples) {
    for (const [id, spec] of examples.entries()) {
      if (!spec.error) {
        examplesObj[id] = spec;
        exampleCount++;
      }
    }
  }

  const writeFile = async (rel: string, content: string) => {
    const full = join(outDir, rel);
    await Deno.mkdir(dirname(full), { recursive: true });
    await Deno.writeTextFile(full, content);
    written.push(full);
  };

  await writeFile("style.css", DOC_CSS);
  await writeFile("runner.js", DOC_RUNNER_JS);
  await writeFile("search.js", DOC_SEARCH_JS);
  await writeFile(
    "search-index.js",
    `globalThis.__SQUID_DOC_SEARCH = ${JSON.stringify(searchEntries)};\n`,
  );
  await writeFile(
    "examples.js",
    `globalThis.__SQUID_DOC_EXAMPLES = ${JSON.stringify(examplesObj)};\n`,
  );

  // Render index.html
  const cards = pkg.modules.map((mod) => {
    const summary = firstSentence(mod.doc) ||
      `${mod.types.length} types · ${mod.values.length} values`;
    return `<a class="mod-card" href="${escapeAttr(moduleHtmlPath(mod.id))}">
  <h3>${escapeHtml(mod.importPath)}</h3>
  <p>${escapeHtml(summary)}</p>
</a>`;
  }).join("\n");

  const indexMain = `<h1 class="mod-title">${
    escapeHtml(options.title ?? pkg.name)
  }</h1>
<p class="mod-summary">${pkg.modules.length} module${
    pkg.modules.length === 1 ? "" : "s"
  }${
    exampleCount > 0
      ? ` · ${exampleCount} runnable WebAssembly example${
        exampleCount === 1 ? "" : "s"
      }`
      : ""
  }</p>
<div class="mod-grid">${cards}</div>`;

  await writeFile(
    "index.html",
    renderPageShell(
      `${options.title ?? pkg.name} — Squid Documentation`,
      "",
      renderSidebar(pkg, null, ""),
      indexMain,
    ),
  );

  // Render each module page
  for (const mod of pkg.modules) {
    const rootPrefix = relativeRootPrefix(mod.id);
    const modResolver: SymbolResolver = (target, fromId) => {
      const hit = resolveLink(target, fromId);
      if (!hit) return null;
      return {
        ...hit,
        htmlHref: hit.moduleId === mod.id && hit.anchor
          ? `#${hit.anchor}`
          : `${rootPrefix}${hit.htmlHref}`,
      };
    };

    const parts: string[] = [];
    parts.push(`<h1 class="mod-title">${escapeHtml(mod.importPath)}</h1>`);
    const counts = [
      mod.types.length ? `${mod.types.length} types` : "",
      mod.traits.length ? `${mod.traits.length} traits` : "",
      mod.effects.length ? `${mod.effects.length} effects` : "",
      mod.values.length ? `${mod.values.length} values` : "",
    ].filter(Boolean).join(" · ");
    if (counts) parts.push(`<p class="mod-summary">${counts}</p>`);

    const modDocHtml = renderMarkdownHtml(
      mod.doc,
      mod.id,
      modResolver,
      mod.codeBlocks,
      examples,
    );
    if (modDocHtml) {
      parts.push(`<section class="mod-doc">${modDocHtml}</section>`);
    }

    if (mod.types.length) {
      parts.push(`<h2 class="section-heading" id="types">Types</h2>`);
      for (const ty of mod.types) {
        parts.push(renderTypeSection(ty, mod, modResolver, examples));
      }
    }
    if (mod.traits.length) {
      parts.push(`<h2 class="section-heading" id="traits">Traits</h2>`);
      for (const tr of mod.traits) {
        parts.push(renderTraitSection(tr, mod, modResolver, examples));
      }
    }
    if (mod.effects.length) {
      parts.push(`<h2 class="section-heading" id="effects">Effects</h2>`);
      for (const eff of mod.effects) {
        parts.push(renderEffectSection(eff, mod, modResolver, examples));
      }
    }
    if (mod.values.length) {
      parts.push(
        `<h2 class="section-heading" id="values">Functions &amp; Values</h2>`,
      );
      for (const val of mod.values) {
        parts.push(renderValueSection(val, mod, modResolver, examples));
      }
    }
    if (mod.implementations.length) {
      parts.push(
        `<h2 class="section-heading" id="implementations">Implementations</h2>`,
      );
      parts.push(
        `<ul class="field-list">${
          mod.implementations.map((imp) => {
            const head = imp.head.join(" ");
            const wh = imp.where.length
              ? ` where { ${imp.where.join(", ")} }`
              : "";
            const sig = `impl ${imp.contract}${head ? ` ${head}` : ""}${wh}`;
            return `<li><code>${highlightSquidHtml(sig)}</code></li>`;
          }).join("\n")
        }</ul>`,
      );
    }

    await writeFile(
      moduleHtmlPath(mod.id),
      renderPageShell(
        `${mod.importPath} — ${options.title ?? pkg.name}`,
        rootPrefix,
        renderSidebar(pkg, mod.id, rootPrefix),
        parts.join("\n"),
      ),
    );
  }

  return { files: written, exampleCount };
}
