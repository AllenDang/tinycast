import hashlib
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PROGRESS = ROOT / "docs/refactor/progress"
MANIFEST = PROGRESS / "34-prepass-full-line-comment-stripped.sha256"
INLINE = PROGRESS / "34-inline-prefixes-before.json"
EXPECTED_MANIFEST_ARTIFACT = "cd3475ad13e63f26c57225026906c32da85ddd7f10915533b8ad0e05f03235ce"
EXPECTED_INLINE_ARTIFACT = "824c9dcb839e0b04f210099fb7bc1fba977f5e02ccbcc0e4d64ac2a1410ffde4"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def stripped_digest(lines: list[str]) -> str:
    kept = (line for line in lines if not line.lstrip().startswith("//"))
    return sha256("".join(kept).encode())


manifest_bytes = MANIFEST.read_bytes()
inline_bytes = INLINE.read_bytes()
assert sha256(manifest_bytes) == EXPECTED_MANIFEST_ARTIFACT
assert sha256(inline_bytes) == EXPECTED_INLINE_ARTIFACT

expected: dict[str, str] = {}
for record in manifest_bytes.decode().splitlines():
    digest, path = record.split("  ", 1)
    expected[path] = digest
assert len(expected) == 194

inline = json.loads(inline_bytes)
reconstructed: dict[str, list[str]] = {}
prefix_count = 0
for path, entries in inline.items():
    lines = (ROOT / path).read_text().splitlines(keepends=True)
    positions: list[int] = []
    for _, item in sorted(entries.items(), key=lambda pair: int(pair[0])):
        prefix = item["prefix"]
        assert sha256(prefix.encode()) == item["prefix_sha256"]
        text = "".join(lines)
        assert text.count(prefix) == 1, (path, prefix, text.count(prefix))
        statement = prefix.splitlines()[-1]
        offset = text.index(prefix) + len(prefix) - len(statement)
        position = text[:offset].count("\n")
        assert lines[position].rstrip() == item["statement_prefix"].rstrip()
        positions.append(position)
        newline = "\n" if lines[position].endswith("\n") else ""
        lines[position] = item["line"] + newline
        prefix_count += 1
    assert positions == sorted(positions), (path, positions)
    reconstructed[path] = lines

records: list[str] = []
for path in sorted(expected):
    lines = reconstructed.get(path)
    if lines is None:
        lines = (ROOT / path).read_text().splitlines(keepends=True)
    digest = stripped_digest(lines)
    assert digest == expected[path], (path, digest, expected[path])
    records.append(f"{digest}  {path}\n")
regenerated = "".join(records).encode()
assert regenerated == manifest_bytes

if len(sys.argv) == 2:
    Path(sys.argv[1]).write_bytes(regenerated)

with tempfile.NamedTemporaryFile() as output:
    output.write(regenerated)
    output.flush()
    assert Path(output.name).read_bytes() == manifest_bytes

print(f"manifest_artifact_sha256={sha256(manifest_bytes)}")
print(f"inline_artifact_sha256={sha256(inline_bytes)}")
print(f"manifest_entries={len(expected)}")
print(f"inline_prefixes={prefix_count}")
print("unique_prefixes=PASS")
print("prefix_order=PASS")
print("reconstructed_file_digests=PASS")
print("byte_for_byte_manifest_regeneration=PASS")
