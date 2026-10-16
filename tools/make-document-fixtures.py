"""Generate public, deterministic documents for native picker acceptance.

Usage: python tools/make-document-fixtures.py local-reports/document-fixtures
No application data, reference source or copyrighted book text is included.
"""

import hashlib
import io
import json
from pathlib import Path
import sys
import zipfile


def main():
    root = Path(sys.argv[1]).resolve()
    root.mkdir(parents=True, exist_ok=True)
    entries = {
        "mimetype": "application/epub+zip",
        "META-INF/container.xml": '''<?xml version="1.0" encoding="UTF-8"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
        "OEBPS/content.opf": '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">fqapp-public-acceptance</dc:identifier>
<dc:title>鸿蒙 EPUB 公开验证</dc:title><dc:creator>公开测试</dc:creator><dc:language>zh-CN</dc:language>
<meta property="dcterms:modified">2026-10-17T00:00:00Z</meta></metadata>
<manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>
<item id="two" href="two.xhtml" media-type="application/xhtml+xml"/>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest>
<spine><itemref idref="two"/><itemref idref="one"/></spine></package>''',
        "OEBPS/one.xhtml": '''<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head>
<body><h1>第一章 文件顺序</h1><p>这是第二个阅读章节。目录应遵循 spine 顺序，而不是 ZIP 文件顺序。</p></body></html>''',
        "OEBPS/two.xhtml": '''<html xmlns="http://www.w3.org/1999/xhtml"><head><title>序章</title></head>
<body><h1>序章 原版阅读器</h1><p>这是第一个阅读章节。公开文本用于验证鸿蒙系统选择、EPUB 解包和重启续读。</p></body></html>''',
        "OEBPS/nav.xhtml": '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目录</title></head><body><nav epub:type="toc"><ol>
<li><a href="two.xhtml">序章</a></li><li><a href="one.xhtml">第一章</a></li></ol></nav></body></html>''',
    }
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as archive:
        for name, text in entries.items():
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 17, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED if name == "mimetype" else zipfile.ZIP_DEFLATED
            archive.writestr(info, text.encode("utf-8"))
    text = "第一章 编码验证\n公开测试文本：中文、标点与文件编码。\n\n第二章 重启续读\n章节和正文应保持可读。\n"
    files = {
        "fq-public.epub": stream.getvalue(),
        "fq-utf16.txt": b"\xff\xfe" + text.encode("utf-16le"),
        "fq-gb18030.txt": text.encode("gb18030"),
        "fq-invalid.epub": b"This is not a ZIP or EPUB archive.\n",
        "fq-invalid.json": b'{"format":"not-a-fqapp-backup","version":1}',
    }
    manifest = {}
    for name, data in files.items():
        (root / name).write_bytes(data)
        manifest[name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    (root / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
