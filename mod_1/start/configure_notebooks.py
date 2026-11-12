"""Привязка ноутбуков курса к ядру проекта без изменения ячеек и выводов."""

import json
from pathlib import Path


KERNEL = {"display_name": "maximum-venv", "language": "python", "name": "maximum-venv"}
PROJECT_ROOT = Path(__file__).resolve().parent.parent


def notebooks(root):
    # Не обходим .venv, резервные копии и служебные checkpoint-файлы.
    return sorted(root.glob("les_*/*.ipynb"))


def configure_notebook(path):
    raw = path.read_bytes()
    text = raw.decode("utf-8-sig")
    document = json.loads(text)
    metadata = document.setdefault("metadata", {})
    previous = json.dumps(metadata, sort_keys=True)
    metadata["kernelspec"] = KERNEL.copy()
    # Хеш интерпретатора с другого компьютера мешает подбору местного ядра.
    metadata.pop("interpreter", None)
    if isinstance(metadata.get("vscode"), dict):
        metadata["vscode"].pop("interpreter", None)
    if json.dumps(metadata, sort_keys=True) == previous:
        return False

    # Находим только верхнеуровневое поле metadata. Остальной файл, включая
    # пользовательские ячейки, большие выводы и окончания строк, сохраняется.
    decoder = json.JSONDecoder()
    offset = text.index("{") + 1
    while True:
        while text[offset].isspace() or text[offset] == ",":
            offset += 1
        if text[offset] == "}":
            raise ValueError(f"В ноутбуке нет поля metadata: {path}")
        key, offset = decoder.raw_decode(text, offset)
        while text[offset].isspace() or text[offset] == ":":
            offset += 1
        start = offset
        _, offset = decoder.raw_decode(text, offset)
        if key == "metadata":
            break

    newline = "\r\n" if "\r\n" in text else "\n"
    replacement = json.dumps(metadata, ensure_ascii=False, indent=1)
    replacement = replacement.replace("\n", newline + " ")
    updated = text[:start] + replacement + text[offset:]
    # Проверяем, что меняются исключительно метаданные ноутбука.
    if json.loads(updated) != document:
        raise RuntimeError(f"Не удалось безопасно обновить метаданные: {path}")
    bom = b"\xef\xbb\xbf" if raw.startswith(b"\xef\xbb\xbf") else b""
    path.write_bytes(bom + updated.encode("utf-8"))
    return True


def main():
    paths = notebooks(PROJECT_ROOT)
    if not paths:
        raise RuntimeError("В папках les_* не найдены ноутбуки курса")
    changed = sum(configure_notebook(path) for path in paths)
    print(f"Ядро maximum-venv указано в {len(paths)} ноутбуках; обновлено: {changed}")


if __name__ == "__main__":
    main()
