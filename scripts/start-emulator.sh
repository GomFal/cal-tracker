#!/usr/bin/env bash
# start-emulator.sh — Lanza el emulador Android de Cal Tracker con máxima aceleración.
#
# Configuración verificada el 2026-08-01 en la workstation de Antonio
# (Medium_Phone_API_36.1, NVIDIA RTX 3060, KVM):
#   -gpu host   -> renderiza con la GPU real (RTX 3060). Mucho más fluido que
#                  -gpu off (software). Si la GPU host crashea, usar --gpu=off.
#   -memory 6144 -> 6 GB de RAM guest. Con -gpu host no hace falta más y el host
#                  (31 GB, a menudo con presión de memoria) evita el swap.
#   -cores 8    -> 8 vCPUs guest (host de 16 núcleos).
#   -accel on   -> obliga KVM; falla en vez de arrancar lento sin aceleración.
#   -netfast    -> red guest de baja latencia.
#
# El XAUTHORITY del Xorg activo rota entre sesiones (sddm genera
# /run/sddm/xauth_*), así que se resuelve automáticamente en cada lanzamiento.
#
# Uso:
#   scripts/start-emulator.sh                # config recomendada (GPU host, 6 GB, 8 cores)
#   scripts/start-emulator.sh --restart      # reinicia aunque ya esté corriendo
#   scripts/start-emulator.sh --wipe-data    # formatea /data (fix INSTALL_FAILED_INSUFFICIENT_STORAGE)
#   scripts/start-emulator.sh --memory=8192 --cores=8 --gpu=host
#
# Variables de entorno: ANDROID_SDK, AVD, MEMORY, CORES, GPU.

set -euo pipefail

ANDROID_SDK="${ANDROID_SDK:-/home/antonio/Android/Sdk}"
AVD="${AVD:-Medium_Phone_API_36.1}"
MEMORY="${MEMORY:-6144}"
CORES="${CORES:-8}"
GPU="${GPU:-host}"
WIPE_DATA=false
RESTART=false

for arg in "$@"; do
  case "$arg" in
    --wipe-data) WIPE_DATA=true ;;
    --restart) RESTART=true ;;
    --memory=*) MEMORY="${arg#*=}" ;;
    --cores=*) CORES="${arg#*=}" ;;
    --gpu=*) GPU="${arg#*=}" ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Argumento desconocido: $arg (usa --help)" >&2; exit 1 ;;
  esac
done

export PATH="$ANDROID_SDK/emulator:$ANDROID_SDK/platform-tools:$PATH"

# --- Precondiciones -----------------------------------------------------------
if [[ ! -e /dev/kvm ]]; then
  echo "ERROR: /dev/kvm no existe. La aceleración KVM no está disponible." >&2
  exit 1
fi
if ! "$ANDROID_SDK/emulator/emulator" -list-avds 2>/dev/null | grep -qx "$AVD"; then
  echo "ERROR: el AVD '$AVD' no existe. Disponibles: $("$ANDROID_SDK/emulator/emulator" -list-avds 2>/dev/null | tr '\n' ' ')" >&2
  exit 1
fi
if ! "$ANDROID_SDK/emulator/emulator" -accel-check 2>/dev/null | grep -q 'is installed and usable'; then
  echo "ERROR: KVM no usable. Ejecuta '$ANDROID_SDK/emulator/emulator -accel-check'." >&2
  exit 1
fi

# --- ¿Ya está corriendo? ------------------------------------------------------
if systemctl --user is-active --quiet cal-tracker-emulator.service; then
  if [[ "$RESTART" == false ]]; then
    echo "El emulador ya está activo (cal-tracker-emulator.service)."
    echo "Usa 'scripts/start-emulator.sh --restart' para reiniciarlo, o 'systemctl --user stop cal-tracker-emulator.service' para pararlo."
    exit 0
  fi
  echo "Reiniciando emulador existente..."
  systemctl --user stop cal-tracker-emulator.service 2>/dev/null || true
fi

# --- Resolver XAUTHORITY del Xorg activo (rota entre sesiones) ----------------
DISPLAY_ENV="${DISPLAY:-:0}"
XAUTH=""
XORG_PID="$(pgrep -x Xorg | head -1 || true)"
if [[ -n "$XORG_PID" ]]; then
  XAUTH="$(tr '\0' '\n' < "/proc/$XORG_PID/environ" 2>/dev/null | sed -n 's/^XAUTHORITY=//p' | head -1 || true)"
  if [[ -z "$XAUTH" ]]; then
    XAUTH="$(ps -p "$XORG_PID" -o args= 2>/dev/null | grep -oP '(?<=-auth )\S+' | head -1 || true)"
  fi
fi
if [[ -z "$XAUTH" ]]; then
  echo "AVISO: no se pudo resolver XAUTHORITY del Xorg; se usa DISPLAY=$DISPLAY_ENV sin token." >&2
fi

# --- Parar servicios previos y procesos stale ---------------------------------
systemctl --user stop cal-tracker-app-watch.service 2>/dev/null || true
systemctl --user stop cal-tracker-emulator-test.service 2>/dev/null || true
ps aux | awk '/qemu-system/ && !/awk/ {print $2}' | xargs -r kill -9
sleep 2

# --- Lanzar (cold boot, sin política de restart automático) --------------------
WIPE_FLAG=()
[[ "$WIPE_DATA" == true ]] && WIPE_FLAG=(-wipe-data)

echo "Lanzando emulador: AVD=$AVD memoria=${MEMORY}MB cores=$CORES gpu=$GPU accel=KVM netfast cold-boot${WIPE_DATA:+ +wipe-data}"
systemd-run --user --unit=cal-tracker-emulator --collect \
  --working-directory="$PWD" \
  -E PATH="$ANDROID_SDK/emulator:$ANDROID_SDK/platform-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  -E DISPLAY="$DISPLAY_ENV" \
  -E XAUTHORITY="$XAUTH" \
  -E XDG_RUNTIME_DIR=/run/user/1000 \
  -E DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  -p StandardOutput=append:/tmp/emulator-systemd.log \
  -p StandardError=append:/tmp/emulator-systemd.log \
  "$ANDROID_SDK/emulator/emulator" -avd "$AVD" -memory "$MEMORY" -cores "$CORES" \
    -accel on -gpu "$GPU" -netfast -no-snapshot -no-snapshot-save \
    -allow-host-audio -no-boot-anim "${WIPE_FLAG[@]}"

# --- Esperar boot completo ------------------------------------------------------
echo "Esperando arranque del guest (hasta 7 min)..."
adb -s emulator-5554 wait-for-device
timeout 420 adb -s emulator-5554 shell 'while [[ $(getprop sys.boot_completed) != 1 ]]; do sleep 3; done; echo Boot completed'

echo "=== Verificación ==="
adb -s emulator-5554 shell echo alive
adb -s emulator-5554 shell df -h /data | tail -1
echo "Emulador listo. Logs: /tmp/emulator-systemd.log (systemctl --user status cal-tracker-emulator.service)"
