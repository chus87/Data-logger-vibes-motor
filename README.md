# Registrador de Vibraciones y GPS con ESP32

Este proyecto implementa un registrador portátil de vibraciones y datos GPS utilizando un ESP32.  
Su propósito principal es monitorizar vibraciones en una motocicleta (o cualquier otro vehículo), registrando también la posición, velocidad, orientación y eventos marcados manualmente.  
Los datos quedan guardados en una tarjeta microSD en formato CSV y pueden ser analizados posteriormente mediante un script en bash incluido en este repositorio.

---

## ✨ Características principales

- **Registro de aceleraciones** en los ejes X, Y y Z usando el sensor MPU6050.  
- **Registro de posición, velocidad y hora exacta** mediante un módulo GPS NEO-6M / NEO-7M / NEO-8M / NEO-M8N.  
- **Almacenamiento en microSD** en formato CSV optimizado.  
- **Generación automática de archivos GPX**, gráficas y enlace a mapa mediante un script bash.  
- **Detección de eventos** mediante un botón físico (por ejemplo, baches, comportamiento extraño, puntos de interés).  
- **Indicadores LED** de estado del GPS (fix/no fix).  
- **Sistema de selección automática de nombre del archivo**: `log_001.csv`, `log_002.csv`, etc.  
- **Consumo bajo y funcionamiento totalmente autónomo** alimentado por USB.

---

## 🔧 Componentes necesarios

- ESP32 (modelo con USB-C o micro-USB)  
- Acelerómetro MPU6050 (GY-521)  
- GPS NEO-6M / 7M / 8M / M8N  
- Módulo lector microSD (compatible 3.3V)  
- Tarjeta microSD  
- Botón pulsador (evento manual)  
- LED rojo (GPS sin fix)  
- LED verde (GPS con fix)  
- Resistencias para LEDs (330 Ω recomendadas)  
- Cableado  
- Placa de prototipado o PCB  
- Caja estanca (opcional, recomendado para moto)

---

## 🔌 Conexiones de hardware

### MPU6050 (I2C)
- VCC → 3V3  
- GND → GND  
- SCL → D22  
- SDA → D21  

### GPS (UART2)
- VCC → 3V3  
- GND → GND  
- TX → D16 (RX2)  
- RX → D17 (TX2)  

### microSD (SPI)
- VCC → 3V3  
- GND → GND  
- CS → D23  
- MOSI → D19  
- CLK → D18  
- MISO → D5  

### Botón de evento
- D15 → botón → GND  
- Incluye `INPUT_PULLUP` en el firmware.

### LEDs
- LED rojo → D2 → resistencia → GND  
- LED verde → D4 → resistencia → GND  

---

## 📝 Formato del archivo CSV generado

Cada línea del log contiene:
millis,fecha,hora,lat,lon,vel_kmh,sats,Ax,Ay,Az,evento,orientacion,gps_fix

Incluye un script que:

1. Genera un enlace para ver el último punto GPS en un mapa.  
2. Crea un archivo GPX con toda la ruta.  
3. Copia y limpia el log en formato listo para LibreOffice/Excel.  
4. Genera automáticamente una gráfica de aceleraciones + velocidad + eventos.  
5. Permite ejecutar cada acción por separado o todas juntas.  

El script detecta automáticamente si falta `gnuplot` y ofrece instalarlo.

---

## 🚀 Uso

1. Alimenta el ESP32 por USB.  
2. Espera a que el LED verde indique *GPS fix*.  
3. Inicia el viaje.  
4. Opcionalmente, marca eventos pulsando el botón.  
5. Extrae la microSD.  
6. En el ordenador, ejecuta el script.


El script generará:
- `ruta.gpx`
- `aceleraciones.png`
- `ultimo_punto_gps_valido.txt`
- `log_YYYY-MM-DD.csv` (limpio para hojas de cálculo)

---
## 📄 Licencia

Este proyecto está publicado bajo la **licencia MIT**, permitiendo modificar y reutilizar libremente el código, manteniendo el aviso de copyright.

---

## 🤝 Contribuciones

Las contribuciones son bienvenidas.  
Puedes abrir *issues*, enviar *pull requests* o proponer nuevas características.

---

## 🏍 Aplicaciones posibles

- Análisis de vibraciones en motocicletas  
- Registro de rutas para vehículos  
- Detección de irregularidades en carreteras  
- Seguimiento de maquinaria  
- Estudios de conducción y comportamiento dinámico  
- Proyectos educativos con sensores  

---

## 📬 Contacto

Si deseas mejorar o adaptar el proyecto, puedes abrir un issue en GitHub.

---
