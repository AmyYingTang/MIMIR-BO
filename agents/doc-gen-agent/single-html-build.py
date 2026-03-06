#!/usr/bin/env python3
"""
single-html-build.py — 将 doc-gen-agent 填充好的 md 文件合并为单文件 HTML

用法:
    python3 single-html-build.py <output_dir> <title> [--template <template.html>]

它做什么:
    1. 读取 fill-order.md 确定页面顺序
    2. 按顺序读取 docs/ 下的 .md 文件
    3. 将 Markdown 转为 HTML 片段（用 Python 内置能力，不依赖第三方库）
    4. 注入到 HTML 模板中，生成带侧边导航的单文件 HTML

输出:
    {output_dir}/{title}.html
"""

import os
import sys
import re
import json
import html
from pathlib import Path
from datetime import datetime


def parse_fill_order(output_dir: Path) -> list[str]:
    """从 fill-order.md 解析页面顺序，返回文件名列表"""
    fill_order = output_dir / "fill-order.md"
    pages = []

    if fill_order.exists():
        content = fill_order.read_text(encoding="utf-8")
        # 匹配类似: 1. reference/limits.md 或 - guides/model-create.md
        for m in re.finditer(r'(?:^|\n)\s*(?:\d+\.|-)\s+(?:\*\*)?([a-zA-Z0-9_/.-]+\.md)', content):
            pages.append(m.group(1))

    # 如果解析失败或为空，直接扫描 docs/ 目录
    if not pages:
        docs_dir = output_dir / "docs"
        if docs_dir.exists():
            # index.md first, then alphabetical
            all_md = sorted(docs_dir.rglob("*.md"), key=lambda p: (p.name != "index.md", str(p)))
            pages = [str(p.relative_to(docs_dir)) for p in all_md]

    return pages


