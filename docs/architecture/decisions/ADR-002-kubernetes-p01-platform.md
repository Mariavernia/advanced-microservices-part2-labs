# ADR-002 — Plataforma P01 con seis servicios independientes

**Estado:** Accepted (training baseline)  
**Fecha:** 2026-11-09

## Contexto

P00 limita la aplicación a Orders e Inventory. P01 debe evidenciar problemas
de configuración, DNS, ciclo de vida de Pods y recursos en un sistema más amplio,
sin convertir la práctica en una formación de Spring.

## Decisión

Introducimos API Gateway (Spring Cloud Gateway), Payments, Shipping y Notifications.
Se mantienen Orders→Inventory y las identidades por namespace del laboratorio.
Gateway realiza routing; no toma decisiones de dominio.

Payments solo anuncia medios de prueba; Shipping devuelve cotizaciones deterministas;
Notifications solo muestra plantillas y el estado de una credencial simulada. Ninguna
acción cobra, envía mensajes ni contrata transportistas.

Externalizamos los destinos en dos ConfigMaps y entregamos una credencial sintética
a Notifications mediante un Secret creado dinámicamente en el namespace personal.
Declaramos requests/limits sin introducir todavía probes ni autoescalado.

## Consecuencias y límites

- Seis JVM por alumno: hay que validar dimensionamiento real antes del curso.
- La plataforma permite observar Service DNS y fallos propagados de configuración.
- **No es modelo de producción:** servicios single-replica, credencial ficticia,
  Gateway sin autenticación, ningún proveedor de pagos o correo conectado.
- Se evita incluir secretos reales o copias base64 en Git.
- Query/Projection entrará en P04, con persistencia y caché.
- Hay una dependencia externa pendiente: imágenes en ACR y pull desde AKS.
- Probes, degradación y autoescalado se reservan para P02.
