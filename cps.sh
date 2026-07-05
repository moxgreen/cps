#!/usr/bin/env bash
#
# rsync‑md5.sh – copia con progresso + verifica MD5
#
# Uso:
#   ./rsync-md5.sh SRC… DEST
#   ./rsync-md5.sh *.mp4 /media/usb
#
# Requisiti: rsync, md5sum, bash ≥ 4.

set -euo pipefail

if (( $# < 2 )); then
  echo "Uso: $0 SRC… DEST" >&2
  exit 1
fi

dest="${@: -1}"               # ultimo argomento = destinazione
srcs=( "${@:1:$#-1}" )        # tutti gli altri = sorgenti

# 1. Copia con progresso (-a = archivio, --partial = riprende se interrotta)
# -----------------------------------------------------------------------
rsync -a --partial --info=progress2 \
      --human-readable        \
      "${srcs[@]}" "$dest"

# 2. Flush forzato dei buffer a disco
# -----------------------------------------------------------------------
sync                                # forza il commit dei dati su disco

# (Opzionale, richiede root) – svuota la page‑cache, così il checksum viene
# ricalcolato leggendo di nuovo da disco, non da RAM:
#   echo 3 > /proc/sys/vm/drop_caches

# 3. Verifica MD5 di tutti i file sorgenti
# -----------------------------------------------------------------------
fail=0

for src_path in "${srcs[@]}"; do
    file=$(basename "$src_path")
    dst_path="$dest/$file"

    if [[ ! -f "$dst_path" ]]; then
        echo "❌  File mancante nella destinazione: $file" >&2
        fail=1
        continue
    fi

    md_src=$(md5sum "$src_path" | awk '{print $1}')
    md_dst=$(md5sum "$dst_path" | awk '{print $1}')

    if [[ "$md_src" != "$md_dst" ]]; then
        echo "❌  MD5 diverso: $file" >&2
        fail=1
    else
        echo "✔️  $file"
    fi
done

if (( fail )); then
    echo "La copia presenta errori!" >&2
    exit 2
else
    echo "Tutti i file verificati con successo."
    
    read -r -p "Vuoi eliminare i file sorgente originali? (s/N) " confirm_delete
    # Convert input to lowercase for case-insensitive comparison (requires Bash 4+)
    if [[ "${confirm_delete,,}" == "s" ]]; then
        echo "Eliminazione dei file sorgente..."
        for src_to_delete in "${srcs[@]}"; do
            if [[ -e "$src_to_delete" ]]; then # Check if source exists
                if rm -rf "$src_to_delete"; then
                    echo "🗑️  Eliminato: $src_to_delete"
                else
                    echo "⚠️  Errore nell'eliminare $src_to_delete" >&2
                fi
            else
                echo "ℹ️  Sorgente già rimossa o non trovata: $src_to_delete"
            fi
        done
        echo "Eliminazione dei file sorgente completata."
    else
        echo "I file sorgente non sono stati eliminati."
    fi
    exit 0 # Added explicit exit 0 for clarity
fi