def md_to_html_fragment(md_text: str) -> str:
    """简易 Markdown → HTML 转换（不依赖第三方库）"""
    lines = md_text.split('\n')
    html_lines = []
    in_table = False
    in_code = False
    in_list = False
    in_admonition = False
    admonition_type = ""
    admonition_title = ""
    admonition_lines = []

    def flush_admonition():
        nonlocal in_admonition, admonition_lines, admonition_type, admonition_title
        if not in_admonition:
            return
        # Map admonition types
        type_map = {
            "tip": ("tip", "💡"),
            "hint": ("tip", "💡"),
            "note": ("info", "ℹ️"),
            "info": ("info", "ℹ️"),
            "warning": ("warn", "⚠️"),
            "caution": ("warn", "⚠️"),
            "danger": ("danger", "🚨"),
            "error": ("danger", "🚨"),
        }
        css_class, icon = type_map.get(admonition_type.lower(), ("info", "ℹ️"))
        title = admonition_title or admonition_type.capitalize()
        body = "<br>".join(admonition_lines)
        html_lines.append(
            f'<div class="admonition {css_class}">'
            f'<div class="admonition-title">{icon} {html.escape(title)}</div>'
            f'<p>{body}</p></div>'
        )
        in_admonition = False
        admonition_lines = []

    def inline_format(text: str) -> str:
        """Handle inline formatting: bold, italic, code, links"""
        # Code (before other formatting to avoid conflicts)
        text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
        # Bold
        text = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', text)
        # Italic
        text = re.sub(r'\*(.+?)\*', r'<em>\1</em>', text)
        # Links
        text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', text)
        # Images (convert to placeholder if file ref, or inline if URL)
        text = re.sub(
            r'!\[([^\]]*)\]\(([^)]+)\)',
            r'<img src="\2" alt="\1" style="max-width:100%;border-radius:8px;margin:8px 0">',
            text
        )
        return text

    i = 0
    while i < len(lines):
        line = lines[i]

        # Code blocks
        if line.strip().startswith('```'):
            if in_code:
                html_lines.append('</code></pre>')
                in_code = False
            else:
                flush_admonition()
                if in_list:
                    html_lines.append('</ul>')
                    in_list = False
                lang = line.strip()[3:]
                html_lines.append(f'<pre><code class="lang-{html.escape(lang)}">')
                in_code = True
            i += 1
            continue

        if in_code:
            html_lines.append(html.escape(line))
            i += 1
            continue

        # Admonition (mkdocs syntax: !!! type "title" or !!! type)
        adm_match = re.match(r'^!!!\s+(\w+)\s*(?:"([^"]*)")?', line)
        if adm_match:
            flush_admonition()
            if in_list:
                html_lines.append('</ul>')
                in_list = False
            in_admonition = True
            admonition_type = adm_match.group(1)
            admonition_title = adm_match.group(2) or ""
            i += 1
            continue

        if in_admonition:
            if line.startswith('    ') or line.strip() == '':
                stripped = line.strip()
                if stripped:
                    admonition_lines.append(inline_format(html.escape(stripped)))
                i += 1
                continue
            else:
                flush_admonition()

        # HTML comment (screenshot placeholders)
        comment_match = re.match(r'^\s*<!--\s*TODO:\s*截图\s*[—-]\s*(.+?)\s*-->', line)
        if comment_match:
            flush_admonition()
            desc = comment_match.group(1)
            html_lines.append(
                f'<div class="img-placeholder">'
                f'<div class="icon">📸</div>{html.escape(desc)}</div>'
            )
            i += 1
            continue

        # Table
        if '|' in line and line.strip().startswith('|'):
            cells = [c.strip() for c in line.strip().strip('|').split('|')]
            if all(re.match(r'^[-:]+$', c) for c in cells):
                # Separator row, skip
                i += 1
                continue
            if not in_table:
                flush_admonition()
                if in_list:
                    html_lines.append('</ul>')
                    in_list = False
                html_lines.append('<table>')
                # Check if next line is separator -> this is header
                if i + 1 < len(lines):
                    next_cells = [c.strip() for c in lines[i + 1].strip().strip('|').split('|')]
                    if all(re.match(r'^[-:]+$', c) for c in next_cells):
                        html_lines.append('<tr>' + ''.join(f'<th>{inline_format(html.escape(c))}</th>' for c in cells) + '</tr>')
                        i += 2  # skip header + separator
                        in_table = True
                        continue
                in_table = True
            html_lines.append('<tr>' + ''.join(f'<td>{inline_format(html.escape(c))}</td>' for c in cells) + '</tr>')
            i += 1
            continue
        elif in_table:
            html_lines.append('</table>')
            in_table = False

        stripped = line.strip()

        # Empty line
        if not stripped:
            if in_list:
                html_lines.append('</ul>')
                in_list = False
            i += 1
            continue

        # Headers
        h_match = re.match(r'^(#{1,6})\s+(.+)', stripped)
        if h_match:
            flush_admonition()
            if in_list:
                html_lines.append('</ul>')
                in_list = False
            level = len(h_match.group(1))
            text = h_match.group(2)
            slug = re.sub(r'[^\w\u4e00-\u9fff-]', '', text.lower().replace(' ', '-'))
            html_lines.append(f'<h{level} id="{slug}">{inline_format(html.escape(text))}</h{level}>')
            i += 1
            continue

        # Unordered list
        if re.match(r'^[-*]\s+', stripped):
            if not in_list:
                html_lines.append('<ul>')
                in_list = True
            content = re.sub(r'^[-*]\s+', '', stripped)
            html_lines.append(f'<li>{inline_format(html.escape(content))}</li>')
            i += 1
            continue

        # Ordered list
        ol_match = re.match(r'^(\d+)\.\s+(.+)', stripped)
        if ol_match:
            if not in_list:
                html_lines.append('<ul>')  # Using ul for simplicity
                in_list = True
            html_lines.append(f'<li>{inline_format(html.escape(ol_match.group(2)))}</li>')
            i += 1
            continue

        # Horizontal rule
        if re.match(r'^[-*_]{3,}$', stripped):
            html_lines.append('<hr>')
            i += 1
            continue

        # Regular paragraph
        if in_list:
            html_lines.append('</ul>')
            in_list = False
        html_lines.append(f'<p>{inline_format(html.escape(stripped))}</p>')
        i += 1

    # Cleanup
    flush_admonition()
    if in_table:
        html_lines.append('</table>')
    if in_list:
        html_lines.append('</ul>')
    if in_code:
        html_lines.append('</code></pre>')

    return '\n'.join(html_lines)


