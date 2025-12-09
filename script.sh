#!/usr/bin/env bash

# ==================== CONFIGURACIÓN ====================

DEFAULT_LOG="log.csv"
LOGFILE=""
OUTDIR=""
DATE_TAG=""

BASE_WIDTH=3840     # 4K horizontal
BASE_HEIGHT=2160
MAX_WIDTH=15360     # límite absoluto
P4K_CAPACITY=20000  # nº de muestras que consideramos "bien" para 4K

# ==================== UTILIDADES ====================

find_log_file() {
  if [[ -f "$DEFAULT_LOG" ]]; then
    LOGFILE="$DEFAULT_LOG"
  else
    echo "No se encuentra '$DEFAULT_LOG' en el directorio actual."
    read -rp "Ruta completa del fichero de log: " LOGFILE
    if [[ ! -f "$LOGFILE" ]]; then
      echo "ERROR: no se encuentra '$LOGFILE'."
      exit 1
    fi
  fi
}

create_output_dir() {
  DATE_TAG=$(date +'%Y-%m-%d')
  OUTDIR="salida_${DATE_TAG}"
  mkdir -p "$OUTDIR"
  echo "Directorio de salida: $OUTDIR"
}

# Cálculo ancho, capacidad y nº de segmentos para N puntos
calc_width_and_segments() {
  local N="$1"

  if (( N <= 0 )); then
    WIDTH=$BASE_WIDTH
    SEGMENTS=0
    CAPACITY=0
    return
  fi

  local k=$(( (N + P4K_CAPACITY - 1) / P4K_CAPACITY ))  # ceil(N/P4K)
  (( k < 1 )) && k=1
  (( k > 4 )) && k=4

  WIDTH=$(( BASE_WIDTH * k ))
  CAPACITY=$(( P4K_CAPACITY * k ))
  SEGMENTS=$(( (N + CAPACITY - 1) / CAPACITY ))
}

# Frecuencia de muestreo aproximada a partir de millis (ms por muestra)
calc_ms_per_sample() {
  awk -F',' '
    NR==2 { last=$1; next }
    NR>2  {
      d=$1-last;
      if (d>0) { sum+=d; n++; last=$1 }
    }
    END {
      if (n>0) printf "%.3f\n", sum/n;
      else print 20.0;
    }
  ' "$LOGFILE"
}

# ==================== ACCIÓN 1: MAPA ====================

accion_mapa() {
  echo ">> [1] Extrayendo último punto GPS válido..."

  local lat lon
  read -r lat lon < <(
    awk -F',' 'NR>1 && $4!=0 && $5!=0 {lat=$4; lon=$5} END{if(lat!="") print lat, lon}' "$LOGFILE"
  )

  if [[ -z "$lat" || -z "$lon" ]]; then
    echo "No se han encontrado coordenadas válidas."
    return
  fi

  local url="https://www.google.com/maps?q=${lat},${lon}"
  {
    echo "Último punto GPS válido:"
    echo "lat = $lat"
    echo "lon = $lon"
    echo "URL Google Maps:"
    echo "$url"
  } > "$OUTDIR/ultimo_punto_gps_valido.txt"

  echo "Guardado: $OUTDIR/ultimo_punto_gps_valido.txt"
}

