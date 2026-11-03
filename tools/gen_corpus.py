#!/usr/bin/env python3
"""Generate the differential-corpus for spec-vs-asm checking (M6).

Line formats (hex = lowercase hex bytes):
  J <hex>            JSON document -> validity (ok/bad)
  U <hex>            JSON string span (between quotes) -> unescaped bytes hex / ERR
  B <hex>            bytes -> b64url-encode then decode -> "b64 hex"
  S <hex>            bytes -> sha256 hex
  H <keyhex> <msghex> -> hmac-sha256 hex
  I <text>           :id -> none / value
  E <text>           exp  -> bad / value
"""
import random, sys

random.seed(20261103)

def h(b): return b.hex().encode() if isinstance(b, (bytes, bytearray)) else b.encode()

lines = []

# --- JSON validity corpus ---
valid_docs = [
    b'{}', b'[]', b'null', b'true', b'false', b'0', b'-1', b'1.5', b'1e10', b'1E-3',
    b'-0.25e+7', b'""', b'"a"', b'"\\u0041"', b'"\\ud83d\\ude00"', b'"cafe \\u2713"',
    b'{"body":"x"}', b'{ "body" : "x" }', b'{"a":{},"b":[]}', b'[[1,[2,[3]]]]',
    b'{"n":null,"t":true,"f":false,"i":42,"s":"hi","a":[1,2,3],"o":{"k":"v"}}',
    b'{"esc":"\\"\\\\\\/\\b\\f\\n\\r\\t"}', b'[1,2,3,4,5]', b'  [1, 2]  ', b'\t{"a":1}\n',
    b'{"nested":{"deep":{"deeper":[[[1]]]}}}', b'"\\u00e9"', b'"\\uD800\\uDC00"',
    b'["zero",0]', b'[0.0]', b'[-0]', b'123456789012345678901234567890',
    b'{"id":1,"body":"b","created_at":"2025-01-01T00:00:00.000Z","author":"a","like_count":0}',
]
invalid_docs = [
    b'', b'{', b'}', b'[', b']', b'{,}', b'[1,]', b'[,1]', b'{"a"}', b'{"a":}',
    b'{"a":1,}', b'{a:1}', b"'x'", b'01', b'1.', b'.1', b'1e', b'1e+', b'+1', b'--1',
    b'"unterminated', b'"bad\\escape"', b'"\\u12"', b'"\\uZZZZ"', b'"\\ud800"', b'"\\udc00"',
    b'"\\ud800\\ud800"', b'nul', b'True', b'FALSE', b'{"a":1}{"b":2}', b'[1][2]', b'1 2',
    b'{"a":1 "b":2}', b'[1 2]', b'"\x01"', b'"\x1f"', b'{"a":tru}', b'[undefined]', b'NaN',
    b'{"a":01}', b'{"a":1.}', b'{"a":.5}', b'{"a":1e}', b'[1,,2]', b'{,}', b'}{',
]
for i, d in enumerate(valid_docs): lines.append(b'J ' + d.hex().encode())
for i, d in enumerate(invalid_docs): lines.append(b'J ' + d.hex().encode())
# random mutations of a valid doc (flip/insert/delete a byte)
base = b'{"body":"hello world","n":123,"arr":[1,2,3],"o":{"x":true}}'
rng = random.Random(7)
for i in range(300):
    b = bytearray(base)
    for _ in range(rng.randint(1, 2)):
        op = rng.randint(0, 2)
        p = rng.randrange(len(b))
        if op == 0: b[p] = rng.randrange(256)
        elif op == 1: b.insert(p, rng.randrange(256))
        else: del b[p]
        if not b: break
    lines.append(b'J ' + h(bytes(b)))

# --- unescape corpus ---
spans = [
    b'', b'plain', b'a\\"b', b'a\\\\b', b'a\\/b', b'\\b\\f\\n\\r\\t',
    b'\\u0041', b'\\u00e9', b'\\u2713', b'\\ud83d\\ude00', b'\\uD83D\\uDE00',
    b'caf\\u00e9 \\u2713', b'mix \\" \\\\ \\n end', b'<b>&amp;</b> \\"quoted\\" / caf\\u00e9 \\u2713',
    b'\\u0000', b'\\u001f', b'\\u007f', b'\\u0080', b'\\u07ff', b'\\u0800', b'\\uffff',
    b'\\udbff\\udfff', b'\\ud800\\udc00 \\ud83d\\ude00', b'raw bytes: caf\xc3\xa9 \xe2\x9c\x93',
]
for s in spans: lines.append(b'U ' + s.hex().encode())

# --- base64 / sha / hmac corpus ---
for i in range(200):
    n = rng.randrange(0, 64)
    b = bytes(rng.randrange(256) for _ in range(n))
    lines.append(b'B ' + b.hex().encode())
    lines.append(b'S ' + b.hex().encode())
    k = bytes(rng.randrange(256) for _ in range(rng.choice([0, 1, 22, 63, 64, 65, 131])))
    m = bytes(rng.randrange(256) for _ in range(rng.randrange(0, 200)))
    lines.append(b'H ' + k.hex().encode() + b' ' + m.hex().encode())

# --- id / exp corpus ---
ids = ['', '0', '1', '42', '007', '9' * 18, '9' * 19, '9' * 30, '-1', '1.5', 'abc',
       '1a', 'a1', ' 1', '1 ', '+1', '0x10', '1e3', '999999999', '2147483647',
       '2147483648', '9223372036854775807', '9223372036854775808']
for i in ids: lines.append(b'I ' + i.encode())
exps = ['0', '1', '-1', '-0', '1767225600', '-1767225600', '9' * 25, '1a', 'a', '',
        '+5', '5+', '--5', '9223372036854775807', '99999999999999999999']
for e in exps: lines.append(b'E ' + e.encode())

out = '\n'.join(l.decode() for l in lines) + '\n'
path = sys.argv[1] if len(sys.argv) > 1 else '/dev/stdout'
with open(path, 'w') as f:
    f.write(out)
print(f"corpus: {len(lines)} cases -> {path}", file=sys.stderr)
