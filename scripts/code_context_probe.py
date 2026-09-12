#!/usr/bin/env python3
"""Offline Graphify/Tree-sitter experiment for source-aware dictation.

Run with a Python environment containing graphifyy 0.9.32. No model calls,
downloads, app integration, or changes to the indexed repository. Output is
retrieval evidence, not a corrected transcript or a semantic correctness claim.
"""

import argparse
import hashlib
import importlib
import importlib.metadata
import json
import re
import subprocess
import time
from pathlib import Path


EXTRACTORS = {
    ".swift": "extract_swift", ".py": "extract_python",
    ".js": "extract_js", ".jsx": "extract_js", ".ts": "extract_js",
    ".tsx": "extract_js", ".mts": "extract_js", ".cts": "extract_js",
    ".java": "extract_java", ".c": "extract_c", ".cpp": "extract_cpp",
    ".cs": "extract_csharp", ".rb": "extract_ruby", ".php": "extract_php",
    ".kt": "extract_kotlin", ".lua": "extract_lua",
}
IGNORED = {"node_modules", "vendor", "dist", "build", "target", "Pods"}
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*")
STOP = {"a", "an", "and", "as", "at", "by", "for", "from", "in", "is", "it",
        "of", "on", "or", "the", "to", "with"}


def syntax_identifiers(path):
    """Supplement graph entities with local names and argument labels.

    Graphify deliberately does not model every variable as a graph node.
    These identifiers carry source locations but no inferred relationships.
    """
    from tree_sitter import Language, Parser

    grammars = {
        ".swift": ("tree_sitter_swift", "language"),
        ".py": ("tree_sitter_python", "language"),
        ".js": ("tree_sitter_javascript", "language"),
        ".jsx": ("tree_sitter_javascript", "language"),
        ".ts": ("tree_sitter_typescript", "language_typescript"),
        ".mts": ("tree_sitter_typescript", "language_typescript"),
        ".cts": ("tree_sitter_typescript", "language_typescript"),
        ".tsx": ("tree_sitter_typescript", "language_tsx"),
    }
    if path.suffix not in grammars:
        return []
    module, function = grammars[path.suffix]
    parser = Parser(Language(getattr(importlib.import_module(module), function)()))
    stack = [parser.parse(path.read_bytes()).root_node]
    result, seen = [], set()
    while stack:
        node = stack.pop()
        if node.type in {"identifier", "simple_identifier", "type_identifier", "property_identifier"}:
            name = node.text.decode("utf-8")
            if IDENTIFIER.fullmatch(name) and len(name) <= 120 and name not in seen:
                seen.add(name)
                result.append((name, "L" + str(node.start_point.row + 1)))
        stack.extend(reversed(node.children))
    return result


def words(value):
    value = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1 \2", value)
    value = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", value)
    return [w for w in re.findall(r"[a-z0-9]+", value.lower()) if w not in STOP]


def source_files(root, max_files=500, max_bytes=256_000):
    """Git ignore rules, source allowlist, no hidden paths or symlinks."""
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others",
         "--exclude-standard"], check=True, capture_output=True, timeout=10)
    names = sorted(set(result.stdout.decode("utf-8").split("\0")))
    selected, rejected = [], 0
    for name in names:
        relative = Path(name)
        if not name or relative.is_absolute() or ".." in relative.parts:
            continue
        if relative.suffix not in EXTRACTORS:
            continue
        if any(part.startswith(".") or part in IGNORED for part in relative.parts):
            continue
        path = root / relative
        if any(parent.is_symlink() for parent in [path, *path.parents] if parent != root):
            rejected += 1
            continue
        if not path.is_file() or not path.resolve().is_relative_to(root):
            rejected += 1
            continue
        if path.stat().st_size > max_bytes:
            rejected += 1
            continue
        selected.append(path)
    return selected[:max_files], {
        "files_available": len(selected), "files_selected": min(len(selected), max_files),
        "file_limit_reached": len(selected) > max_files, "files_rejected": rejected,
    }


