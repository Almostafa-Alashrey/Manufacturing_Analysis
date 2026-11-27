"""Build docs/PROJECT_DOCUMENTATION.pdf from docs/PROJECT_DOCUMENTATION.md
Usage:  python docs/build_pdf.py        (needs: pip install reportlab)
Minimal black and white style, like the DEPI documentation guidelines.
"""
import datetime
import os
import re

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.platypus import (BaseDocTemplate, CondPageBreak, Frame, HRFlowable, Image, KeepTogether, PageTemplate,
                                Paragraph, Preformatted, Spacer, Table, TableStyle)

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, 'PROJECT_DOCUMENTATION.md')
OUTPUT = os.path.join(HERE, 'PROJECT_DOCUMENTATION.pdf')
LOGOS = [os.path.join(HERE, 'images', 'logo_depi.png'), os.path.join(HERE, 'images', 'logo_mcit.png')]

PAGE_W, PAGE_H = A4
MARGIN_X = 2.3 * cm
CONTENT_W = PAGE_W - 2 * MARGIN_X
GREY = colors.HexColor('#555555')

# ------------------------------------------------------------------ styles
body = ParagraphStyle('body', fontName='Times-Roman', fontSize=10.5, leading=14.5, spaceAfter=6)
title = ParagraphStyle('title', fontName='Times-Bold', fontSize=30, leading=36, alignment=TA_CENTER, spaceAfter=14)
subtitle = ParagraphStyle('subtitle', parent=body, alignment=TA_CENTER, fontSize=11.5, leading=17)
h2 = ParagraphStyle('h2', fontName='Times-Bold', fontSize=17, leading=21, spaceBefore=16, spaceAfter=4, keepWithNext=1)
h3 = ParagraphStyle('h3', fontName='Times-Bold', fontSize=11.5, leading=15, spaceBefore=10, spaceAfter=3, keepWithNext=1)
item = ParagraphStyle('item', parent=body, leftIndent=16, bulletIndent=4, spaceAfter=3)
cell = ParagraphStyle('cell', parent=body, fontSize=9.5, leading=12.5, spaceAfter=0)
cell_head = ParagraphStyle('cell_head', parent=cell, fontName='Times-Bold')
caption = ParagraphStyle('caption', parent=body, fontName='Times-Italic', fontSize=9, alignment=TA_CENTER, textColor=GREY)
quote = ParagraphStyle('quote', parent=body, fontName='Times-Italic', spaceAfter=0)


# ------------------------------------------------------------------ text helpers
def clean(text):
    """Replace symbols that the PDF fonts cannot draw."""
    for a, b in {'⬜': '[ ]', '🟨': '[~]', '✅': '[x]', '✍️': '', '≈': '~', '≥': '>=', '≤': '<=',
                 '→': '->', '✓': 'v', '×': 'x'}.items():
        text = text.replace(a, b)
    return text.encode('cp1252', errors='ignore').decode('cp1252')


def inline(text):
    """Markdown inline formatting -> reportlab XML."""
    text = clean(text)
    text = text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    text = re.sub(r'`([^`]+)`', r'<font face="Courier" size="9">\1</font>', text)
    text = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', text)
    text = re.sub(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])', r'<i>\1</i>', text)
    text = re.sub(r'(?<![\w])_(?!\s)(.+?)(?<!\s)_(?![\w])', r'<i>\1</i>', text)
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2" color="black"><u>\1</u></a>', text)
    return text.replace('  \n', '<br/>')


def write_box():
    """Empty box that shows where a team member has to write."""
    box = Table([[Paragraph('<i>Write here</i>', ParagraphStyle('w', parent=body, fontSize=8, textColor=colors.HexColor('#999999')))]],
                colWidths=[CONTENT_W], rowHeights=[2.4 * cm])
    box.setStyle(TableStyle([('BOX', (0, 0), (-1, -1), 0.5, colors.black), ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                             ('LEFTPADDING', (0, 0), (-1, -1), 6), ('TOPPADDING', (0, 0), (-1, -1), 4)]))
    return [box, Spacer(1, 6)]


def make_table(rows):
    """rows: list of lists of strings (first row is the header)."""
    data = [[Paragraph(inline(c), cell_head if r == 0 else cell) for c in row] for r, row in enumerate(rows)]
    weights = [max(len(clean(row[i])) if i < len(row) else 0 for row in rows) ** 0.6 + 4 for i in range(len(rows[0]))]
    widths = [CONTENT_W * w / sum(weights) for w in weights]
    table = Table(data, colWidths=widths, repeatRows=1)
    table.setStyle(TableStyle([('GRID', (0, 0), (-1, -1), 0.5, colors.black),
                               ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#EFEFEF')),
                               ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                               ('TOPPADDING', (0, 0), (-1, -1), 4), ('BOTTOMPADDING', (0, 0), (-1, -1), 4)]))
    return [table, Spacer(1, 8)]


def make_image(alt, path):
    full = os.path.join(HERE, path)
    if not os.path.exists(full):
        return [Paragraph('[image not found: ' + clean(path) + ']', caption)]
    img = Image(full)
    scale = min(1.0, CONTENT_W / img.imageWidth, 12 * cm / img.imageHeight)
    img.drawWidth, img.drawHeight = img.imageWidth * scale, img.imageHeight * scale
    return [KeepTogether([img, Spacer(1, 3), Paragraph(inline(alt), caption)]), Spacer(1, 6)]