def extract_nav_from_pages(pages_content: list[dict]) -> str:
    """从页面内容中提取导航HTML"""
    nav_html = []
    current_section = None

    for page in pages_content:
        # Determine section from path
        path = page["path"]
        if "/" in path:
            section = path.split("/")[0]
        elif path in ("index.md", "quickstart.md", "faq.md"):
            section = {"index.md": "概览", "quickstart.md": "概览", "faq.md": "帮助"}.get(path, "其他")
        else:
            section = "其他"

        section_labels = {
            "概览": "概览", "guides": "操作指南", "reference": "参考",
            "帮助": "帮助", "其他": "文档"
        }

        label = section_labels.get(section, section)
        if label != current_section:
            if current_section is not None:
                nav_html.append('</div>')  # close prev section
                nav_html.append('<div class="nav-divider"></div>')
            nav_html.append(f'<div class="nav-section">')
            nav_html.append(f'<div class="nav-section-title">{html.escape(label)}</div>')
            current_section = label

        # Extract first h1 or h2 as page title
        title = page.get("title", path)
        anchor = page["anchor"]

        # Determine if this is a sub-item
        is_sub = "/" in path and path.count("/") >= 1 and path not in ("index.md",)
        css_class = "nav-item l2" if False else "nav-item"  # Keep flat for now

        nav_html.append(f'<a class="{css_class}" href="#{anchor}">{html.escape(title)}</a>')

    if current_section is not None:
        nav_html.append('</div>')

    return '\n'.join(nav_html)


def extract_title_from_md(md_text: str) -> str:
    """Extract first heading from markdown"""
    for line in md_text.split('\n'):
        m = re.match(r'^#\s+(.+)', line.strip())
        if m:
            return m.group(1)
    return "Untitled"


def build_single_html(output_dir: str, title: str, template_path: str = None):
    output_dir = Path(output_dir)
    docs_dir = output_dir / "docs"

    if not docs_dir.exists():
        print(f"  ❌ docs 目录不存在: {docs_dir}")
        sys.exit(1)

    # 1. Get page order
    pages_order = parse_fill_order(output_dir)
    if not pages_order:
        print("  ❌ 无法确定页面顺序（fill-order.md 为空且 docs/ 下无 .md 文件）")
        sys.exit(1)

    # 2. Read and convert each page
    pages_content = []
    for page_path in pages_order:
        full_path = docs_dir / page_path
        if not full_path.exists():
            print(f"  ⚠️  跳过不存在的文件: {page_path}")
            continue

        md_text = full_path.read_text(encoding="utf-8")
        page_title = extract_title_from_md(md_text)
        anchor = re.sub(r'[^\w\u4e00-\u9fff-]', '', page_path.replace('/', '-').replace('.md', '').lower())
        html_fragment = md_to_html_fragment(md_text)

        pages_content.append({
            "path": page_path,
            "title": page_title,
            "anchor": anchor,
            "html": html_fragment,
        })

    print(f"  📄 合并 {len(pages_content)} 个页面...")

    # 3. Build navigation
    nav_html = extract_nav_from_pages(pages_content)

    # 4. Build content sections
    content_html = []
    for page in pages_content:
        content_html.append(f'<section class="section-page" id="{page["anchor"]}">')
        content_html.append(page["html"])
        content_html.append('</section>')

    # 5. Read template and inject
    if template_path and Path(template_path).exists():
        template = Path(template_path).read_text(encoding="utf-8")
    else:
        template = get_default_template()

    final_html = template.replace("{{TITLE}}", html.escape(title))
    final_html = final_html.replace("{{NAV}}", nav_html)
    final_html = final_html.replace("{{CONTENT}}", '\n'.join(content_html))
    final_html = final_html.replace("{{BUILD_TIME}}", datetime.now().strftime("%Y-%m-%d %H:%M"))

    # 6. Write output
    safe_name = re.sub(r'[^\w\u4e00-\u9fff-]', '-', title.lower()).strip('-')
    out_file = output_dir / f"{safe_name}.html"
    out_file.write_text(final_html, encoding="utf-8")
    print(f"  ✅ 输出: {out_file}")
    print(f"  📦 文件大小: {out_file.stat().st_size / 1024:.1f} KB")
    return str(out_file)


def get_default_template() -> str:
    """内置默认 HTML 模板"""
    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{{TITLE}}</title>
<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
:root {
  --sidebar-w:280px; --header-h:56px;
  --c-bg:#fafbfc; --c-sidebar:#fff; --c-border:#e8ecf0;
  --c-text:#2c3e50; --c-text-light:#6b7b8d; --c-text-muted:#9ba8b7;
  --c-primary:#3b82f6; --c-primary-soft:#eff6ff; --c-primary-dark:#2563eb;
  --c-accent:#10b981; --c-accent-soft:#ecfdf5;
  --c-warn:#f59e0b; --c-warn-soft:#fffbeb;
  --c-danger:#ef4444; --c-danger-soft:#fef2f2;
  --c-info:#6366f1; --c-info-soft:#eef2ff;
  --c-code-bg:#f4f6f8; --c-card:#fff;
  --radius:8px;
  --shadow-sm:0 1px 3px rgba(0,0,0,0.06);
  --shadow-md:0 4px 12px rgba(0,0,0,0.08);
  --font-body:'Noto Sans SC',-apple-system,BlinkMacSystemFont,sans-serif;
  --font-mono:'JetBrains Mono','SF Mono',monospace;
}
*{margin:0;padding:0;box-sizing:border-box}
html{scroll-behavior:smooth;scroll-padding-top:calc(var(--header-h)+20px)}
body{font-family:var(--font-body);font-size:15px;line-height:1.72;color:var(--c-text);background:var(--c-bg)}

