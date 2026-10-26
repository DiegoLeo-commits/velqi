"""
Optimiza yt-dlp para Velqi: solo reemplaza _extractors.py con YouTube-only.
NO elimina archivos físicos para no romper imports dinámicos de yt-dlp.

Estrategia segura:
  - Mantiene todos los archivos .py del directorio extractor intactos
  - Solo sobreescribe _extractors.py con una versión que solo exporta YouTube
  - Elimina .dist-info y share/ que sí son seguros de eliminar (no son importados)

Usage (desde raíz del proyecto):
    python scripts/trim_ytdlp.py build/python-site-packages
"""
import os
import shutil
import sys

# _extractors.py mínimo: solo importa extractores de YouTube.
# Al reemplazarlo, yt-dlp solo registrará extractores YouTube en su lista
# interna, acelerando el startup sin romper módulos referenciados en otras partes.
MINIMAL_EXTRACTORS_PY = '''# flake8: noqa: F401
# Minimal _extractors.py — YouTube only (Velqi app optimization)
# NOTE: Los archivos físicos de otros extractores siguen presentes para evitar
# ModuleNotFoundError en imports dinámicos internos de yt-dlp.
from .youtube import (
    YoutubeClipIE,
    YoutubeConsentRedirectIE,
    YoutubeFavouritesIE,
    YoutubeHistoryIE,
    YoutubeIE,
    YoutubeLivestreamEmbedIE,
    YoutubeMusicSearchURLIE,
    YoutubeNotificationsIE,
    YoutubePlaylistIE,
    YoutubeRecommendedIE,
    YoutubeSearchIE,
    YoutubeSearchURLIE,
    YoutubeShortsAudioPivotIE,
    YoutubeSubscriptionsIE,
    YoutubeTabIE,
    YoutubeTruncatedIDIE,
    YoutubeTruncatedURLIE,
    YoutubeWatchLaterIE,
    YoutubeYtBeIE,
    YoutubeYtUserIE,
)
'''


def trim_arch(arch_dir: str):
    extractor_dir = os.path.join(arch_dir, "yt_dlp", "extractor")
    if not os.path.isdir(extractor_dir):
        print(f"  [SKIP] no extractor dir in {arch_dir}")
        return

    # SOLO reemplazar _extractors.py — NO eliminar archivos físicos
    extractors_py = os.path.join(extractor_dir, "_extractors.py")
    with open(extractors_py, "w", encoding="utf-8") as f:
        f.write(MINIMAL_EXTRACTORS_PY)
    print(f"  [OK] _extractors.py reemplazado con versión YouTube-only (archivos físicos intactos)")

    # Eliminar __pycache__ y .pyc — ahorran ~11MB por arco sin romper nada.
    # Python los regenera en tiempo de ejecución si los necesita.
    pycache_removed = 0
    pyc_removed = 0
    for dp, dirs, files in os.walk(arch_dir, topdown=False):
        for f in files:
            if f.endswith(".pyc"):
                os.remove(os.path.join(dp, f))
                pyc_removed += 1
        for d in dirs:
            if d == "__pycache__":
                full = os.path.join(dp, d)
                if os.path.isdir(full):
                    shutil.rmtree(full)
                    pycache_removed += 1

    if pycache_removed or pyc_removed:
        print(f"  [OK] Eliminados {pycache_removed} dirs __pycache__, {pyc_removed} archivos .pyc")

    size_mb = sum(
        os.path.getsize(os.path.join(dp, f))
        for dp, dn, fn in os.walk(arch_dir)
        for f in fn
    ) / 1024 / 1024

    print(f"  {os.path.basename(arch_dir)}: tamaño restante {size_mb:.1f}MB")


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "build/python-site-packages"
    if not os.path.isdir(root):
        print(f"ERROR: directory not found: {root}")
        sys.exit(1)

    print(f"Optimizando yt-dlp en {root} (estrategia segura: solo _extractors.py)")
    for arch in sorted(os.listdir(root)):
        arch_path = os.path.join(root, arch)
        if os.path.isdir(arch_path):
            trim_arch(arch_path)
    print("Listo. Reconstruir el APK para aplicar los cambios.")


if __name__ == "__main__":
    main()
