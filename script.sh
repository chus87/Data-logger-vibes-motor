#!/usr/bin/env bash

DEFAULT_LOG="log.csv"
DATE_TAG=""
OUTDIR=""
LOGFILE=""

# ==== Buscar fichero de log ====
find_log_file() {
  local file="$DEFAULT_LOG"
  if [[ -f "$file" ]]; then
    LOGFILE="$file"
  else
    echo "No se ha encontrado '$DEFAULT_LOG' en el directorio actual."
    read -rp "Introduce ruta completa del fichero de log: " file
    if [[ ! -f "$file" ]]; then
      echo "ERROR: no se encuentra el fichero '$file'."
      exit 1
    fi
    LOGFILE="$file"
  fi
}

# ==== Crear directorio de salida con fecha ====
create_output_dir() {
  DATE_TAG=$(date +'%Y-%m-%d')
  OUTDIR="salida_${DATE_TAG}"
  mkdir -p "$OUTDIR"
  echo "Directorio de salida: $OUTDIR"
}

# ==== 1) Último punto GPS válido + enlace mapa ====
accion_mapa() {
  echo ">> [1] Generando enlace de mapa desde '$LOGFILE'..."

  local lat lon
  read -r lat lon < <(
    awk -F',' 'NR>1 && $4 != 0 && $5 != 0 {lat=$4; lon=$5} END{if(lat!="") print lat, lon}' "$LOGFILE"
  )

  if [[ -z "$lat" || -z "$lon" ]]; then
    echo "No se han encontrado coordenadas válidas (lat/lon != 0)."
    return
  fi

  local url="https://www.google.com/maps?q=${lat},${lon}"
  echo "Último punto GPS válido:"
  echo "  lat = $lat"
  echo "  lon = $lon"
  echo "URL Google Maps:"
  echo "  $url"

  {
    echo "Último punto GPS válido:"
    echo "lat = $lat"
    echo "lon = $lon"
    echo "URL Google Maps:"
    echo "$url"
  } > "$OUTDIR/ultimo_punto_gps_valido.txt"

  echo "Guardado en: $OUTDIR/ultimo_punto_gps_valido.txt"
}

# ==== 2) GPX con extensiones (speed, fix, sats, orientation, event) ====
accion_gpx() {
  echo ">> [2] Generando GPX..."

  local gpxfile="$OUTDIR/ruta.gpx"

  awk -F',' '
  BEGIN {
    print "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    print "<gpx version=\"1.1\" creator=\"esp32-logger\" xmlns=\"http://www.topografix.com/GPX/1/1\">"
    print "  <trk>"
    print "    <name>Ruta ESP32</name>"
    print "    <trkseg>"
  }
  NR>1 {
    millis=$1;
    date=$2;
    time=$3;
    lat=$4;
    lon=$5;
    speed=$6;      # km/h
    sats=$7;
    event=$11;
    fix=$12;       # 0 o 1
    orient=$13;    # orientación

    if (lat != 0 && lon != 0 && date != "0000-00-00") {
      iso = date "T" time "Z";
      print "      <trkpt lat=\"" lat "\" lon=\"" lon "\">"
      print "        <time>" iso "</time>"
      print "        <extensions>"
      print "          <speed_kmh>" speed "</speed_kmh>"
      print "          <fix>" fix "</fix>"
      print "          <sats>" sats "</sats>"
      print "          <orientation>" orient "</orientation>"
      print "          <event>" event "</event>"
      print "        </extensions>"
      print "      </trkpt>"
    }
  }
  END {
    print "    </trkseg>"
    print "  </trk>"
    print "</gpx>"
  }' "$LOGFILE" > "$gpxfile"

  echo "GPX generado: $gpxfile"
}

# ==== 3) Copia del log ====
accion_log_copia() {
  echo ">> [3] Copiando log al directorio de salida..."
  local copyname="log-${DATE_TAG}.csv"
  cp "$LOGFILE" "$OUTDIR/${copyname}"
  echo "Copiado como: $OUTDIR/${copyname}"
}