def build(root, max_files=500):
    from graphify import extract as graph_extract

    started = time.perf_counter()
    files, limits = source_files(root, max_files)
    nodes, edges, errors, digests = [], [], [], {}
    for path in files:
        relative = path.relative_to(root).as_posix()
        before = hashlib.sha256(path.read_bytes()).hexdigest()
        try:
            extracted = getattr(graph_extract, EXTRACTORS[path.suffix])(path)
            identifiers = syntax_identifiers(path)
        except Exception as error:
            errors.append({"file": relative, "error_type": type(error).__name__})
            continue
        if extracted.get("error"):
            errors.append({"file": relative, "error_type": "extractor_error"})
            continue
        if hashlib.sha256(path.read_bytes()).hexdigest() != before:
            errors.append({"file": relative, "error_type": "source_changed"})
            continue
        digests[relative] = before
        # Structured identifiers only. No comments, string literals, or arbitrary
        # graph rationale become model instructions in this experiment.
        for node in extracted.get("nodes", []):
            label = node.get("label", "")
            if not isinstance(label, str) or not IDENTIFIER.fullmatch(label) or len(label) > 120:
                continue
            if label == path.name:
                continue
            nodes.append({"id": relative + "::" + node["id"], "name": label, "file": relative,
                          "location": node.get("source_location"),
                          "kind": node.get("type", "symbol") if node.get("source_file") else "reference"})
        graph_names = {node["name"] for node in nodes
                       if node["file"] == relative and node["kind"] != "reference"}
        for name, location in identifiers:
            if name not in graph_names:
                nodes.append({"id": relative + "::syntax::" + name, "name": name,
                              "file": relative, "location": location, "kind": "identifier"})
        for edge in extracted.get("edges", []):
            if edge.get("confidence") != "EXTRACTED":
                continue
            edges.append({"source": relative + "::" + edge["source"],
                          "target": relative + "::" + edge["target"],
                          "relation": edge.get("relation"), "context": edge.get("context")})
    return {"schema": "plynn-code-context-probe/v1", "root": str(root),
            "extractor": {"name": "graphifyy", "version": importlib.metadata.version("graphifyy")},
            "elapsed_ms": round((time.perf_counter() - started) * 1000, 1),
            "limits": limits, "errors": errors, "source_sha256": digests,
            "nodes": nodes, "edges": edges}


def retrieve(index, query, active_file=None, limit=12):
    """Rank spelling hints. Never replace ambiguous or approximate speech."""
    query_words = set(words(query))
    ranked = []
    names_by_id = {node["id"]: node["name"] for node in index["nodes"]}
    for node in index["nodes"]:
        if node.get("kind") == "reference":
            continue
        tokens = set(words(node["name"]))
        overlap = tokens & query_words
        if not overlap:
            continue
        coverage = len(overlap) / max(1, len(tokens))
        score = coverage * 4 + min(len(overlap), 3)
        if active_file and node["file"] == active_file:
            score += 2
        ranked.append((score, node))
    ranked.sort(key=lambda row: (-row[0], row[1]["name"], row[1]["file"]))
    candidates, seen = [], set()
    for score, node in ranked:
        key = (node["name"], node["file"], node["location"])
        if key in seen:
            continue
        seen.add(key)
        related = set()
        for edge in index["edges"]:
            other = edge["target"] if edge["source"] == node["id"] else (
                edge["source"] if edge["target"] == node["id"] else None)
            if other in names_by_id:
                related.add((edge["relation"], names_by_id[other]))
        candidates.append({"name": node["name"], "file": node["file"],
                           "location": node["location"], "score": round(score, 2),
                           "related": sorted(related)[:8]})
        if len(candidates) == limit:
            break
    return candidates


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--query", required=True)
    parser.add_argument("--active-file", help="Explicit repository-relative path; never inferred")
    parser.add_argument("--max-files", type=int, default=500)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not 1 <= args.max_files <= 500:
        parser.error("--max-files must be between 1 and 500")
    index = build(args.root.resolve(strict=True), args.max_files)
    index["query"] = args.query
    index["candidates"] = retrieve(index, args.query, args.active_file)
    encoded = json.dumps(index, indent=2) + "\n"
    if args.output:
        args.output.write_text(encoded)
    print(json.dumps({key: index[key] for key in
                      ("extractor", "elapsed_ms", "limits", "errors", "candidates")}, indent=2))
    return 1 if index["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
