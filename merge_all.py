import os
from pathlib import Path

OUTPUT_FILE = "merged_all.txt"
list_files = []
# תיקיות שלא נכנסים אליהן בכלל
SKIP_DIRS = {
    "node_modules", "venv", ".venv", "env", "ENV",
    ".git", ".idea", ".vscode",
    "dist", "build", ".build", "dist-ssr",
    "__pycache__", ".pytest_cache", ".mypy_cache", "htmlcov",
    ".next", ".nuxt", ".vite", "coverage",".terraform",
}

# קבצים ספציפיים לדילוג
SKIP_FILES_EXACT = {
    "package.json",
    "package-lock.json",
    OUTPUT_FILE,
    "merge_all.py",
}

# קבצים שמדלגים עליהם לפי שם (לא סיומת!)
SKIP_BY_NAME = {
    "output.css", 
    ".dockerignore",
    ".gitignore",
    "LICENSE", "LICENSE.txt", "LICENSE.md",
    ".env" ,"terraform.tfstate","terraform.tfstate.backup",
    "terraform.tfvars",
    "terraform.tfstate.*", "*.log","*.lock","*.bak",
    ".terraform.lock.hcl",        
}

# סיומות בינאריות / לא רלוונטיות
SKIP_EXTS = {
    ".svg",
    ".png", ".jpg", ".jpeg", ".webp", ".gif", ".ico",
    ".pdf", ".zip", ".tar", ".gz", ".7z", ".rar",
    ".mp4", ".mov", ".avi", ".mkv",
    ".woff", ".woff2", ".ttf", ".eot",
    ".mp3", ".wav",
    ".exe", ".dll", ".so", ".dylib",".tflstate",".tfstate.backup",
}

# סיומות שמכניסים (כולל CSS!)
INCLUDE_EXTS = {
    ".py",
    ".js", ".jsx",
    ".ts", ".tsx",
    ".html",
    ".css",        # ✅ כל CSS חוץ מ־output.css
    ".json",
    ".yml", ".yaml",
    ".md", ".mdx",
    ".sh",
    ".tf",
    ".dockerfile",
    ".txt",
    ".example"
}

def should_skip_file(p: Path) -> bool:
    name_lower = p.name.lower()

    if p.name in SKIP_FILES_EXACT:
        return True

    if name_lower in SKIP_BY_NAME:
        return True

    if p.suffix.lower() in SKIP_EXTS:
        return True

    return False

def should_include_file(p: Path, root: Path = None) -> bool:
    # ✅ כל סוגי Dockerfile: Dockerfile, Dockerfile.backend, וכו'
    if p.name.lower() in {"dockerfile", "dockerfile.dev", "dockerfile.prod",
                          "jenkinsfile"," jenkinsfile"}:
        return True
    # ✅ Include all files inside the entities/ directory
    if root is not None:
        try:
            rel = p.relative_to(root)
            if rel.parts and rel.parts[0] == "entities":
                return True
        except ValueError:
            pass
    return p.suffix.lower() in INCLUDE_EXTS


def is_text_file(p: Path) -> bool:
    try:
        with open(p, "rb") as f:
            chunk = f.read(4096)
        return b"\x00" not in chunk
    except Exception:
        return False

def merge_project(root: Path) -> None:
    
    out_path = root / OUTPUT_FILE
    included, skipped = 0, 0

    with open(out_path, "w", encoding="utf-8") as out:
        for dirpath, dirnames, filenames in os.walk(root):
            # סינון תיקיות
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]

            for filename in sorted(filenames):
                file_path = Path(dirpath) / filename
                rel_path = file_path.relative_to(root)

                if should_skip_file(file_path):
                    skipped += 1
                    continue

                if not should_include_file(file_path, root):
                    skipped += 1
                    continue

                if not is_text_file(file_path):
                    skipped += 1
                    continue

                try:
                    content = file_path.read_text(encoding="utf-8", errors="replace")
                except Exception:
                    skipped += 1
                    continue

                out.write(f"\n--- START: {rel_path.as_posix()} ---\n")
                out.write(content)
                if not content.endswith("\n"):
                    out.write("\n")
                list_files.append(rel_path)    
                out.write(f"--- END: {rel_path.as_posix()} ---\n")

                included += 1

    print(f"✅ Created {OUTPUT_FILE}")
    print(f"📦 Included files: {included}")
    print(f"🚫 Skipped files:  {skipped}")
    print("⚔️ output.css was successfully excluded.")
    print ("The files are:")
    for file in list_files:
        print(file)
if __name__ == "__main__":
    merge_project(Path(".").resolve())
