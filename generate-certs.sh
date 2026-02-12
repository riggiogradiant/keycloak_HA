#!/bin/bash
# =============================================================================
# Script de Generación de Certificados SSL/TLS
# Para uso en desarrollo/testing de Keycloak
# =============================================================================

set -e

CERT_DIR="certs"
DOMAIN="${CERT_DOMAIN:-localhost}"
DAYS="${CERT_DAYS:-3650}"

echo "=========================================="
echo "  Generador de Certificados SSL/TLS"
echo "=========================================="
echo ""
echo "  Dominio: $DOMAIN"
echo "  Validez: $DAYS días"
echo ""

# Crear directorio de certificados
mkdir -p "$CERT_DIR"

# Generar clave privada
echo "[1/3] Generando clave privada..."
openssl genrsa -out "$CERT_DIR/tls.key" 2048
echo "  ✅ Clave privada creada: $CERT_DIR/tls.key"

# Generar certificado autofirmado
echo ""
echo "[2/3] Generando certificado autofirmado..."
openssl req -new -x509 \
  -key "$CERT_DIR/tls.key" \
  -out "$CERT_DIR/tls.crt" \
  -days "$DAYS" \
  -subj "/C=ES/ST=Spain/L=Madrid/O=Development/OU=IT/CN=$DOMAIN" \
  -addext "subjectAltName=DNS:$DOMAIN,DNS:*.${DOMAIN},DNS:localhost,DNS:keycloak-nodo1,DNS:keycloak-nodo2,IP:127.0.0.1"

echo "  ✅ Certificado creado: $CERT_DIR/tls.crt"

# Mostrar información del certificado
echo ""
echo "[3/3] Información del certificado:"
echo "----------------------------------------"
openssl x509 -in "$CERT_DIR/tls.crt" -noout -subject -dates -ext subjectAltName

# Establecer permisos
chmod 600 "$CERT_DIR/tls.key"
chmod 644 "$CERT_DIR/tls.crt"

echo ""
echo "=========================================="
echo "  ✅ Certificados generados exitosamente"
echo "=========================================="
echo ""
echo "  Archivos creados:"
echo "    - $CERT_DIR/tls.key (clave privada)"
echo "    - $CERT_DIR/tls.crt (certificado)"
echo ""
echo "  ⚠️  ADVERTENCIA: Estos son certificados"
echo "      autofirmados solo para desarrollo."
echo "      NO usar en producción."
echo ""