# ==================== ACCIÓN 2: GPX ====================

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
    speed=$6;
    sats=$7;
    event=$11;
    fix=$12;
    orient=$13;

    if (lat!=0 && lon!=0 && date!="0000-00-00") {
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

# ==================== ACCIÓN 3: COPIA LOG ====================

accion_log_copia() {
  echo ">> [3] Copiando log..."

  local copyname="log-${DATE_TAG}.csv"
  cp "$LOGFILE" "$OUTDIR/${copyname}"
  echo "Copiado como: $OUTDIR/${copyname}"
}

# ==================== ACCIÓN 4A: GRÁFICA PRINCIPAL ====================

accion_grafica_principal() {
  echo ">> [4] Generando gráfica(s) principal(es)..."

  # Calcular inicio y fin con fecha válida
  local START_TIME END_TIME
  START_TIME=$(awk -F',' 'NR>1 && $2!="0000-00-00" {print $2" "$3; exit}' "$LOGFILE")
  [[ -z "$START_TIME" ]] && START_TIME="0000-00-00 00:00:00"
  END_TIME=$(awk -F',' 'NR>1 && $2!="0000-00-00" {last=$2" "$3} END{print last}' "$LOGFILE")
  [[ -z "$END_TIME" ]] && END_TIME="0000-00-00 00:00:00"

  # Extraer datos sin cabecera
  local DATA="$OUTDIR/_data_noheader_main.tmp"
  tail -n +2 "$LOGFILE" > "$DATA"

  local N
  N=$(wc -l < "$DATA")
  if (( N <= 0 )); then
    echo "No hay datos (aparte de la cabecera)."
    rm -f "$DATA"
    return
  fi

  calc_width_and_segments "$N"
  echo "  Puntos totales: $N"
  echo "  Ancho base: ${WIDTH}px, capacidad por imagen: $CAPACITY puntos, segmentos: $SEGMENTS"

  local seg
  for (( seg=0; seg<SEGMENTS; seg++ )); do
    local start=$(( seg * CAPACITY + 1 ))
    local end=$(( (seg + 1) * CAPACITY ))
    (( end > N )) && end=$N

    local SEGFILE="$OUTDIR/main_segment_$((seg+1)).csv"
    sed -n "${start},${end}p" "$DATA" > "$SEGFILE"

    local PNG="$OUTDIR/aceleraciones_$((seg+1)).png"

    gnuplot <<EOF
set terminal pngcairo size ${WIDTH},${BASE_HEIGHT}
set output "${PNG}"
set datafile separator ","
set grid
set key outside
set xlabel "Tiempo (s) (millis/1000)"
set ylabel "Aceleración (g)"
set y2label "Velocidad (km/h)"
set y2tics
set title sprintf("Aceleraciones MPU6050 (segmento %d/%d)\\nInicio: %s   Fin: %s", ${seg}+1, ${SEGMENTS}, "${START_TIME}", "${END_TIME}")

plot \
 "${SEGFILE}" using (\$1/1000):8  with lines lc rgb "#e41a1c" title "Ax (g)", \
 "${SEGFILE}" using (\$1/1000):9  with lines lc rgb "#377eb8" title "Ay (g)", \
 "${SEGFILE}" using (\$1/1000):10 with lines lc rgb "#4daf4a" title "Az (g)", \
 "${SEGFILE}" using (\$1/1000):6  with lines lc rgb "#984ea3" axes x1y2 title "Velocidad (km/h)", \
 "${SEGFILE}" using (\$1/1000):(\$11==1 ? 1.15 : 1/0) with impulses lc rgb "black" lw 2 title "Evento botón"
EOF

    echo "  Gráfica principal segmento $((seg+1)) generada: $PNG"
  done

  rm -f "$DATA"
}

# ==================== ACCIÓN 4B: GRÁFICAS DE EVENTOS (±5 s) ====================

accion_graficas_eventos() {
  echo ">> [4b] Analizando eventos para gráficas detalladas..."

  # Buscar líneas con event==1 (NR y millis)
  local EVTFILE="$OUTDIR/_event_lines.tmp"
  awk -F',' 'NR>1 && $11==1 {print NR","$1}' "$LOGFILE" > "$EVTFILE"

  if [[ ! -s "$EVTFILE" ]]; then
    echo "No hay eventos registrados (column 11 == 1)."
    rm -f "$EVTFILE"
    return
  fi

  local ms_per_sample
  ms_per_sample=$(calc_ms_per_sample)
  if [[ -z "$ms_per_sample" ]]; then
    ms_per_sample=20.0
  fi

  echo "  ms por muestra aproximado: $ms_per_sample"

  local samples_5s
  samples_5s=$(awk -v ms="$ms_per_sample" 'BEGIN{printf "%d", (5000.0/ms)+0.5}')

  echo "  Ventana por evento: ±${samples_5s} muestras"

  local TOTAL_LINES
  TOTAL_LINES=$(wc -l < "$LOGFILE")

  mkdir -p "$OUTDIR/eventos"

  while IFS=',' read -r lineno millis; do
    echo "  Evento en línea $lineno (millis=$millis)..."

    local start=$(( lineno - samples_5s ))
    local end=$(( lineno + samples_5s ))
    (( start < 2 )) && start=2
    (( end > TOTAL_LINES )) && end=$TOTAL_LINES

    local EVTDIR="$OUTDIR/eventos/evento_${lineno}"
    mkdir -p "$EVTDIR"

    local SEGFILE="$EVTDIR/segmento.csv"
    sed -n "${start},${end}p" "$LOGFILE" > "$SEGFILE.tmp"
    # quitar cabecera si por algún motivo entrara
    awk -F',' 'NR==1 && $1=="millis" {next} {print}' "$SEGFILE.tmp" > "$SEGFILE"
    rm -f "$SEGFILE.tmp"

    local N
    N=$(wc -l < "$SEGFILE")
    if (( N <= 0 )); then
      echo "    Segmento vacío, se omite."
      continue
    fi

    calc_width_and_segments "$N"
    # Para eventos, casi siempre SEGMENTS=1; si no, se respetan varios trozos.
    local seg
    for (( seg=0; seg<SEGMENTS; seg++ )); do
      local start2=$(( seg * CAPACITY + 1 ))
      local end2=$(( (seg + 1) * CAPACITY ))
      (( end2 > N )) && end2=$N

      local SEGFILE2="$EVTDIR/segmento_$((seg+1)).csv"
      sed -n "${start2},${end2}p" "$SEGFILE" > "$SEGFILE2"

      local PNG="$EVTDIR/evento_${lineno}_seg$((seg+1)).png"

      # Tiempo del evento en segundos (aprox)
      local t_event
      t_event=$(awk -F',' 'NR==1{print $1/1000.0}' <<<"$millis")

      gnuplot <<EOF
set terminal pngcairo size ${WIDTH},${BASE_HEIGHT}
set output "${PNG}"
set datafile separator ","
set grid
set xlabel "Tiempo (s)"
set ylabel "Aceleración (g)"
set title sprintf("Evento línea %d (segmento %d/%d)", ${lineno}, ${seg}+1, ${SEGMENTS})
set arrow 1 from ${t_event}, graph 0 to ${t_event}, graph 1 nohead lc rgb "black" lw 2
plot \
  "${SEGFILE2}" using (\$1/1000):8 with lines lc rgb "#e41a1c" title "Ax", \
  "${SEGFILE2}" using (\$1/1000):9 with lines lc rgb "#377eb8" title "Ay", \
  "${SEGFILE2}" using (\$1/1000):10 with lines lc rgb "#4daf4a" title "Az"
EOF

      echo "    Gráfica de evento generada: $PNG"
    done

  done < "$EVTFILE"

  rm -f "$EVTFILE"
}

# ==================== ACCIÓN 4 (TODO: principal + eventos) ====================

accion_graficas() {
  accion_grafica_principal
  accion_graficas_eventos
}

# ==================== ACCIÓN 5: TODO ====================

accion_todo() {
  accion_mapa
  accion_gpx
  accion_log_copia
  accion_graficas
}

# ==================== MENÚ ====================

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
  echo "4) Generar gráficas (principal + eventos)"
  echo "5) Hacer TODO (1–4)"
  echo "0) Salir"
  echo
  read -rp "Elige opción: " opt

  case "$opt" in
    1) accion_mapa ;;
    2) accion_gpx ;;
    3) accion_log_copia ;;
    4) accion_graficas ;;
    5) accion_todo ;;
    0) exit 0 ;;
    *) echo "Opción no válida." ;;
  esac
}

# ==================== EJECUCIÓN ====================

find_log_file
create_output_dir
main_menu
