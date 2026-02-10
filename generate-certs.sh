#!/bin/bash

echo "🔐 Generating SSL certificates..."

mkdir -p certs

# Generar certificado auto-firmado
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout certs/keycloak.key \
  -out certs/keycloak.crt \
  -days 365 \
  -subj "/CN=localhost/O=Keycloak/C=ES" \
  -addext "subjectAltName=DNS:localhost,DNS:keycloak-1,DNS:keycloak-2,IP:127.0.0.1" \
  2>/dev/null

# Convertir a PKCS12
openssl pkcs12 -export \
  -in certs/keycloak.crt \
  -inkey certs/keycloak.key \
  -out certs/keycloak.p12 \
  -name keycloak \
  -passout pass:changeit

# Dar permisos de lectura para que Docker pueda leerlo
chmod 644 certs/keycloak.p12
chmod 644 certs/keycloak.crt
chmod 600 certs/keycloak.key

echo "✅ Certificates generated in certs/"
