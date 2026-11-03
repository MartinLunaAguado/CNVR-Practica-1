<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>CNVR - Grupo ${grupo}</title>
  <style>
    body { font-family: Arial, sans-serif; background: #f2f4f7; color: #1d2433; margin: 0; }
    main { max-width: 640px; margin: 60px auto; background: #fff; padding: 32px 40px;
           border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,.08); }
    h1   { margin-top: 0; font-size: 26px; }
    .pod { font-family: monospace; font-size: 22px; color: #0b5cad; }
    td   { padding: 4px 12px 4px 0; }
  </style>
</head>
<body>
  <main>
    <h1>Trabajo final CNVR - Grupo ${grupo}</h1>
    <p>Esta página la ha servido el Pod:</p>
    <p class="pod">__POD_NAME__</p>
    <table>
      <tr><td>Nodo</td><td>__NODE_NAME__</td></tr>
      <tr><td>IP del Pod</td><td>__POD_IP__</td></tr>
    </table>
    <p><small>Desplegado con Terraform sobre Kubernetes (Calico + Multus).</small></p>
  </main>
</body>
</html>
