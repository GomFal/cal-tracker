# Límites de abuso y coste por endpoint

- Estado: Lista para planificación
- Última actualización: 2026-07-16
- Superficies afectadas: API, Nginx, autenticación, correo, LLM/STT, observabilidad
- Prioridad: Alta

## Resumen

Aplicar límites por identidad, IP y clase de operación para frenar fuerza bruta, spam y consumo no autorizado de proveedores de pago sin bloquear usos legítimos.

## Problema y motivación

Endpoints públicos y operaciones de IA/STT pueden amplificar abuso, coste y degradación del servicio si no tienen límites coordinados.

## Contexto actual verificado

No se encontraron controles de rate limiting en la API ni `limit_req` en Nginx. La confirmación de correo incorporada en `develop` evita emitir sesión al registrar por email, pero el registro puede seguir generando correo y registros pendientes; Google y cuentas verificadas acceden a operaciones costosas.

## Objetivos

- Limitar autenticación, registro/confirmación, recuperación, STT, agentes y demás operaciones costosas.
- Dar errores y tiempos de reintento consistentes.
- Observar presupuesto, abuso y falsos positivos por usuario, IP y endpoint.

## Requisitos funcionales

- Deben existir políticas diferenciadas para operaciones públicas, autenticadas y de coste externo.
- Autenticación, registro y recuperación admitirán como máximo 10 peticiones por minuto y por IP.
- El envío de correos se limitará a 3 por hora y dirección destinataria.
- LLM y STT admitirán conjuntamente 60 operaciones por hora y usuario, con un máximo de 2 simultáneas.
- Los límites autenticados deben priorizar identidad/cuota; la IP debe ser una señal adicional para redes compartidas.
- La respuesta `429` debe usar un contrato estable, incluir el tiempo de reintento y no revelar información sensible.
- Deben existir límites globales de emergencia y alertas de gasto/anomalía.
- Reintentos, streaming interrumpido y concurrencia deben contabilizarse de forma definida.

## Casos límite y errores

- NAT de universidades, empresas o familias.
- Ataques distribuidos contra una misma cuenta o correo.
- Petición de IA aceptada pero fallida antes de consumir el proveedor.

## Criterios de aceptación

- Pruebas repetidas superan cada umbral y reciben el error esperado sin invocar trabajo caro adicional.
- Usuarios distintos tras una IP compartida conservan capacidad razonable.
- Métricas distinguen bloqueo, coste evitado, coste consumido y falso positivo.
- Un operador puede activar un freno global auditable.

## Impacto previsto en el proyecto

Middleware API, proxy, contratos, móvil/web, métricas y configuración operativa.

## Decisiones confirmadas

- Se aplicarán los umbrales iniciales 10/minuto/IP para auth, 3 correos/hora/dirección y 60 LLM-STT/hora/usuario con concurrencia máxima 2.
- Los valores serán configurables sin cambiar código.
- El MVP no tendrá planes, pantalla de cuotas ni políticas diferenciadas por tipo de suscripción.

## Preguntas abiertas

- Ninguna para el alcance del MVP.
