#!/usr/bin/env bash
# Cambia una cara en un video con FaceFusion dentro de Docker (solo CPU).
# Uso: ./cambiar_cara.sh -v video.mp4 -f foto1.png -f foto2.png [-o salida.mp4] [opciones]
set -euo pipefail

IMAGE="${IMAGE:-facefusion-cpu}"            # imagen creada con el Dockerfile de esta carpeta
VOLUMEN_MODELOS="${VOLUMEN_MODELOS:-facefusion-assets}"  # guarda los modelos para no bajarlos cada vez

VIDEO=""
FOTOS=()
SALIDA="resultado.mp4"
MODO="one"             # one = cambia solo la cara mas grande de cada fotograma
                       # many = cambia todas las caras
                       # reference = sigue una cara concreta (ver --posicion y --distancia)
POSICION=0             # solo con --modo reference: posicion de la cara (orden grande a chico)
DISTANCIA=0.4          # solo con --modo reference: mas alto = mas tolerante, pero cambia caras de mas
FOTOGRAMA_REF=0        # solo con --modo reference: fotograma donde se elige la cara
INICIO=""              # fotograma inicial (para pruebas cortas)
FIN=""                 # fotograma final
MODELO="hyperswap_1c_256"
PIXEL_BOOST="512x512"  # 256x256 es mas rapido, 512x512 se ve mejor
MEJORAR="si"           # si = aplica face_enhancer (codeformer); no = mas rapido
BLEND=80               # fuerza del enhancer, 0-100
HILOS=3                # mas hilos = mas rapido pero mas memoria (si el contenedor muere por memoria, baja esto)
DRY_RUN=0

uso() {
  cat <<EOF
Uso: $0 -v VIDEO -f FOTO [-f FOTO ...] [opciones]

  -v, --video RUTA        video donde se cambia la cara
  -f, --foto RUTA         foto de la cara nueva (repetir para varias; si son buenas, mejoran el parecido)
  -o, --salida RUTA       archivo de salida (por defecto: $SALIDA)
      --modo MODO         one | many | reference (por defecto: $MODO)
      --posicion N        con reference: posicion de la cara (por defecto: $POSICION)
      --distancia X       con reference: tolerancia de seguimiento (por defecto: $DISTANCIA)
      --fotograma-ref N   con reference: fotograma donde se elige la cara (por defecto: $FOTOGRAMA_REF)
      --inicio N --fin N  procesar solo ese tramo de fotogramas (24 fotogramas ~ 1 s)
      --modelo NOMBRE     modelo de cambio de cara (por defecto: $MODELO)
      --pixel-boost WxH   256x256 | 512x512 | 1024x1024 (por defecto: $PIXEL_BOOST)
      --sin-mejora        no aplicar face_enhancer (mas rapido)
      --blend N           fuerza del enhancer (por defecto: $BLEND)
      --hilos N           hilos de CPU (por defecto: $HILOS)
      --dry-run           solo mostrar el comando, sin ejecutarlo
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--video) VIDEO="$2"; shift 2 ;;
    -f|--foto) FOTOS+=("$2"); shift 2 ;;
    -o|--salida) SALIDA="$2"; shift 2 ;;
    --modo) MODO="$2"; shift 2 ;;
    --posicion) POSICION="$2"; shift 2 ;;
    --distancia) DISTANCIA="$2"; shift 2 ;;
    --fotograma-ref) FOTOGRAMA_REF="$2"; shift 2 ;;
    --inicio) INICIO="$2"; shift 2 ;;
    --fin) FIN="$2"; shift 2 ;;
    --modelo) MODELO="$2"; shift 2 ;;
    --pixel-boost) PIXEL_BOOST="$2"; shift 2 ;;
    --sin-mejora) MEJORAR="no"; shift ;;
    --blend) BLEND="$2"; shift 2 ;;
    --hilos) HILOS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) uso; exit 0 ;;
    *) echo "Opcion desconocida: $1" >&2; uso; exit 1 ;;
  esac
done

[[ -n "$VIDEO" && ${#FOTOS[@]} -gt 0 ]] || { echo "Faltan -v y al menos un -f" >&2; uso; exit 1; }
[[ -f "$VIDEO" ]] || { echo "No existe el video: $VIDEO" >&2; exit 1; }
for f in "${FOTOS[@]}"; do [[ -f "$f" ]] || { echo "No existe la foto: $f" >&2; exit 1; }; done
[[ "$MODO" =~ ^(one|many|reference)$ ]] || { echo "--modo debe ser one, many o reference" >&2; exit 1; }
if [[ -n "$INICIO" || -n "$FIN" ]]; then
  [[ -n "$INICIO" && -n "$FIN" ]] || { echo "Usa --inicio y --fin juntos" >&2; exit 1; }
  (( FIN > INICIO )) || { echo "--fin debe ser mayor que --inicio" >&2; exit 1; }
fi

# Carpeta de trabajo que se monta en el contenedor (se borra al terminar)
TRABAJO="$(mktemp -d)"
trap 'rm -rf "$TRABAJO"' EXIT
mkdir -p "$TRABAJO/in" "$TRABAJO/out"
cp "$VIDEO" "$TRABAJO/in/video.${VIDEO##*.}"
VIDEO_EN="/work/in/video.${VIDEO##*.}"

FOTOS_EN=()
n=1
for f in "${FOTOS[@]}"; do
  ext="${f##*.}"
  cp "$f" "$TRABAJO/in/foto_$n.$ext"
  FOTOS_EN+=("/work/in/foto_$n.$ext")
  n=$((n + 1))
done

PROCESADORES=(face_swapper)
EXTRA=()
if [[ "$MEJORAR" == "si" ]]; then
  PROCESADORES+=(face_enhancer)
  EXTRA+=(--face-enhancer-model codeformer --face-enhancer-blend "$BLEND")
fi
if [[ "$MODO" == "reference" ]]; then
  EXTRA+=(--reference-face-position "$POSICION" --reference-face-distance "$DISTANCIA" --reference-frame-number "$FOTOGRAMA_REF")
fi
if [[ -n "$INICIO" ]]; then
  EXTRA+=(--trim-frame-start "$INICIO" --trim-frame-end "$FIN")
fi

CMD=(docker run --rm
  -v "$TRABAJO:/work"
  -v "$VOLUMEN_MODELOS:/facefusion/.assets"
  --entrypoint python "$IMAGE" facefusion.py headless-run
  --source-paths "${FOTOS_EN[@]}"
  --target-path "$VIDEO_EN"
  --output-path "/work/out/salida.mp4"
  --processors "${PROCESADORES[@]}"
  --face-swapper-model "$MODELO" --face-swapper-pixel-boost "$PIXEL_BOOST" --face-swapper-weight 1.0
  --face-selector-mode "$MODO" --face-selector-order large-small
  --face-mask-types box occlusion region --face-mask-blur 0.4
  --execution-providers cpu --execution-thread-count "$HILOS"
  --output-video-encoder libx264 --output-video-quality 90
  "${EXTRA[@]}")

if [[ $DRY_RUN -eq 1 ]]; then
  printf '%q ' "${CMD[@]}"; echo
  exit 0
fi

echo "Procesando... (puede tardar mucho en CPU: ~5-10 s por fotograma con enhancer)"
"${CMD[@]}"

mkdir -p "$(dirname "$SALIDA")"
cp "$TRABAJO/out/salida.mp4" "$SALIDA"
echo "Listo: $SALIDA"
