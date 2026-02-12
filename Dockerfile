# =============================================================================
# Dockerfile - Keycloak Optimizado para Producción
# =============================================================================
FROM quay.io/keycloak/keycloak:26.0.0 AS builder

# Habilitar health y metrics
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

# Configure a database vendor
ENV KC_DB=postgres

# Deshabilitar XA transactions (build time)
ENV KC_TRANSACTION_XA_ENABLED=false

WORKDIR /opt/keycloak

# Build optimizado para producción
RUN /opt/keycloak/bin/kc.sh build

# =============================================================================
# Production stage
# =============================================================================
FROM quay.io/keycloak/keycloak:26.0.0

# Copiar build optimizado
COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Variables de entorno por defecto (pueden sobrescribirse)
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_HTTP_ENABLED=false
ENV KC_HTTPS_ENABLED=true

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--optimized"]