# ------------------------------------------------------------------ markdown -> flowables
def parse(lines):
    story, i, after_title = [], 0, False
    while i < len(lines):
        line = lines[i].rstrip('\n')
        stripped = line.strip()

        if not stripped:
            i += 1
        elif stripped.startswith('<!--'):                      # comments: only the write marker is shown
            if 'WRITE HERE' in stripped:
                story += write_box()
            i += 1
        elif stripped.startswith('```'):                       # code block
            code, i = [], i + 1
            while i < len(lines) and not lines[i].strip().startswith('```'):
                code.append(clean(lines[i].rstrip('\n'))); i += 1
            i += 1
            pre = Preformatted('\n'.join(code), ParagraphStyle('code', fontName='Courier', fontSize=8.5, leading=11))
            box = Table([[pre]], colWidths=[CONTENT_W])
            box.setStyle(TableStyle([('BACKGROUND', (0, 0), (-1, -1), colors.HexColor('#F4F4F4')),
                                     ('BOX', (0, 0), (-1, -1), 0.5, colors.HexColor('#999999')),
                                     ('LEFTPADDING', (0, 0), (-1, -1), 8), ('TOPPADDING', (0, 0), (-1, -1), 6)]))
            story += [box, Spacer(1, 8)]
        elif stripped.startswith('# '):
            story += [Spacer(1, 2.2 * cm), Paragraph(inline(stripped[2:]), title)]
            after_title = True; i += 1
        elif stripped.startswith('## '):
            story.append(CondPageBreak(8 * cm if stripped.startswith('## Appendix') else 5 * cm))
            story.append(Paragraph(inline(stripped[3:]), h2))
            story.append(HRFlowable(width='100%', thickness=0.8, color=colors.black, spaceAfter=6))
            i += 1
        elif stripped.startswith('### '):
            story.append(CondPageBreak(5.5 * cm))
            story.append(Paragraph(inline(stripped[4:]), h3)); i += 1
        elif re.fullmatch(r'-{3,}', stripped):
            story.append(HRFlowable(width='100%', thickness=0.5, color=colors.HexColor('#999999'), spaceBefore=6, spaceAfter=6)); i += 1
        elif stripped.startswith('|'):                         # table
            rows = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                row = [c.strip() for c in lines[i].strip().strip('|').split('|')]
                if not all(re.fullmatch(r':?-{3,}:?', c) for c in row):
                    rows.append(row)
                i += 1
            story += make_table(rows)
        elif stripped.startswith('>'):                         # quote
            text = []
            while i < len(lines) and lines[i].strip().startswith('>'):
                text.append(lines[i].strip().lstrip('>').strip()); i += 1
            box = Table([[Paragraph(inline(' '.join(text)), quote)]], colWidths=[CONTENT_W])
            box.setStyle(TableStyle([('LINEBEFORE', (0, 0), (0, -1), 2.5, colors.black), ('LEFTPADDING', (0, 0), (-1, -1), 10),
                                     ('TOPPADDING', (0, 0), (-1, -1), 2), ('BOTTOMPADDING', (0, 0), (-1, -1), 2)]))
            story += [box, Spacer(1, 8)]
        elif re.match(r'^(\d+)\.\s', stripped) or re.match(r'^[-*]\s', stripped):   # lists
            m = re.match(r'^(\d+)\.\s+(.*)', stripped)
            bullet, text = (m.group(1) + '.', m.group(2)) if m else ('•', stripped[2:])
            story.append(Paragraph(inline(text), item, bulletText=bullet)); i += 1
        elif re.match(r'^!\[(.*?)\]\((.*?)\)$', stripped):     # image
            m = re.match(r'^!\[(.*?)\]\((.*?)\)$', stripped)
            story += make_image(m.group(1), m.group(2)); i += 1
        else:                                                  # paragraph (joins following lines)
            text = [line]
            i += 1
            while i < len(lines) and lines[i].strip() and not re.match(r'^(#|>|\||```|<!--|-{3,}|\d+\.\s|[-*]\s|!\[)', lines[i].strip()):
                text.append(lines[i].rstrip('\n')); i += 1
            style = subtitle if after_title else body
            story.append(Paragraph(inline('\n'.join(text)), style))
            if after_title:
                story.append(Paragraph(clean(f'Generated on {datetime.date.today():%d %B %Y}'), caption))
                story.append(Spacer(1, 1.2 * cm))
            after_title = False
    return story


# ------------------------------------------------------------------ page decoration
def decorate(canvas, doc):
    canvas.saveState()
    top = PAGE_H - 1.1 * cm
    for n, path in enumerate(LOGOS):
        if os.path.exists(path):
            img_h = 1.5 * cm
            img_w = img_h * 193 / 100 if n == 0 else img_h * 197 / 94
            x = MARGIN_X if n == 0 else PAGE_W - MARGIN_X - img_w
            canvas.drawImage(path, x, top - img_h, width=img_w, height=img_h, mask='auto')
    canvas.setFont('Times-Roman', 9)
    canvas.setFillColor(GREY)
    canvas.drawCentredString(PAGE_W / 2, 1.2 * cm, f'Page {doc.page}')
    canvas.restoreState()


def build():
    with open(SOURCE, encoding='utf-8') as f:
        lines = f.readlines()
    doc = BaseDocTemplate(OUTPUT, pagesize=A4, leftMargin=MARGIN_X, rightMargin=MARGIN_X, topMargin=3.4 * cm,
                          bottomMargin=2.2 * cm, title='Project Documentation', author='DEPI Project Team')
    frame = Frame(MARGIN_X, 2.2 * cm, CONTENT_W, PAGE_H - 3.4 * cm - 2.2 * cm, id='main', leftPadding=0, rightPadding=0,
                  topPadding=0, bottomPadding=0)
    doc.addPageTemplates([PageTemplate(id='page', frames=[frame], onPage=decorate)])
    doc.build(parse(lines))
    print('Created', OUTPUT)


if __name__ == '__main__':
    build()
