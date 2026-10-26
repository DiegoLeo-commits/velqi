# Python script to build optimized site-packages.zip and bundle into python_app.zip
import os
import sys
import shutil
import zipfile
import compileall

def pack():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root_dir)
    
    root = "build/python-site-packages/x86_64"
    dest_zip = "python/site-packages.zip"
    temp_dir = "build/temp_site_packages"
    temp_arch_dir = os.path.join(temp_dir, "x86_64")
    
    if not os.path.isdir(root):
        print(f"ERROR: no se encontro {root}. Ejecute el paso 1 primero.")
        sys.exit(1)
        
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
    os.makedirs(temp_arch_dir)
    
    # 1. Copiar site-packages de x86_64
    print("Copiando paquetes...")
    shutil.copytree(root, temp_arch_dir, dirs_exist_ok=True)
    
    # 2. Ejecutar trim de extractores de yt-dlp en el temporal
    print("Recortando extractores innecesarios de yt-dlp...")
    sys.path.append(os.path.abspath("scripts"))
    import trim_ytdlp
    trim_ytdlp.trim_arch(temp_arch_dir)
    
    # 3. Empaquetar archivos fuente .py directamente (evita incompatibilidades de magic number)
    print("Conservando archivos fuente (.py) para compatibilidad multiplataforma...")

    # Eliminar __pycache__ y .pyc innecesarios antes de zippear
    for r, dirs, files in os.walk(temp_arch_dir, topdown=False):
        for f in files:
            if f.endswith(".pyc") or f.endswith(".pyo"):
                os.remove(os.path.join(r, f))
        for d in dirs:
            if d == "__pycache__":
                shutil.rmtree(os.path.join(r, d))

    # 6. Comprimir usando zipfile para maxima compatibilidad (ZIP_DEFLATED)
    print(f"Comprimiendo a {dest_zip}...")
    if os.path.exists(dest_zip):
        os.remove(dest_zip)
        
    with zipfile.ZipFile(dest_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for r, dirs, files in os.walk(temp_arch_dir):
            for file in files:
                full_path = os.path.join(r, file)
                rel_path = os.path.relpath(full_path, temp_arch_dir)
                zf.write(full_path, rel_path)
                
    # Limpiar temporal
    shutil.rmtree(temp_dir)
    
    # 7. Generar assets/python_app.zip con zipfile
    print("Empaquetando todo en assets/python_app.zip...")
    dest_app_zip = "assets/python_app.zip"
    if os.path.exists(dest_app_zip):
        os.remove(dest_app_zip)
        
    app_files = ["main.py", "ytdlp_backend.py", "ytmusic_backend.py", "cookies.txt", "site-packages.zip"]
    with zipfile.ZipFile(dest_app_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for f in app_files:
            file_path = os.path.join("python", f)
            if os.path.exists(file_path):
                zf.write(file_path, f)
            else:
                print(f"WARNING: no se encontro {file_path}")
                
    print("== PROCESO DE ZIP COMPLETADO CON EXITO ==")

if __name__ == "__main__":
    pack()
