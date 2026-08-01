# Uso consentido de chats para mejorar modelos

- Estado: Diferida hasta después del MVP
- Última actualización: 2026-07-16
- Superficies afectadas: producto, privacidad, backend, móvil, datos, proveedores de IA
- Prioridad: Alta

## Resumen

Durante el MVP no se utilizarán chats para entrenar, evaluar o mejorar modelos. Los términos lo indicarán expresamente. El acceso limitado a conversaciones para diagnosticar y corregir bugs del servicio sí estará permitido con controles operativos y sin crear datasets de entrenamiento.

## Problema y motivación

Los chats de BetterCalories pueden revelar dieta, objetivos y datos relativos a salud. Reutilizarlos para una finalidad distinta del servicio sin una base y expectativas claras crea riesgo jurídico, ético y reputacional.

## Contexto actual verificado

El sistema conserva mensajes y transcripciones crudas y permite acceso administrativo, pero no se encontró una preferencia específica, registro de consentimiento, pipeline de desidentificación ni mecanismo de exclusión de datasets/modelos. La AEPD describe los datos de salud como especialmente protegidos; el EDPB exige evaluar caso por caso anonimato y base jurídica en modelos de IA y recomienda una DPIA antes de tratamientos con alto riesgo.

Fuentes regulatorias: [AEPD sobre datos de salud](https://www.aepd.es/areas-de-actuacion/salud/tus-derechos-en-relacion-con-tus-datos-de-salud), [EDPB Opinion 28/2024](https://www.edpb.europa.eu/documents/opinion-of-the-board-art-64/opinion-282024-on-certain-data-protection-aspects-related-to_en), [EDPB Guidelines 05/2020 sobre consentimiento](https://www.edpb.europa.eu/documents/guideline/guidelines-052020-on-consent-under-regulation-2016679_en) y [EDPB sobre DPIA](https://www.edpb.europa.eu/topics/accountability-and-compliance-tools/data-protection-impact-assessment_en).

## Objetivos

- Garantizar que ningún chat del MVP entra en entrenamiento, fine-tuning o evaluación de modelos.
- Permitir diagnóstico de bugs solo cuando el contenido sea necesario para mantener o corregir el servicio.
- Informar de ambas condiciones en términos y privacidad de manera comprensible.

## Fuera de alcance

- Declarar por esta ficha una base jurídica definitiva.
- Entrenar un modelo antes de completar revisión jurídica, DPIA y controles técnicos.
- Construir consentimiento, datasets o pipelines de mejora de modelos durante el MVP.

## Experiencia y flujo esperado

Los términos de servicio y el aviso de privacidad indicarán que los chats no se usan para entrenar o mejorar modelos durante el MVP. También explicarán que personal autorizado puede acceder de forma limitada al contenido cuando sea necesario para investigar y corregir un bug comunicado o detectado.

## Requisitos funcionales

- No debe existir ningún flujo que copie chats del MVP a datasets de entrenamiento, fine-tuning o evaluación de modelos.
- El diagnóstico de bugs debe limitar el acceso a personal autorizado, al caso concreto y al tiempo estrictamente necesario.
- El acceso para bugs debe quedar auditado sin duplicar el contenido en tickets o logs inseguros.
- Los proveedores no pueden reutilizar el contenido para entrenar sus propios modelos salvo un cambio futuro expresamente evaluado y autorizado.
- Los términos y privacidad deben distinguir claramente prestación/depuración del servicio frente a mejora de modelos.

## Casos límite y errores

- Un chat menciona salud o datos de otra persona.
- Una persona menor de edad o sin capacidad suficiente usa la cuenta.
- El dato ya fue agregado, evaluado o incorporado a un modelo.
- Cambian proveedor, finalidad o condiciones materiales del tratamiento.

## Criterios de aceptación

- Un test de extremo a extremo demuestra que ningún chat llega a datasets o procesos de mejora de modelos.
- Los accesos para investigar bugs identifican operador, motivo, conversación y momento sin copiar el texto al registro de auditoría.
- Personal no autorizado no puede consultar el contenido desde el panel administrativo.
- Términos, privacidad y condiciones de proveedores reflejan que no existe uso para entrenamiento durante el MVP.

## Impacto previsto en el proyecto

Términos y privacidad, permisos del panel administrativo, auditoría de accesos y configuración/contratos de proveedores.

## Supuestos

- Si una fase posterior activa mejora de modelos, la anonimización no podrá presumirse por eliminar nombre o email y esta definición deberá reabrirse antes de tratar datos.

## Decisiones confirmadas

- Durante el MVP los chats no se utilizarán para entrenar, evaluar ni mejorar modelos.
- Los términos de servicio indicarán expresamente esta exclusión.
- Los chats sí pueden consultarse de forma limitada para diagnosticar y corregir bugs del producto.
- El uso para bugs no autoriza crear datasets ni reutilizar el contenido para mejorar modelos.

## Preguntas abiertas

- Ninguna para el MVP. Si se plantea mejorar modelos en una fase posterior, deberá reabrirse esta ficha para decidir consentimiento, tipos de mejora, menores, proveedores y retirada.
