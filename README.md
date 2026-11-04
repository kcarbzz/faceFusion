# Cambio de cara en video con FaceFusion + Docker

Script para cambiar una cara en un video usando [FaceFusion](https://github.com/facefusion/facefusion)
dentro de Docker. Sin interfaz, sin pagar y sin marca de agua. Funciona solo con CPU, por lo que es lento pero fiable.

> **Uso responsable:** usa solo caras de personas que dieron su permiso (tú, amigos que aceptan).
> No subas a GitHub fotos ni videos de personas. El `.gitignore` ya los excluye.

## Requisitos
- Docker (Docker Desktop o Colima en Mac). Con Colima: `colima start --cpu 6 --memory 10 --disk 25`
- ~10 GB de RAM para Docker y ~6 GB de disco (imagen y modelos)

## 1. Construir la imagen (una sola vez)
```bash
docker build -t facefusion-cpu .
```

## 2. Prueba corta (siempre antes del video completo)
24 fotogramas ≈ 1 segundo. Esta prueba de 2 segundos tarda unos minutos:
```bash
./cambiar_cara.sh -v mi_video.mp4 -f amigo1.png -f amigo2.png \
  --inicio 210 --fin 258 -o prueba.mp4
```

## 3. Video completo
```bash
./cambiar_cara.sh -v mi_video.mp4 -f amigo1.png -f amigo2.png -o resultado.mp4
```

Con `--dry-run` solo imprime el comando de Docker, sin ejecutarlo.

## Qué modo usar (`--modo`)
| Modo | Qué hace | Cuándo |
|------|----------|--------|
| `one` (por defecto) | Cambia **solo la cara más grande** de cada fotograma | La persona a cambiar siempre sale más cerca de la cámara |
| `many` | Cambia **todas** las caras | Quieres cambiar a todos |
| `reference` | Sigue una cara concreta (`--posicion`, `--distancia`) | Hay varias caras y `one` elige mal |

Con `reference`, una `--distancia` baja (0,3) pierde la cara cuando gira la cabeza, y una alta (0,6) empieza a cambiar caras de otras personas.

## Consejos para mejor parecido
- Usa **varias fotos buenas** (de frente, con luz, sin lentes ni gorra). FaceFusion las combina. Una foto mala puede empeorar el resultado.
- No mezcles fotos de **personas distintas** en `-f`: se promedian las caras.
- `--pixel-boost 512x512` y el enhancer (por defecto) dan más calidad. `--sin-mejora` y `256x256` son más rápidos.
- Lentes oscuros, caras muy pequeñas o de perfil limitan el resultado.
- El cambio de cara **no cambia el pelo ni la forma de la cabeza**.

## Velocidad de referencia (MacBook Air M4, Docker en CPU, 3 hilos)
~5-10 s por fotograma con enhancer a 512x512. Un video de 30 s (714 fotogramas) ≈ 1 a 1,5 horas.
Si el contenedor muere por memoria (`exit 137`), baja `--hilos`.

## Cómo funciona
El script copia tus archivos a una carpeta temporal, la monta en un contenedor con la imagen de FaceFusion
y ejecuta `headless-run`. Los modelos se guardan en un volumen de Docker (`facefusion-assets`) para no volver a bajarlos.
