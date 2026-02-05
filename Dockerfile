# Imagen de Keycloak con PostgreSQL pre-built
FROM quay.io/keycloak/keycloak:23.0

# Build para PostgreSQL en modo producción
RUN /opt/keycloak/bin/kc.sh build --db=postgres

# Usar el comando start optimized por defecto
CMD ["start", "--optimized"]
