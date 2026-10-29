# Testes de performance (k6)

`load.js` sobe gradualmente até 20 usuários virtuais por 50 s, exercitando dashboard, extrato,
criação de lançamentos e health check. A execução falha se:

- mais de 1% das requisições falharem;
- o p95 de latência passar de 500 ms (800 ms no dashboard);
- menos de 99% dos checks passarem.

```bash
# com k6 instalado
k6 run -e API_URL=http://localhost:3333 perf/load.js
# ou via Docker
docker run --rm -i --network host -e API_URL=http://localhost:3333 grafana/k6 run - < perf/load.js
```

No CI, o job `performance` executa o mesmo script e publica o resumo como artefato.
