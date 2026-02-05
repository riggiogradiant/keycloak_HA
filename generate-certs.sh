#!/bin/bash

# Script para generar certificados SSL auto-firmados para Keycloak
# Para producción, usa certificados reales de Let's Encrypt o una CA

set -e

CERTS_DIR="./certs"
DAYS_VALID=365
HOSTNAME="${KC_HOSTNAME:-localhost}"
KEY_PASS="${KEY_STORE_PASS:-changeit}"

echo "🔐 Generando certificados SSL para Keycloak HA"
echo "================================================"
echo ""
echo "Hostname: $HOSTNAME"
echo "Válidos por: $DAYS_VALID días"
echo ""

# Crear directorio para certificados
mkdir -p "$CERTS_DIR"

# 1. Generar certificado y clave privada para Keycloak (formato PKCS12)
echo "📝 Generando certificado PKCS12 para Keycloak..."
keytool -genkeypair \
  -alias keycloak \
  -keyalg RSA \
  -keysize 2048 \
  -validity $DAYS_VALID \
  -keystore "$CERTS_DIR/keycloak.p12" \
  -storetype PKCS12 \
  -storepass "$KEY_PASS" \
  -keypass "$KEY_PASS" \
  -dname "CN=$HOSTNAME, OU=Keycloak, O=MyOrg, L=City, ST=State, C=ES" \
  -ext "SAN=DNS:$HOSTNAME,DNS:keycloak-node-1,DNS:keycloak-node-2,DNS:localhost,IP:127.0.0.1"

echo "✅ Certificado PKCS12 creado: $CERTS_DIR/keycloak.p12"
echo ""

# 2. Generar certificados para Nginx (formato PEM)
echo "📝 Generando certificados para Nginx..."

# Crear clave privada
openssl genrsa -out "$CERTS_DIR/nginx.key" 2048

# Crear certificado
openssl req -new -x509 \
  -key "$CERTS_DIR/nginx.key" \
  -out "$CERTS_DIR/nginx.crt" \
  -days $DAYS_VALID \
  -subj "/CN=$HOSTNAME/OU=Nginx/O=MyOrg/L=City/ST=State/C=ES" \
  -addext "subjectAltName=DNS:$HOSTNAME,DNS:localhost,IP:127.0.0.1"

echo "✅ Certificados Nginx creados:"
echo "   - $CERTS_DIR/nginx.crt"
echo "   - $CERTS_DIR/nginx.key"
echo ""

# 3. Mostrar información de los certificados
echo "📋 Información del certificado Keycloak:"
keytool -list -v -keystore "$CERTS_DIR/keycloak.p12" -storepass "$KEY_PASS" -storetype PKCS12 | head -20

echo ""
echo "================================================"
echo "✅ Certificados generados exitosamente"
echo "================================================"
echo ""
echo "⚠️  IMPORTANTE para PRODUCCIÓN:"
echo "   Estos son certificados AUTO-FIRMADOS para pruebas."
echo "   Para producción, obtén certificados de:"
echo "   - Let's Encrypt (gratis): https://letsencrypt.org/"
echo "   - Tu CA empresarial"
echo ""
echo "📁 Los certificados están en: $CERTS_DIR/"
echo ""
