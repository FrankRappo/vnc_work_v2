#!/usr/bin/env python3
"""
fetch_email_code.py — достать одноразовый код подтверждения из почты по IMAP.
Незаменим при OAuth/passwordless-входах, где код приходит на email.

Использование:
  python3 fetch_email_code.py --host imap.example.com --user user@example.com --pass 'PW' \
      [--from example] [--digits 6] [--newest 1] [--subject 'confirm']

  --from     подстрока в поле From (фильтр отправителя), напр. example / auth
  --subject  подстрока в Subject (доп. фильтр)
  --digits   длина кода (по умолчанию 6)
  --newest   из скольких последних писем искать (по умолчанию 5)

Печатает найденный код (или список кандидатов). Хитрость: игнорирует '000000' и
hex-цвета (#RRGGBB) из HTML-вёрстки писем — берёт код из текста, а не из CSS.
"""
import argparse, imaplib, email, re, sys, html as _html
from email.header import decode_header, make_header

def body_text(msg):
    out = ""
    if msg.is_multipart():
        for p in msg.walk():
            if p.get_content_type() in ("text/plain", "text/html"):
                try: out += p.get_payload(decode=True).decode(p.get_content_charset() or "utf-8", "ignore")
                except Exception: pass
    else:
        try: out = msg.get_payload(decode=True).decode(msg.get_content_charset() or "utf-8", "ignore")
        except Exception: out = ""
    return out

def codes(text, n):
    stripped = _html.unescape(re.sub(r"<[^>]+>", " ", text))
    pat = re.compile(r"(?<![\w#])(\d{%d})(?![\w])" % n)
    found = [c for c in pat.findall(stripped) if c != "0" * n]
    # dedup, keep order
    seen, res = set(), []
    for c in found:
        if c not in seen: seen.add(c); res.append(c)
    return res

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True); ap.add_argument("--user", required=True)
    ap.add_argument("--pass", dest="pw", required=True); ap.add_argument("--port", type=int, default=993)
    ap.add_argument("--from", dest="frm", default=""); ap.add_argument("--subject", default="")
    ap.add_argument("--digits", type=int, default=6); ap.add_argument("--newest", type=int, default=5)
    a = ap.parse_args()
    M = imaplib.IMAP4_SSL(a.host, a.port, timeout=30); M.login(a.user, a.pw); M.select("INBOX")
    typ, data = M.search(None, "ALL"); ids = data[0].split()
    if not ids: print("inbox пуст"); return
    for i in reversed(ids[-a.newest:]):
        typ, md = M.fetch(i, "(RFC822)")
        msg = email.message_from_bytes(md[0][1])
        frm = str(make_header(decode_header(msg.get("From", ""))))
        subj = str(make_header(decode_header(msg.get("Subject", ""))))
        date = msg.get("Date", "")
        if a.frm and a.frm.lower() not in frm.lower(): continue
        if a.subject and a.subject.lower() not in subj.lower(): continue
        c = codes(body_text(msg), a.digits)
        print(f"FROM: {frm[:50]} | {date[:31]}")
        print(f"SUBJ: {subj[:70]}")
        if c:
            print("CODE:", c[0], ("(others: " + ",".join(c[1:4]) + ")") if len(c) > 1 else "")
            M.logout(); return
        print("(кода не найдено в этом письме)")
    M.logout()

if __name__ == "__main__":
    main()