.header{position:fixed;top:0;left:0;right:0;height:var(--header-h);background:#fff;border-bottom:1px solid var(--c-border);display:flex;align-items:center;padding:0 24px;z-index:100;box-shadow:var(--shadow-sm)}
.header-logo{display:flex;align-items:center;gap:10px;font-weight:700;font-size:16px;color:var(--c-text);text-decoration:none}
.header-logo .icon{width:32px;height:32px;border-radius:8px;background:linear-gradient(135deg,var(--c-primary),var(--c-info));display:flex;align-items:center;justify-content:center;color:#fff;font-size:16px}
.header-search{margin-left:auto;position:relative}
.header-search input{width:240px;padding:7px 12px 7px 34px;border:1px solid var(--c-border);border-radius:6px;font:13px var(--font-body);background:var(--c-bg);color:var(--c-text);transition:border-color .2s,box-shadow .2s}
.header-search input:focus{outline:none;border-color:var(--c-primary);box-shadow:0 0 0 3px rgba(59,130,246,0.1)}
.header-search::before{content:"🔍";position:absolute;left:10px;top:50%;transform:translateY(-50%);font-size:13px;pointer-events:none}
.header-meta{margin-left:16px;font-size:11px;color:var(--c-text-muted)}
.sidebar-toggle{display:none;background:none;border:none;font-size:22px;cursor:pointer;padding:4px 8px;margin-right:8px;color:var(--c-text-light)}

.sidebar{position:fixed;top:var(--header-h);left:0;bottom:0;width:var(--sidebar-w);background:var(--c-sidebar);border-right:1px solid var(--c-border);overflow-y:auto;padding:16px 0;z-index:90;transition:transform .3s}
.sidebar::-webkit-scrollbar{width:4px}
.sidebar::-webkit-scrollbar-thumb{background:#d1d5db;border-radius:4px}
.nav-section{padding:0 16px;margin-bottom:6px}
.nav-section-title{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.8px;color:var(--c-text-muted);padding:8px 8px 4px;user-select:none}
.nav-item{display:block;padding:7px 12px;font-size:13.5px;color:var(--c-text-light);text-decoration:none;border-radius:6px;transition:all .15s;cursor:pointer;margin:1px 0}
.nav-item:hover{background:var(--c-bg);color:var(--c-text)}
.nav-item.active{background:var(--c-primary-soft);color:var(--c-primary-dark);font-weight:500;position:relative}
.nav-item.active::before{content:"";position:absolute;left:0;top:4px;bottom:4px;width:3px;background:var(--c-primary);border-radius:2px}
.nav-item.l2{padding-left:28px;font-size:13px}
.nav-divider{height:1px;background:var(--c-border);margin:10px 16px}

.main{margin-left:var(--sidebar-w);padding:calc(var(--header-h)+32px) 48px 80px;max-width:860px}
.main h1{font-size:28px;font-weight:700;margin:0 0 8px;letter-spacing:-.3px}
.main h2{font-size:21px;font-weight:600;margin:48px 0 16px;padding-bottom:10px;border-bottom:2px solid var(--c-border)}
.main h3{font-size:17px;font-weight:600;margin:32px 0 12px}
.main p{margin-bottom:14px}

.admonition{border-radius:var(--radius);padding:14px 16px;margin:16px 0;border-left:4px solid}
.admonition-title{font-weight:600;font-size:13px;margin-bottom:4px;display:flex;align-items:center;gap:6px}
.admonition p{margin:0;font-size:14px}
.admonition.tip{background:var(--c-accent-soft);border-color:var(--c-accent)}
.admonition.tip .admonition-title{color:#059669}
.admonition.warn{background:var(--c-warn-soft);border-color:var(--c-warn)}
.admonition.warn .admonition-title{color:#b45309}
.admonition.info{background:var(--c-info-soft);border-color:var(--c-info)}
.admonition.info .admonition-title{color:#4f46e5}
.admonition.danger{background:var(--c-danger-soft);border-color:var(--c-danger)}
.admonition.danger .admonition-title{color:#dc2626}

table{width:100%;border-collapse:collapse;margin:16px 0;font-size:14px}
th{text-align:left;padding:10px 14px;background:var(--c-bg);font-weight:600;font-size:13px;border-bottom:2px solid var(--c-border)}
td{padding:10px 14px;border-bottom:1px solid var(--c-border);vertical-align:top}
tr:hover td{background:#fafbfd}

code{font-family:var(--font-mono);font-size:13px;background:var(--c-code-bg);padding:2px 6px;border-radius:4px}
pre{background:var(--c-code-bg);border-radius:var(--radius);padding:16px;margin:16px 0;overflow-x:auto}
pre code{background:none;padding:0;font-size:13px;line-height:1.6}

.img-placeholder{background:var(--c-bg);border:2px dashed var(--c-border);border-radius:var(--radius);padding:32px;text-align:center;color:var(--c-text-muted);font-size:13px;margin:16px 0}
.img-placeholder .icon{font-size:28px;margin-bottom:6px}

.section-page{padding-top:16px;margin-bottom:48px}

ul,ol{margin:8px 0 14px 24px}
li{margin-bottom:4px}

.back-to-top{position:fixed;bottom:28px;right:28px;width:40px;height:40px;border-radius:50%;background:var(--c-card);border:1px solid var(--c-border);box-shadow:var(--shadow-md);display:flex;align-items:center;justify-content:center;font-size:18px;cursor:pointer;color:var(--c-text-light);opacity:0;transition:opacity .3s;pointer-events:none;text-decoration:none}
.back-to-top.show{opacity:1;pointer-events:auto}

@media print{
  .header,.sidebar,.back-to-top,.header-search,.header-meta{display:none!important}
  .main{margin:0;padding:20px;max-width:100%}
  .section-page{page-break-before:always}
}
@media(max-width:900px){
  .sidebar{transform:translateX(-100%)}
  .sidebar.open{transform:translateX(0);box-shadow:var(--shadow-md)}
  .sidebar-toggle{display:block}
  .main{margin-left:0;padding:calc(var(--header-h)+24px) 20px 60px}
  .header-search input{width:160px}
  .header-meta{display:none}
}
</style>
</head>
<body>
<header class="header">
  <button class="sidebar-toggle" onclick="document.querySelector('.sidebar').classList.toggle('open')">☰</button>
  <a href="#top" class="header-logo"><span class="icon">📄</span>{{TITLE}}</a>
  <div class="header-search"><input type="text" placeholder="搜索文档..." id="search-input"></div>
  <div class="header-meta">构建于 {{BUILD_TIME}}</div>
</header>
<nav class="sidebar" id="sidebar">
{{NAV}}
</nav>
<main class="main" id="top">
{{CONTENT}}
</main>
<a href="#top" class="back-to-top" id="btt">↑</a>
<script>
const navItems=document.querySelectorAll('.nav-item[href^="#"]');
const sections=[];
navItems.forEach(item=>{const id=item.getAttribute('href').slice(1);const el=document.getElementById(id);if(el)sections.push({id,el,nav:item})});
function updateActive(){const y=window.scrollY+100;let cur=sections[0];for(const s of sections){if(s.el.offsetTop<=y)cur=s}navItems.forEach(n=>n.classList.remove('active'));if(cur)cur.nav.classList.add('active')}
window.addEventListener('scroll',updateActive);updateActive();
const btt=document.getElementById('btt');
window.addEventListener('scroll',()=>{btt.classList.toggle('show',window.scrollY>400)});
const si=document.getElementById('search-input');
si.addEventListener('input',function(){const q=this.value.toLowerCase().trim();document.querySelectorAll('.section-page').forEach(s=>{s.style.display=!q||s.textContent.toLowerCase().includes(q)?'':'none'})});
navItems.forEach(item=>{item.addEventListener('click',()=>{document.querySelector('.sidebar').classList.remove('open')})});
</script>
</body>
</html>'''


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("用法: python3 single-html-build.py <output_dir> <title> [--template <path>]")
        sys.exit(1)

    output_dir = sys.argv[1]
    title = sys.argv[2]
    template = None

    if "--template" in sys.argv:
        idx = sys.argv.index("--template")
        if idx + 1 < len(sys.argv):
            template = sys.argv[idx + 1]

    build_single_html(output_dir, title, template)