# ==== Comprobar / instalar gnuplot ====
asegurar_gnuplot() {
  if command -v gnuplot >/dev/null 2>&1; then
    return 0
  fi

  echo "gnuplot no está instalado."
  read -rp "¿Quieres instalarlo ahora con apt? [s/N]: " ans
  case "$ans" in
    s|S|y|Y)
      if command -v apt >/dev/null 2>&1; then
        echo "Instalando gnuplot (se requiere sudo)..."
        sudo apt update && sudo apt install -y gnuplot
        if command -v gnuplot >/dev/null 2>&1; then
          echo "gnuplot instalado correctamente."
          return 0
        else
          echo "ERROR: no se pudo instalar gnuplot automáticamente."
          return 1
        fi
      else
        echo "No se ha encontrado apt. Instala gnuplot manualmente."
        return 1
      fi
      ;;
    *)
      echo "No se instalará gnuplot. Omitiendo la gráfica."
      return 1
      ;;
  esac
}

# ==== 4) Gráfica con gnuplot (sin perder eventos) ====
accion_grafica() {
  echo ">> [4] Generando gráfica de aceleraciones..."

  if ! asegurar_gnuplot; then
    return
  fi

  local pngfile="$OUTDIR/aceleraciones.png"

  # Hora de inicio: primera línea con fecha válida
  local START_TIME
  START_TIME=$(awk -F',' 'NR>1 && $2!="0000-00-00" {print $2" "$3; exit}' "$LOGFILE")
  [[ -z "$START_TIME" ]] && START_TIME="0000-00-00 00:00:00"

  # Hora de fin: última línea con fecha válida
  local END_TIME
  END_TIME=$(awk -F',' 'NR>1 && $2!="0000-00-00" {last=$2" "$3} END{if(last!="") print last}' "$LOGFILE")
  [[ -z "$END_TIME" ]] && END_TIME="0000-00-00 00:00:00"

  gnuplot <<EOF
set terminal pngcairo size 3184,2160
set output "${pngfile}"
set datafile separator ","
set key outside
set grid
set xlabel "Tiempo (s) (millis/1000)"
set ylabel "Aceleración (g)"
set y2label "Velocidad (km/h)"
set y2tics
set title sprintf("Aceleraciones MPU6050\\nInicio: %s   Fin: %s","${START_TIME}","${END_TIME}")

# Ax: rojo, Ay: azul, Az: verde, Velocidad: morado, Evento: negro (sin every -> no se pierde ninguno)
plot "${LOGFILE}" using (\$1/1000):8  every ::2 with lines lc rgb "#e41a1c" title "Ax (g)", \
     "${LOGFILE}" using (\$1/1000):9  every ::2 with lines lc rgb "#377eb8" title "Ay (g)", \
     "${LOGFILE}" using (\$1/1000):10 every ::2 with lines lc rgb "#4daf4a" title "Az (g)", \
     "${LOGFILE}" using (\$1/1000):6  every ::2 with lines lc rgb "#984ea3" axes x1y2 title "Velocidad (km/h)", \
     "${LOGFILE}" using (\$1/1000):(\$11==1 ? 1.15 : 1/0) with impulses lc rgb "black" lw 2 title "Evento botón"
EOF

  echo "Gráfica generada: $pngfile"
}

# ==== 5) Todas las acciones ====
accion_todo() {
  accion_mapa
  accion_gpx
  accion_log_copia
  accion_grafica
}

# ==== Menú principal ====
main_menu() {
  echo "==========================================="
  echo "  Herramienta para procesar log de ESP32"
  echo "==========================================="
  echo "Fichero de log: $LOGFILE"
  echo "Directorio de salida: $OUTDIR"
  echo
  echo "1) Último punto GPS + enlace Google Maps"
  echo "2) Generar GPX de la ruta"
  echo "3) Copiar log al directorio de salida"
  echo "4) Generar gráfica Ax/Ay/Az + velocidad (gnuplot)"
  echo "5) Hacer TODO (1–4)"
  echo "0) Salir"
  echo

  read -rp "Elige opción: " opt

  case "$opt" in
    1) accion_mapa ;;
    2) accion_gpx ;;
    3) accion_log_copia ;;
    4) accion_grafica ;;
    5) accion_todo ;;
    0) echo "Saliendo."; exit 0 ;;
    *) echo "Opción no válida." ;;
  esac
}

# ==== Ejecución principal ====
find_log_file
create_output_dir
main_menu

