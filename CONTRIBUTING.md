# Contribuir

Gracias por ayudar a mantener esta guía exacta y segura para principiantes.

## Principios editoriales

- Español claro como idioma principal; conserva nombres oficiales de servicios, APIs y comandos.
- Fuentes primarias para afirmaciones técnicas: documentación de AWS, Kubernetes o el proyecto propietario.
- No fijes una versión “actual” sin fecha, ciclo de revisión o consulta dinámica.
- Todo comando mutable debe declarar perfil, región, variables, efecto, estado esperado y rollback/cleanup.
- Costos, cambios de acceso y operaciones destructivas requieren una advertencia antes del comando.
- No uses capturas como única fuente técnica. Prefiere texto, tablas o Mermaid revisables por diff.
- Distingue laboratorio educativo de recomendación de producción.
- No afirmes compliance sin mecanismo, prueba, evidencia, responsable y excepciones.

## Flujo de cambio

1. Crea una rama corta desde `main`.
2. Modifica el capítulo más específico; evita convertir el README en un manual monolítico.
3. Añade enlaces directos a fuentes y fecha si el dato cambia con el tiempo.
4. Ejecuta:

   ```bash
   make check
   ```

   CI añade validación del schema de `eksctl` y de los manifiestos contra las versiones de Kubernetes documentadas.
   Para reproducirla localmente, instala con `pip --require-hashes` las dependencias bloqueadas en
   `requirements-ci.txt`, además de `eksctl` 0.230.0,
   `kubeconform` 0.8.0, `actionlint` 1.7.12 y ShellCheck 0.11.0, y ejecuta `make check-ci`.

   ```bash
   python3 -m pip install --require-hashes --requirement requirements-ci.txt
   make check-ci
   ```

   Si cambias una dependencia Python directa, edita `requirements-ci.in` y regenera el lock reproducible:

   ```bash
   uv pip compile requirements-ci.in --generate-hashes --universal --output-file requirements-ci.txt
   ```

5. Si el cambio afecta comandos AWS/EKS, registra versiones de herramientas, cuenta/región redactadas y resultado.
6. Abre un pull request usando la plantilla y declara explícitamente lo que no probaste.

## Checklist técnico

- [ ] `aws`, `eksctl` y `kubectl` se usan para la capa correcta.
- [ ] No hay placeholders con `<valor>` que el shell interprete como redirección.
- [ ] La identidad y el contexto se verifican antes de escribir o borrar.
- [ ] Operaciones asíncronas tienen waiter o comprobación de estado.
- [ ] Versiones de Kubernetes están en soporte estándar al crear.
- [ ] Imágenes/AMIs siguen soportadas y se fijan de forma reproducible.
- [ ] Add-ons se contrastan con la versión del clúster.
- [ ] La limpieza cubre recursos externos y verificación posterior.
- [ ] El lock Python, los checksums de binarios y el commit de schemas se actualizaron de forma verificable.

## Seguridad

No publiques secretos ni detalles explotables. Sigue [SECURITY.md](SECURITY.md) para reportes sensibles. Una inexactitud
no sensible puede usar la plantilla de issue correspondiente.

## Licencia de contribuciones

El repositorio aún no declara licencia. Antes de aceptar contribuciones externas sustantivas, el propietario debe elegir
y publicar una licencia y aclarar los términos de contribución.
