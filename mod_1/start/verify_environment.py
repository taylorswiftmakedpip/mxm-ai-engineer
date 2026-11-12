"""Проверка окружения, которую start/setup.ps1 запускает через Python проекта."""

import importlib
import json
from importlib.metadata import version
from pathlib import Path
import sys


def main():
    if sys.version_info[:3] != (3, 14, 10):
        raise RuntimeError(f"Нужен Python 3.14.10, обнаружен {sys.version}")
    if sys.prefix == sys.base_prefix:
        raise RuntimeError("Запущен Python вне виртуального окружения проекта")
    print(f"Python: {sys.version.split()[0]} ({sys.executable})")
    from jupyter_client.kernelspec import KernelSpecManager

    kernel = KernelSpecManager().get_kernel_spec("maximum-venv")
    if kernel.display_name != "maximum-venv" or Path(kernel.argv[0]).resolve() != Path(sys.executable).resolve():
        raise RuntimeError("Ядро maximum-venv должно использовать Python из окружения проекта")
    print("Ядро maximum-venv: настроено правильно")
    project_root = Path(__file__).resolve().parent.parent
    notebook_paths = sorted(project_root.glob("les_*/*.ipynb"))
    if not notebook_paths:
        raise RuntimeError("Не найдены ноутбуки курса")
    for path in notebook_paths:
        metadata = json.loads(path.read_text(encoding="utf-8-sig"))["metadata"]
        if metadata.get("kernelspec", {}).get("name") != "maximum-venv":
            raise RuntimeError(f"В {path.name} не настроено ядро maximum-venv")
    print(f"Привязка ноутбуков к ядру: проверено {len(notebook_paths)} файлов")
    requirements = Path(__file__).with_name("requirements.txt")
    for line in requirements.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        package, expected = line.split("==")
        actual = version(package)
        if actual != expected:
            raise RuntimeError(f"{package}: нужна версия {expected}, обнаружена {actual}")
        importlib.import_module(package)
        print(f"{package}: {actual}")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import pandas as pd

    frame = pd.DataFrame({"year": [2020, 2020, 2021], "value": [1.0, 3.0, 5.0]})
    grouped = frame.groupby("year").mean()
    if grouped.loc[2020, "value"] != 2.0:
        raise RuntimeError("Проверка группировки данных в pandas завершилась ошибкой")
    grouped.plot()
    plt.close("all")
    print("Импорты библиотек, группировка данных и построение графика: всё работает")

    # Реальный запуск зарегистрированного ядра: обнаруживаем неверный Python
    # и ошибки запуска, которых не видно при простом чтении kernel.json.
    import nbformat
    from nbclient import NotebookClient

    probe = nbformat.v4.new_notebook(cells=[nbformat.v4.new_code_cell(
        "import json, sys, numpy, pandas, matplotlib\n"
        "print(json.dumps({'executable': sys.executable, 'prefix': sys.prefix}))"
    )])
    NotebookClient(probe, kernel_name="maximum-venv", timeout=60, startup_timeout=60).execute()
    output = "".join(item.get("text", "") for item in probe.cells[0].outputs)
    actual = json.loads(output)
    if Path(actual["executable"]).resolve() != Path(sys.executable).resolve():
        raise RuntimeError(f"Ядро запустило другой Python: {actual['executable']}")
    if Path(actual["prefix"]).resolve() != project_root / ".venv":
        raise RuntimeError("Ядро запущено вне .venv проекта")
    print("Ядро maximum-venv: запущено, тестовая ячейка выполнена в .venv проекта")


if __name__ == "__main__":
    main()
